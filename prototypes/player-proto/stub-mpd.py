#!/usr/bin/env python3
"""A tiny MPD stand-in for keys-test.sh.

Usage: stub-mpd.py PORT_FILE [--outputs] [--queue]

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
"""

import socket
import sys
import threading
import time

PORT_FILE = sys.argv[1]
WITH_OUTPUTS = "--outputs" in sys.argv[2:]
WITH_QUEUE = "--queue" in sys.argv[2:]

STATUS = (
    b"volume: 40\nrepeat: 0\nrandom: 0\nsingle: 0\nconsume: 0\n"
    + (b"playlistlength: 6\n" if WITH_QUEUE else b"playlistlength: 0\n")
    + b"state: stop\nOK\n"
)

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

SLOW = ("list ", "listplaylists", "outputs", "listplaylistinfo", "playlistinfo")


def reply(cmd):
    if cmd.startswith("status"):
        return STATUS
    if cmd.startswith("outputs"):
        return OUTPUTS if WITH_OUTPUTS else b"OK\n"
    if cmd.startswith("config"):
        return CONFIG if WITH_OUTPUTS else CONFIG_REFUSED
    if cmd.startswith("playlistinfo"):
        return QUEUE if WITH_QUEUE else b"OK\n"
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
