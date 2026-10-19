#!/usr/bin/env python3
"""A tiny MPD stand-in for keys-test.sh.

Usage: stub-mpd.py PORT_FILE [--outputs] [--queue] [--playlists]

Binds 127.0.0.1:0, writes the chosen port to PORT_FILE, then speaks just enough of the
protocol for the player to settle: a banner, `status`, and `OK` for everything else.

The replies answer a question the real daemon cannot answer on demand:

* an *empty* library and output list (`list`, `listplaylists`, `outputs` return nothing);
* `--outputs`: two configured audio outputs, one of them in the shape of an old daemon
  (no `plugin:` field) and a `config` reply that carries the blocks `outputs` cannot,
  so the plugin/device fallback is exercised;
* without `--outputs`: `config` is refused exactly like a real MPD refuses it to a
  non-local client, which is the branch the live daemon takes as well;
* `--queue`: six tracks whose titles and artists start with different letters, so a
  one-letter queue filter can match exactly one row and the test can prove the pane
  plays that row's *real* queue index instead of its position in the filtered view.

The list answers are delayed by 120 ms so the transient "loading" frame is observable
without racing the worker's 300 ms poll loop.

The settings, statistics and queue-editing replies exist because the app grows panes that
should be proved end to end instead of mocked. One line per reply, with the feature that
needs that shape:

* `crossfade` -> `crossfade: <stored>` — the crossfade row reads back what it wrote, so the
  bare query answers the stored number and not a constant;
* `crossfade <n>` -> `crossfade: <n>` — the echo (not a bare `OK`) is the value the row paints
  after a write, which is how a clamp that only happens in the widget becomes visible;
* `crossfade <bad>` -> `ACK [2@0] {crossfade} need a number in the range 0-20` — the row keeps
  its old value and shows the refusal, so the ACK text has to be the daemon's wording;
* `replay_gain_mode <mode>` -> `OK` — the settings toggle stores off|track|album|auto without
  echoing anything, exactly like the daemon it will talk to;
* `replay_gain_mode <bad>` -> `ACK [2@0] {replay_gain_mode} invalid replay gain mode: <mode>` —
  the toggle falls back to the stored mode and prints the reason it refused;
* `replay_gain_status` -> `replay_gain_mode: <stored>` — the pane's first read, where the key is
  `replay_gain_mode` and not `mode`, or the row shows "off" whatever was stored;
* `status` -> `crossfade:`, `replay_gain_mode:`, `playlist:`, `bitrate: 0`, `audio: 44100:16:2` —
  one poll feeds the settings rows, the queue-version watch and the now-playing format line;
* `shuffle` -> `OK` plus a new `playlist:` — the queue pane redraws on a version change only, so
  the bump is what proves a shuffle (same six rows and order) actually landed;
* `prio <n> <start>:<end>` -> `OK` plus version, or `ACK [2@0] {prio} Bad song index` for a
  priority outside 0-255 or a reversed range — the pane must leave its selection alone then;
* `update` / `rescan` -> `updating_db: 1` — the scan pane prints the job id while it waits, and
  a bare `OK` would make a running scan look finished;
* `stats` -> artists/albums/songs/uptime/db_playtime/db_update/playtime — the statistics pane
  formats all seven, and an empty library would otherwise report zeros everywhere;
* `load "<name>"` -> `OK` plus version, or `ACK [50@0] {load} no such playlist` — the playlist
  pane reports a name that vanished instead of replacing the queue with nothing;
* `rm "<name>" ["<uri>"]` -> `OK` plus version, or `ACK [50@0] {rm} no such playlist` — same
  branch, and a deleted name has to make a later `load` fail the same way;
* `seekcur <spec>` -> `OK`, or `ACK [2@0] {seekcur} Bad song index` on an empty queue — the
  progress bar snaps back on that ACK instead of showing a position nothing is playing;
* `addtagid` / `cleartagid` -> `OK` plus version, or `ACK [2@0] {addtagid} Bad song index` for an
  id the queue does not hold — the tag editor stays open and marks the row;
* `add <uri>` / `deleteid <id>` / `clear` -> `OK` plus version — the pane needs the redraw
  trigger, not a changed queue, since the queue stays the six stub tracks.

`--playlists` seeds two saved names (and lets `listplaylists` publish them), and `save "<name>"`
adds one, so both the `OK` and the `no such playlist` branch of `load`/`rm` are reachable without
restarting the stub.
"""

