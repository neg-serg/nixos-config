"""A minimal MPD client speaking the plain-text wire protocol.

Only the standard library is used: the daemon protocol is line based
(``command arg1 arg2\\n`` -> ``Key: value`` lines -> ``OK`` or ``ACK``), so a
few helpers replace a third-party dependency.  The client is deliberately
small; it covers playback, queue, modes, playlists and library search, which
is everything a voice front-end needs.
"""

from __future__ import annotations

import os
import socket
from collections.abc import Iterable, Sequence

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 6600
DEFAULT_TIMEOUT = 10.0
GREETING_PREFIX = "OK MPD "

# Maximum number of commands in one MPD command list (server side limit is
# generous; chunking keeps a huge album from blowing the server's input
# buffer).
_COMMAND_LIST_CHUNK = 200

# Tags accepted by `search`/`find`.  `any` matches every tag (MPD >= 0.21).
SEARCH_TAGS = frozenset(
    {
        "any",
        "file",
        "artist",
        "albumartist",
        "album",
        "title",
        "genre",
        "date",
        "composer",
        "performer",
        "name",
    }
)


class MPDError(Exception):
    """The server answered with ``ACK`` (command level failure)."""

    def __init__(
        self,
        code: int,
        message: str,
        command: tuple[str, ...] = (),
    ) -> None:
        self.code = code
        self.message = message
        self.command = command
        super().__init__(f"MPD error {code}: {message}")


class MPDConnectionError(Exception):
    """Transport level failure: no daemon, timeout, closed connection."""


def quote(argument: str) -> str:
    """Quote one protocol argument the way libmpdclient does."""
    if argument and not any(ch in argument for ch in ' \t"\\\n'):
        return argument
    escaped = argument.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def split_pairs(lines: Iterable[str]) -> list[tuple[str, str]]:
    """Turn ``Key: value`` protocol lines into pairs (garbage is skipped)."""
    pairs: list[tuple[str, str]] = []
    for line in lines:
        key, separator, value = line.partition(": ")
        if separator:
            pairs.append((key, value))
    return pairs


def song_dict(pairs: Iterable[tuple[str, str]]) -> dict[str, str]:
    """Flatten pairs into a metadata dict with lower-cased keys.

    MPD capitalises tag names (``Title``, ``AlbumArtist``); the rest of the
    client speaks lowercase, so the translation happens once, here.
    """
    result: dict[str, str] = {}
    for key, value in pairs:
        key = key.lower()
        if key in result:
            result[key] = f"{result[key]}, {value}"
        else:
            result[key] = value
    return result


def songs_from(pairs: Iterable[tuple[str, str]]) -> list[dict[str, str]]:
    """Group protocol pairs into song dicts (a song starts at ``file``).

    MPD repeats keys for songs with several artists/tags; repeated values are
    joined with ``", "`` so callers can print them directly.
    """
    songs: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for key, value in pairs:
        key = key.lower()
        if key == "file":
            current = {"file": value}
            songs.append(current)
        elif current is not None:
            if key in current:
                current[key] = f"{current[key]}, {value}"
            else:
                current[key] = value
    return songs


def _parse_ack(line: str) -> tuple[int, str]:
    body = line[len("ACK") :].strip()
    code_token, _, rest = body.partition("@")
    try:
        code = int(code_token.strip().lstrip("["))
    except ValueError:
        code = 0
    _, _, message = rest.partition("]")
    message = message.strip()
    if message.startswith("{") and "}" in message:
        message = message.split("}", 1)[1].strip()
    return code, message or line


