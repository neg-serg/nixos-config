"""An in-process MPD daemon: enough of the wire protocol to test the client.

The server speaks real MPD protocol bytes (greeting, ``Key: value`` replies,
``OK``/``ACK``, command lists) on a loopback port, so tests exercise the same
paths a deployed daemon would.
"""

from __future__ import annotations

import shlex
import socketserver
import threading

GREETING = "OK MPD 0.24.0"

DEFAULT_TRACKS: list[dict[str, object]] = [
    {
        "file": "Agalloch/The Mantle/01 - Falling Snow.flac",
        "Title": "Falling Snow",
        "Artist": "Agalloch",
        "AlbumArtist": "Agalloch",
        "Album": "The Mantle",
        "Genre": "Doom Metal",
        "Date": "2002",
        "Time": 545,
    },
    {
        "file": "Agalloch/The Mantle/02 - The Hawthorne Passage.flac",
        "Title": "The Hawthorne Passage",
        "Artist": "Agalloch",
        "AlbumArtist": "Agalloch",
        "Album": "The Mantle",
        "Genre": "Doom Metal",
        "Date": "2002",
        "Time": 588,
    },
    {
        "file": "Evoken/Antithesis of Light/06 - Antithesis of Light.flac",
        "Title": "Antithesis of Light",
        "Artist": "Evoken",
        "AlbumArtist": "Evoken",
        "Album": "Antithesis of Light",
        "Genre": "Funeral Doom",
        "Date": "2005",
        "Time": 737,
    },
    {
        "file": "Various/Ambient/01 - Drone One.flac",
        "Title": "Drone One",
        "Album": "Ambient Sampler",
        "Genre": "Ambient",
        "Time": 300,
    },
]


class Ack(Exception):
    """Protocol level error, reported as ``ACK [...]`` to the client."""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def _song_lines(track: dict[str, object], pos: int | None = None) -> list[str]:
    lines = []
    if pos is not None:
        lines.append(f"Pos: {pos}")
        lines.append(f"Id: {pos + 1}")
    lines.append(f"file: {track['file']}")
    for key, value in track.items():
        if key == "file":
            continue
        lines.append(f"{key}: {value}")
    return lines