import socket
import sys
import threading
import time

PORT_FILE = sys.argv[1]
WITH_OUTPUTS = "--outputs" in sys.argv[2:]
WITH_QUEUE = "--queue" in sys.argv[2:]
# Canned artists/albums/browser content. Off by default: the empty-daemon suites assert on a
# library that answered with nothing, and that is a different test from one with content.
WITH_LIBRARY = "--library" in sys.argv[2:]
WITH_PLAYLISTS = "--playlists" in sys.argv[2:]

# Titles and artists are picked so every initial letter is unique across both columns: a
# filter of "w" matches only the artist of row 2, which is how the test tells a filter over
# the real queue from a filter that renumbers the pane.
TRACKS = [
    ("Aurora", "Zelda"),
    ("Bluebird", "Xavier"),
    ("Cascade", "Wendy"),
    ("Dust", "Victor"),
    ("Ember", "Ursula"),
    ("Fjord", "Tomas"),
]

# The queue ids are the `Id:` values the `playlistinfo` reply carries; `addtagid` and `cleartagid`
# address a song by id, so the range check has to come from the same table that produced them.
QUEUE_IDS = frozenset(index + 1 for index in range(len(TRACKS))) if WITH_QUEUE else frozenset()

# Daemon state outlives the socket: the app reconnects between polls and a test may read a setting
# back over a second connection, so a value written by `crossfade 12` must survive the connection
# that carried it. One lock is enough — every handler touches a few fields and the replies are tiny.
STATE = {
    # `crossfade: 0` is what a fresh daemon reports, so an untouched stub answers like a real one.
    "crossfade": 0,
    # Same reason: a daemon that was never told otherwise reports `off`.
    "replay_gain": "off",
    # The queue version starts at 1; every mutating command adds one. The queue pane uses the
    # change as its only redraw trigger, so a test can read `playlist:` twice to prove a refresh.
    "version": 1,
    # Names a later `load`/`rm` may refer to; `save` adds one, --playlists seeds two, so both the
    # OK and the "no such playlist" branch are reachable without a preceding save.
    "playlists": {"Stub Set", "Stub Best"} if WITH_PLAYLISTS else set(),
}
LOCK = threading.Lock()

QUEUE = b"".join(
    (
        f"file: stub/{index:02d}-{title.lower()}.flac\n"
        f"Title: {title}\n"
        f"Artist: {artist}\n"
        f"Time: {120 + index}\n"
        f"Pos: {index}\n"
        f"Id: {index + 1}\n"
    ).encode()
    for index, (title, artist) in enumerate(TRACKS)
) + b"OK\n"

# Three outputs, three shapes of the same reply: the modern one (plugin and driver both
# present), a daemon older than 0.22 (no `plugin` at all, so the type has to come from
# `config`), and one whose plugin and driver are the same word (MPD 0.22/0.23) so the
# rendered second line has something to collapse.
OUTPUTS = (
    b"outputid: 0\n"
    b"outputname: Stub Pipe\n"
    b"plugin: pulse\n"
    b"driver: pipewire\n"
    b"outputenabled: 1\n"
    b"outputid: 1\n"
    b"outputname: Stub Fifo\n"
    b"driver: fifo\n"
    b"outputenabled: 0\n"
    b"outputid: 2\n"
    b"outputname: Stub Repeat\n"
    b"plugin: alsa\n"
    b"driver: alsa\n"
    b"outputenabled: 1\n"
    b"OK\n"
)

CONFIG = (
    b'config: music_directory "/var/lib/mpd/music"\n'
    b"config: audio_output {\n"
    b'config:   name "Stub Pipe"\n'
    b'config:   type "pulse"\n'
    b'config:   device "stub-device-0"\n'
    b"config: }\n"
    b"config: audio_output {\n"
    b'config:   name "Stub Fifo"\n'
    b'config:   type "alsa"\n'
    b'config:   device "/tmp/stub.fifo"\n'
    b"config: }\n"
    b"OK\n"
)