class MPDClient:
    """Blocking MPD client; every call opens the socket on first use."""

    def __init__(
        self,
        host: str | None = None,
        port: int | None = None,
        password: str | None = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        env = os.environ
        self.host = host or env.get("MPD_HOST") or DEFAULT_HOST
        self.port = int(port or env.get("MPD_PORT") or DEFAULT_PORT)
        self.password = password or env.get("MPD_PASSWORD")
        self.timeout = timeout
        self.version: str | None = None
        self._sock: socket.socket | None = None
        self._reader = None

    # -- transport -----------------------------------------------------
    def connect(self) -> MPDClient:
        if self._sock is not None:
            return self
        try:
            sock = socket.create_connection(
                (self.host, self.port), self.timeout
            )
        except OSError as exc:
            raise MPDConnectionError(
                f"cannot reach MPD at {self.host}:{self.port}: {exc}"
            ) from exc
        sock.settimeout(self.timeout)
        self._sock = sock
        self._reader = sock.makefile("rb")
        greeting = self._read_line()
        if not greeting.startswith(GREETING_PREFIX):
            self.close()
            raise MPDConnectionError(f"bad MPD greeting: {greeting!r}")
        self.version = greeting[len(GREETING_PREFIX) :].strip()
        if self.password:
            self.command("password", self.password)
        return self

    def close(self) -> None:
        if self._reader is not None:
            try:
                self._reader.close()
            except OSError:
                pass
            self._reader = None
        if self._sock is not None:
            try:
                self._sock.close()
            except OSError:
                pass
            self._sock = None
        self.version = None

    def __enter__(self) -> MPDClient:
        return self.connect()

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def _read_line(self) -> str:
        if self._reader is None:
            raise MPDConnectionError("not connected")
        try:
            raw = self._reader.readline()
        except socket.timeout as exc:
            raise MPDConnectionError(
                f"timed out waiting for MPD at {self.host}:{self.port}"
            ) from exc
        except OSError as exc:
            raise MPDConnectionError(f"MPD connection lost: {exc}") from exc
        if not raw:
            raise MPDConnectionError("MPD closed the connection")
        return raw.decode("utf-8", errors="replace").rstrip("\r\n")

    def _send(self, payload: str) -> None:
        if self._sock is None:
            raise MPDConnectionError("not connected")
        try:
            self._sock.sendall(payload.encode("utf-8"))
        except OSError as exc:
            raise MPDConnectionError(f"MPD connection lost: {exc}") from exc

    # -- protocol ------------------------------------------------------
    def command(self, *args: object) -> list[tuple[str, str]]:
        """Run one command and return its ``Key: value`` pairs."""
        self.connect()
        self._send(" ".join(quote(str(arg)) for arg in args) + "\n")
        lines: list[str] = []
        while True:
            line = self._read_line()
            if line == "OK":
                return split_pairs(lines)
            if line.startswith("ACK"):
                code, message = _parse_ack(line)
                raise MPDError(code, message, tuple(str(a) for a in args))
            lines.append(line)

    def command_list(
        self, commands: Sequence[Sequence[object]]
    ) -> list[list[tuple[str, str]]]:
        """Run commands atomically-ish; returns pairs per command."""
        self.connect()
        payload = ["command_list_begin"]
        payload += [
            " ".join(quote(str(arg)) for arg in command)
            for command in commands
        ]
        payload.append("command_list_end")
        self._send("\n".join(payload) + "\n")
        results: list[list[tuple[str, str]]] = []
        current: list[str] = []
        while True:
            line = self._read_line()
            if line == "OK":
                return results
            if line == "list_OK":
                results.append(split_pairs(current))
                current = []
                continue
            if line.startswith("ACK"):
                code, message = _parse_ack(line)
                raise MPDError(code, message, ("command_list",))
            current.append(line)

    # -- playback ------------------------------------------------------
    def status(self) -> dict[str, str]:
        return dict(self.command("status"))

    def current_song(self) -> dict[str, str]:
        return song_dict(self.command("currentsong"))

    def queue(self) -> list[dict[str, str]]:
        return songs_from(self.command("playlistinfo"))

    def song_at(self, position: int) -> dict[str, str]:
        found = songs_from(self.command("playlistinfo", position))
        return found[0] if found else {}

    def play(self, position: int | None = None) -> None:
        if position is None:
            self.command("play")
        else:
            self.command("play", position)

    def pause(self, paused: bool = True) -> None:
        self.command("pause", 1 if paused else 0)

    def resume(self) -> None:
        self.command("pause", 0)

    def toggle_pause(self) -> bool:
        """Pause when playing, resume when paused; True when now paused."""
        was_playing = self.status().get("state") == "play"
        self.pause(was_playing)
        return was_playing

    def stop(self) -> None:
        self.command("stop")

    def next(self) -> None:
        self.command("next")

    def previous(self) -> None:
        self.command("previous")

    # -- volume --------------------------------------------------------
    def volume(self) -> int | None:
        raw = self.status().get("volume")
        if raw is None:
            return None
        try:
            value = int(raw)
        except ValueError:
            return None
        return value if value >= 0 else None

    def set_volume(self, value: int) -> int:
        clamped = max(0, min(100, int(value)))
        self.command("setvol", clamped)
        return clamped

    def adjust_volume(self, delta: int) -> int | None:
        current = self.volume()
        if current is None:
            return None
        return self.set_volume(current + delta)

    # -- seek ----------------------------------------------------------
    def seek_relative(self, seconds: float) -> None:
        sign = "+" if seconds >= 0 else ""
        self.command("seekcur", f"{sign}{seconds:g}")

    def seek_to(self, seconds: float) -> None:
        self.command("seekcur", f"{max(0.0, seconds):g}")

    # -- modes ---------------------------------------------------------
    def _mode(self, name: str, enabled: bool) -> bool:
        self.command(name, 1 if enabled else 0)
        return enabled

    def set_random(self, enabled: bool) -> bool:
        return self._mode("random", enabled)

    def set_repeat(self, enabled: bool) -> bool:
        return self._mode("repeat", enabled)

    def set_single(self, enabled: bool) -> bool:
        return self._mode("single", enabled)

    def set_consume(self, enabled: bool) -> bool:
        return self._mode("consume", enabled)

    def mode(self, name: str) -> bool:
        return self.status().get(name) == "1"

    def flip_mode(self, name: str) -> bool:
        return self._mode(name, not self.mode(name))

    def set_crossfade(self, seconds: int) -> int:
        value = max(0, int(seconds))
        self.command("crossfade", value)
        return value

    # -- queue and library --------------------------------------------
    def clear(self) -> None:
        self.command("clear")

    def add(self, uri: str) -> None:
        self.command("add", uri)

    def add_many(self, uris: Iterable[str]) -> int:
        """Append many URIs, using MPD command lists when possible."""
        items = list(uris)
        for start in range(0, len(items), _COMMAND_LIST_CHUNK):
            chunk = items[start : start + _COMMAND_LIST_CHUNK]
            try:
                self.command_list([("add", uri) for uri in chunk])
            except (MPDError, MPDConnectionError):
                # Older servers (or a queue being edited concurrently) may
                # refuse a command list; fall back to plain `add` calls.
                for uri in chunk:
                    self.add(uri)
        return len(items)

    def search(self, tag: str, needle: str) -> list[dict[str, str]]:
        if tag not in SEARCH_TAGS:
            raise ValueError(f"unsupported search tag: {tag}")
        return songs_from(self.command("search", tag, needle))

    def search_any(self, needle: str) -> list[dict[str, str]]:
        return self.search("any", needle)

    def find(self, tag: str, needle: str) -> list[dict[str, str]]:
        if tag not in SEARCH_TAGS:
            raise ValueError(f"unsupported search tag: {tag}")
        return songs_from(self.command("find", tag, needle))

    # -- playlists -----------------------------------------------------
    def playlists(self) -> list[str]:
        return [
            value
            for key, value in self.command("listplaylists")
            if key == "playlist"
        ]

    def playlist_songs(self, name: str) -> list[dict[str, str]]:
        return songs_from(self.command("listplaylistinfo", name))

    def load_playlist(self, name: str) -> None:
        self.command("load", name)

    def save_playlist(self, name: str) -> None:
        self.command("save", name)

    def delete_playlist(self, name: str) -> None:
        self.command("rm", name)

    # -- misc ----------------------------------------------------------
    def update(self, path: str = "") -> None:
        if path:
            self.command("update", path)
        else:
            self.command("update")

    def stats(self) -> dict[str, str]:
        return dict(self.command("stats"))

    def ping(self) -> None:
        self.command("ping")