class FakeMPD:
    """Small stand-in for mpd(1); call :meth:`start` then point a client at it."""

    def __init__(
        self,
        tracks: list[dict[str, object]] | None = None,
        playlists: dict[str, list[str]] | None = None,
    ) -> None:
        self.tracks = list(tracks if tracks is not None else DEFAULT_TRACKS)
        self.queue: list[dict[str, object]] = []
        self.playlists = {
            name: list(items) for name, items in (playlists or {}).items()
        }
        self.volume = 50
        # Outputs without a mixer report -1 and ignore setvol (see MPD docs).
        self.volume_supported = True
        self.modes = {
            "repeat": 0,
            "random": 0,
            "single": 0,
            "consume": 0,
        }
        self.crossfade = 0
        self.state = "stop"
        self.position = 0
        self.updated: list[str] = []
        self.commands: list[str] = []
        self.command_lists = 0
        self.host = "127.0.0.1"
        self.port = 0
        self._server: _Server | None = None
        self._thread: threading.Thread | None = None

    # -- lifecycle -----------------------------------------------------
    def start(self) -> FakeMPD:
        server = _Server((self.host, 0), _Handler)
        server.fake = self  # type: ignore[attr-defined]
        self._server = server
        self.port = server.server_address[1]
        self._thread = threading.Thread(
            target=server.serve_forever, daemon=True
        )
        self._thread.start()
        return self

    def stop(self) -> None:
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None

    def __enter__(self) -> FakeMPD:
        return self.start()

    def __exit__(self, *_exc: object) -> None:
        self.stop()

    # -- state helpers -------------------------------------------------
    def current(self) -> dict[str, object] | None:
        if not self.queue or self.position >= len(self.queue):
            return None
        return self.queue[self.position]

    def status_lines(self) -> list[str]:
        lines = [
            f"volume: {self.volume if self.volume_supported else -1}",
            f"repeat: {self.modes['repeat']}",
            f"random: {self.modes['random']}",
            f"single: {self.modes['single']}",
            f"consume: {self.modes['consume']}",
            f"crossfade: {self.crossfade}",
            "partition: default",
            f"playlistlength: {len(self.queue)}",
            f"state: {self.state}",
            f"bitrate: {self.volume if self.state == 'play' else 0}",
        ]
        if self.queue:
            lines += [
                f"song: {self.position}",
                f"songid: {self.position + 1}",
                f"time: {0}:{int(self.current()['Time'])}",
                "elapsed: 0.0",
                f"duration: {float(self.current()['Time'])}",
            ]
        return lines

    def run(self, argv: list[str]) -> list[str]:
        """Execute one command; returns reply lines (without the final OK)."""
        self.commands.append(" ".join(argv))
        name = argv[0]
        args = argv[1:]

        if name in ("ping", "close"):
            return []
        if name == "status":
            return self.status_lines()
        if name == "currentsong":
            track = self.current()
            return _song_lines(track, self.position) if track else []
        if name == "playlistinfo":
            if args:
                index = int(args[0])
                if index >= len(self.queue):
                    raise Ack(50, "Bad song index")
                return _song_lines(self.queue[index], index)
            lines: list[str] = []
            for index, track in enumerate(self.queue):
                lines += _song_lines(track, index)
            return lines
        if name == "stats":
            return [
                f"artists: {len({t.get('Artist') for t in self.tracks})}",
                "albums: 3",
            ]
        if name == "clear":
            self.queue = []
            self.position = 0
            self.state = "stop"
            return []
        if name == "add":
            uri = args[0] if args else ""
            track = next(
                (item for item in self.tracks if item["file"] == uri), None
            )
            if track is None:
                raise Ack(50, "No such directory")
            self.queue.append(track)
            return []
        if name == "play":
            if not self.queue:
                raise Ack(52, "No song loaded")
            if args:
                self.position = int(args[0])
                if self.position >= len(self.queue):
                    raise Ack(50, "Bad song index")
            self.state = "play"
            return []
        if name == "pause":
            if args and args[0] == "1":
                self.state = "pause"
            else:
                self.state = "play" if self.queue else "stop"
            return []
        if name == "stop":
            self.state = "stop"
            return []
        if name == "next":
            if self.position + 1 < len(self.queue):
                self.position += 1
            self.state = "play"
            return []
        if name == "previous":
            if self.position > 0:
                self.position -= 1
            self.state = "play"
            return []
        if name == "setvol":
            if self.volume_supported:
                self.volume = max(0, min(100, int(args[0])))
            return []
        if name == "seekcur":
            return []
        if name in self.modes:
            self.modes[name] = int(args[0])
            return []
        if name == "crossfade":
            self.crossfade = int(args[0])
            return []
        if name in ("search", "find"):
            tag, needle = args[0], args[1]
            return self._search_lines(tag, needle)
        if name == "listplaylists":
            lines = []
            for playlist in sorted(self.playlists):
                lines += [
                    f"playlist: {playlist}",
                    "Last-Modified: 2026-01-01T00:00:00Z",
                ]
            return lines
        if name == "listplaylistinfo":
            return [
                f"file: {item}" for item in self.playlists.get(args[0], [])
            ]
        if name == "load":
            if args[0] not in self.playlists:
                raise Ack(50, "No such playlist")
            for item in self.playlists.get(args[0], []):
                track = next(
                    (track for track in self.tracks if track["file"] == item),
                    None,
                )
                if track is not None:
                    self.queue.append(track)
            return []
        if name == "save":
            self.playlists[args[0]] = [item["file"] for item in self.queue]
            return []
        if name == "rm":
            self.playlists.pop(args[0], None)
            return []
        if name == "update":
            self.updated.append(args[0] if args else "")
            return []
        raise Ack(5, f"unknown command {name!r}")

    def _search_lines(self, tag: str, needle: str) -> list[str]:
        needle = needle.lower()
        lines: list[str] = []
        for track in self.tracks:
            if tag == "any":
                haystack = [str(value) for value in track.values()]
            else:
                haystack = [
                    str(value)
                    for key, value in track.items()
                    if key.lower() == tag.lower()
                ]
            if any(needle in value.lower() for value in haystack):
                lines += _song_lines(track)
        return lines


class _Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        fake: FakeMPD = self.server.fake  # type: ignore[attr-defined]
        self.wfile.write(f"{GREETING}\n".encode())
        in_list = False
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            if line == "command_list_begin":
                in_list = True
                fake.command_lists += 1
                continue
            if line == "command_list_end":
                in_list = False
                self.wfile.write(b"OK\n")
                continue
            argv = shlex.split(line)
            if not argv:
                if in_list:
                    self.wfile.write(b"list_OK\n")
                continue
            try:
                reply = fake.run(argv)
            except Ack as ack:
                self.wfile.write(
                    f"ACK [{ack.code}@0] {{{argv[0]}}} {ack.message}\n".encode()
                )
                return
            for item in reply:
                self.wfile.write(f"{item}\n".encode())
            self.wfile.write(b"list_OK\n" if in_list else b"OK\n")