CONFIG_REFUSED = b"ACK [4@0] {config} Command only permitted to local clients\n"

# The library is empty, so a count can only come from the stub: real numbers, none of them the
# sum of the six stub tracks, keep a pane that recomputes or prints a placeholder visible.
STATS = (
    b"artists: 6\n"
    b"albums: 6\n"
    b"songs: 6\n"
    b"uptime: 4242\n"
    b"db_playtime: 4221\n"
    b"db_update: 1700000000\n"
    b"playtime: 0\n"
    b"OK\n"
)

# `update` and `rescan` are long jobs in a real daemon, so their reply is a job id rather than a
# bare `OK`; a fixed id keeps the "scan started" line reachable without a second command.
UPDATING = b"updating_db: 1\nOK\n"

CROSSFADE_MAX = 20
REPLAY_GAIN_MODES = ("off", "track", "album", "auto")

SLOW = ("list ", "listplaylists", "outputs", "listplaylistinfo", "playlistinfo")


def split_args(text):
    """Split the argument part of a command line into MPD arguments.

    MPD quotes an argument with `"` and escapes only `"` and `\\` inside it, so `load "My \\"x\\""`
    has to yield `My "x"` — the app escapes playlist names exactly this way before sending them,
    and a stub that matched the raw text would refuse every name it just accepted from a `save`.
    """
    args = []
    i = 0
    while i < len(text):
        while i < len(text) and text[i] == " ":
            i += 1
        if i >= len(text):
            break
        if text[i] == '"':
            i += 1
            word = []
            while i < len(text) and text[i] != '"':
                if text[i] == "\\" and i + 1 < len(text) and text[i + 1] in '"\\':
                    i += 1
                word.append(text[i])
                i += 1
            i += 1  # the closing quote
            args.append("".join(word))
        else:
            start = i
            while i < len(text) and text[i] != " ":
                i += 1
            args.append(text[start:i])
    return args


def bump_version():
    """The one mutation the queue pane can observe: it polls `playlist:` and redraws on change."""
    with LOCK:
        STATE["version"] += 1


def status_reply(args):
    """`status`, grown with the fields the new panes read.

    The original keys keep their order and values (`playlistlength` and `state: stop` are what
    the empty/queue runs assert on); the new ones slot in around them: `crossfade` and
    `replay_gain_mode` are the settings rows, `playlist` is the queue version the pane watches,
    and `bitrate`/`audio` are what a real daemon prints for a running output, so now-playing
    formats a real line instead of "unknown" even though the stub never plays.
    """
    with LOCK:
        crossfade = STATE["crossfade"]
        gain = STATE["replay_gain"]
        version = STATE["version"]
    return (
        b"volume: 40\nrepeat: 0\nrandom: 0\nsingle: 0\nconsume: 0\n"
        + f"crossfade: {crossfade}\n".encode()
        + f"replay_gain_mode: {gain}\n".encode()
        + f"playlist: {version}\n".encode()
        + (
            b"playlistlength: 6\nsong: 2\nsongid: 3\n"
            if (WITH_QUEUE and WITH_LIBRARY)
            else b"playlistlength: 6\n"
            if WITH_QUEUE
            else b"playlistlength: 0\n"
        )
        + b"state: stop\n"
        + b"bitrate: 0\n"
        + b"audio: 44100:16:2\n"
        + b"OK\n"
    )


def crossfade_reply(args):
    """`crossfade` / `crossfade <0..20>`.

    The bare form reports the stored value instead of a constant, which is the only way a test
    can tell that `crossfade 12` reached the daemon and not just a widget. The set form echoes the
    value inside the reply body: the daemon answers `crossfade: 12`, and the row paints that, so a
    stub replying a bare `OK` would hide a broken echo. Out of range is one ACK whose text names
    both the command and the bounds, because the row keeps its old value and prints that text.
    """
    if not args:
        with LOCK:
            current = STATE["crossfade"]
        return f"crossfade: {current}\nOK\n".encode()
    try:
        value = int(args[0])
    except ValueError:
        value = -1
    if not 0 <= value <= CROSSFADE_MAX:
        return b"ACK [2@0] {crossfade} need a number in the range 0-20\n"
    with LOCK:
        STATE["crossfade"] = value
    return f"crossfade: {value}\nOK\n".encode()


def replay_gain_mode_reply(args):
    """`replay_gain_mode <off|track|album|auto>`: store the mode, answer `OK`.

    The mode is remembered because `replay_gain_status` and `status` report it later — a stub that
    forgot it would make every read-back test pass for the wrong reason. A mode outside the four is
    refused with the daemon's own ACK, which the settings row turns into its error line.
    """
    if len(args) != 1:
        return b"ACK [2@0] {replay_gain_mode} wrong number of arguments\n"
    mode = args[0]
    if mode not in REPLAY_GAIN_MODES:
        return f"ACK [2@0] {{replay_gain_mode}} invalid replay gain mode: {mode}\n".encode()
    with LOCK:
        STATE["replay_gain"] = mode
    return b"OK\n"


def replay_gain_status_reply(args):
    """`replay_gain_status`: the stored mode under the key the pane reads (`replay_gain_mode`)."""
    with LOCK:
        mode = STATE["replay_gain"]
    return f"replay_gain_mode: {mode}\nOK\n".encode()


def stats_reply(args):
    """`stats`: the seven numbers the statistics pane formats, none of them a placeholder zero."""
    return STATS


def update_reply(args):
    """`update [uri]` / `rescan [uri]`: hand back the job id, the way a real scan-start reply does."""
    return UPDATING


def shuffle_reply(args):
    """`shuffle [<start:end>]`: `OK` plus a version bump.

    The rows and their order stay the six stub tracks, so the version is the whole signal: it is
    the only thing the pane polls, which is what lets a test prove the shuffle reached the daemon.
    """
    bump_version()
    return b"OK\n"


def prio_reply(args):
    """`prio <0..255> <start>:<end>`.

    A valid range answers `OK` and moves the version; every invalid one answers the single ACK the
    pane treats as "keep the selection": a priority outside 0-255, a reversed range, or a bound
    that is not a number. Nothing is bumped on a refusal, so a failed edit cannot look like a redraw.
    """
    if len(args) != 2:
        return b"ACK [2@0] {prio} wrong number of arguments\n"
    try:
        priority = int(args[0])
        start, _, end = args[1].partition(":")
        start = int(start)
        end = int(end)
    except ValueError:
        return b"ACK [2@0] {prio} Bad song index\n"
    if not 0 <= priority <= 255 or start < 0 or start > end:
        return b"ACK [2@0] {prio} Bad song index\n"
    bump_version()
    return b"OK\n"


def listplaylists_reply(args):
    """`listplaylists`: one `playlist:` line per saved name, empty unless `--playlists` is given.

    The default run asserts the app says "nothing here" rather than inventing rows, so the empty
    answer is the default and the flag is what gives the playlist pane rows to `load` and `rm`.
    """
    if not WITH_PLAYLISTS:
        return b"OK\n"
    with LOCK:
        names = sorted(STATE["playlists"])
    return b"".join(f"playlist: {name}\n".encode() for name in names) + b"OK\n"


def save_reply(args):
    """`save "<name>"`: `OK` (unchanged) plus remembering the name.

    This is the only way a test can create a playlist the stub will then `load`; the reply body
    stays byte-identical to the previous stand-in, since a real daemon's is a bare `OK` too.
    """
    if len(args) == 1:
        with LOCK:
            STATE["playlists"].add(args[0])
    return b"OK\n"


def load_reply(args):
    """`load "<name>"`: replace the queue with a saved playlist.

    The name arrives quoted, so it is unquoted before it is matched; an unknown one is refused with
    code 50 ("no such playlist") exactly like a real daemon, which is the branch the pane paints as
    "not found" instead of emptying the queue. A successful load changes the queue, so it bumps.
    """
    if len(args) != 1:
        return b"ACK [2@0] {load} wrong number of arguments\n"
    with LOCK:
        known = args[0] in STATE["playlists"]
    if not known:
        return b"ACK [50@0] {load} no such playlist\n"
    bump_version()
    return b"OK\n"


def rm_reply(args):
    """`rm "<name>" ["<uri>"]`: delete a saved playlist, or one entry of it.

    The same "no such playlist" ACK covers an unknown name; deleting the whole playlist also drops
    the name from the known set, so a later `load` of it fails the same way a real daemon would. A
    single-entry `rm` (the optional uri) keeps the playlist, so only the version moves.
    """
    if len(args) not in (1, 2):
        return b"ACK [2@0] {rm} wrong number of arguments\n"
    with LOCK:
        known = args[0] in STATE["playlists"]
    if not known:
        return b"ACK [50@0] {rm} no such playlist\n"
    if len(args) == 1:
        with LOCK:
            STATE["playlists"].discard(args[0])
    bump_version()
    return b"OK\n"


def seekcur_reply(args):
    """`seekcur <12.5|+5|-5|50%>`: `OK`, or `Bad song index` when there is nothing to seek in.

    The app sends `seekcur <seconds>`, but a real daemon also takes a signed offset (seek by 5 s)
    and a percentage (seek to 50%), which is what the progress bar's coarser jumps use. The empty
    queue is checked before the argument, because that ACK is what makes the bar snap back instead
    of showing a position nothing is playing; a malformed spec only matters in --queue mode, where
    the daemon has a song and still refuses the time.
    """
    if not WITH_QUEUE:
        return b"ACK [2@0] {seekcur} Bad song index\n"
    if len(args) != 1 or not valid_seek(args[0]):
        return b"ACK [2@0] {seekcur} Bad seek parameter\n"
    return b"OK\n"


def valid_seek(spec):
    """The seek shapes the app can produce: `12.5`, `+5`, `-5`, `50%`, a rounded `61.200`."""
    if spec.endswith("%"):
        spec = spec[:-1]
    try:
        float(spec)
    except ValueError:
        return False
    return True


def tag_edit_reply(verb, args):
    """`addtagid <songid> <tag> <value>` / `cleartagid <songid> [<tag>]`.

    The tag editor addresses a queue entry by id, so the check has to use the ids `playlistinfo`
    published and refuse anything else with `Bad song index`: that ACK is what keeps the editor open
    and marks the row, instead of closing on a write that went nowhere. `cleartagid` also accepts
    the id alone, which is how "drop every tag on this song" is sent. A tag edit rewrites one queue
    entry, and a real daemon moves the queue version for that too, so the row is re-read.
    """
    wanted = (3,) if verb == "addtagid" else (1, 2)
    if len(args) not in wanted:
        return f"ACK [2@0] {{{verb}}} wrong number of arguments\n".encode()
    try:
        songid = int(args[0])
    except ValueError:
        return f"ACK [2@0] {{{verb}}} Bad song index\n".encode()
    if songid not in QUEUE_IDS:
        return f"ACK [2@0] {{{verb}}} Bad song index\n".encode()
    bump_version()
    return b"OK\n"


def add_reply(args):
    """`add <uri>`: append one song; the pane only needs the version to reload the queue."""
    if not args:
        return b"ACK [2@0] {add} wrong number of arguments\n"
    bump_version()
    return b"OK\n"


def deleteid_reply(args):
    """`deleteid <id>`: `OK` without a range check.

    The app only deletes an id it just read from `playlistinfo`, and the stub cannot model a queue
    that shrinks — refusing ids the stub itself published would fail a correct app, so every
    well-formed id is accepted and the version bump is the part that proves the pane reloaded.
    """
    if len(args) != 1:
        return b"ACK [2@0] {deleteid} wrong number of arguments\n"
    bump_version()
    return b"OK\n"


def clear_reply(args):
    """`clear`: `OK` plus a version bump — emptying the queue is the largest possible redraw."""
    bump_version()
    return b"OK\n"


# Tag lists behind the browser and the pickers. One set of names, deliberately distinct from the
# queue's, so a test can tell which pane it is looking at by its contents alone.
ARTISTS = ("Aurora", "Bluebird", "Cascade")
ALBUMS = ("Aurora - Zelda", "Bluebird - Xavier", "Cascade - Wendy")
# `lsinfo /` shows one directory and one file: enough for the browser to have a cursor, a
# directory to enter and a song to play.
BROWSER = (
    b"directory: stub/Sub\n"
    b"Last-Modified: 2024-01-01T00:00:00Z\n"
    b"file: stub/01-aurora.flac\n"
    b"Title: Aurora\n"
    b"Artist: Zelda\n"
    b"Time: 120\n"
    b"OK\n"
)

# What `search` and `find` answer: the same song, so the search pane has rows to draw.
FOUND = (
    b"file: stub/01-aurora.flac\n"
    b"Title: Aurora\n"
    b"Artist: Zelda\n"
    b"Time: 120\n"
    b"OK\n"
)


def currentsong_reply(args):
    """The track `status` claims is playing, in the queue's own shape.

    `A` in the Playlists pane sends `playlistadd <name> <uri>` with the *playing* song's file,
    and the now-playing pane prints its tags: both need a real `currentsong`, not an empty reply.
    """
    if not (WITH_QUEUE and WITH_LIBRARY):
        return b"OK\n"
    title, artist = TRACKS[2]
    return (
        f"file: stub/02-{title.lower()}.flac\n"
        f"Title: {title}\n"
        f"Artist: {artist}\n"
        "Time: 122\n"
        "Pos: 2\n"
        "Id: 3\n"
        "OK\n"
    ).encode()


def list_reply(args):
    """`list <tag>` for the pickers: three artists, three albums, two playlists.

    Only in `--library` mode: the empty-daemon suites ("an empty library must say so") depend on
    this answering `OK` and nothing else.
    """
    if not WITH_LIBRARY:
        return b"OK\n"
    tag = args[0].lower() if args else ""
    names = {"artist": ARTISTS, "album": ALBUMS, "playlist": ("pop", "rock")}.get(tag, ())
    return b"".join(f"{tag.title()}: {name}\n".encode() for name in names) + b"OK\n"


def lsinfo_reply(args):
    return BROWSER if WITH_LIBRARY else b"OK\n"


def find_reply(args):
    return FOUND if WITH_LIBRARY else b"OK\n"


HANDLERS = {
    "currentsong": currentsong_reply,
    "list": list_reply,
    "lsinfo": lsinfo_reply,
    "find": find_reply,
    "search": find_reply,
    "crossfade": crossfade_reply,
    "replay_gain_mode": replay_gain_mode_reply,
    "replay_gain_status": replay_gain_status_reply,
    "stats": stats_reply,
    "update": update_reply,
    "rescan": update_reply,
    "shuffle": shuffle_reply,
    "prio": prio_reply,
    "listplaylists": listplaylists_reply,
    "save": save_reply,
    "load": load_reply,
    "rm": rm_reply,
    "seekcur": seekcur_reply,
    "addtagid": lambda args: tag_edit_reply("addtagid", args),
    "cleartagid": lambda args: tag_edit_reply("cleartagid", args),
    "add": add_reply,
    "deleteid": deleteid_reply,
    "clear": clear_reply,
}


def reply(cmd):
    # The verb decides the handler, the rest is arguments: an exact match keeps `add` from eating
    # `addtagid` and `status` from eating nothing at all (`stats` shares the prefix but not a verb).
    verb, _, rest = cmd.partition(" ")
    if cmd.startswith("status"):
        return status_reply(split_args(rest))
    if cmd.startswith("outputs"):
        return OUTPUTS if WITH_OUTPUTS else b"OK\n"
    if cmd.startswith("config"):
        return CONFIG if WITH_OUTPUTS else CONFIG_REFUSED
    if cmd.startswith("playlistinfo"):
        return QUEUE if WITH_QUEUE else b"OK\n"
    handler = HANDLERS.get(verb)
    if handler is not None:
        return handler(split_args(rest))
    return b"OK\n"


def serve(conn):
    conn.sendall(b"OK MPD 0.23.5\n")
    buf = b""
    while True:
        try:
            chunk = conn.recv(4096)
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            cmd = raw.decode("utf-8", "replace").strip()
            if cmd.startswith(SLOW):
                time.sleep(0.12)
            conn.sendall(reply(cmd))


def main():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(8)
    with open(PORT_FILE, "w") as fh:
        fh.write(str(srv.getsockname()[1]))
        fh.flush()
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=serve, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
