#!/usr/bin/env python3
"""The producer behind the player's live instrument (the `spectroscope` plugin).

`aurora --scope-fifo=PATH` reads a text pipe of decimal samples — whitespace or comma separated,
one value per line or a whole frame per line — at the rate `--scope-rate` names. This script turns
the audio the player is actually playing into that text: `pw-record` hands it raw f32le mono frames
on stdin, it writes the numbers to the FIFO.

Two details are load-bearing:

* The FIFO is opened for writing *without* O_NONBLOCK. The player's reader treats EOF as "the
  producer is gone" and re-opens the path on its next frame, so a producer that gives up between
  frames never overlaps with the reader long enough to be seen — the instrument then sits dead
  while this process believes it is feeding. A blocking open parks this process until the player
  opens the read end, which is exactly the start-up order the two of them have.
* Nothing is buffered here while nobody reads: a write blocks, so a parked player does not hand
  the instrument a backlog of stale audio the moment it is shown again.

The sample rate belongs to the caller (`pw-record --rate`), and the player is told the same number
because its own fallback is MPD's `audio:` line — the format of the stream the daemon *decodes*, not
of the sink monitor this captures.
"""

import os
import struct
import sys

# Samples per text line and bytes per stdin read. 64 samples is ~450 bytes on the wire and ~750
# lines/s at 48 kHz — small enough that the renderer never waits for a line, large enough that the
# per-line overhead is noise. 4096 bytes is 1024 frames: ~21 ms of audio per read.
BATCH = 64
READ = 4096


def attach(path):
    """Block until the player holds the read end, then keep the write end for good."""
    return os.open(path, os.O_WRONLY)


def emit(out, values):
    lines = [
        " ".join("%.4f" % v for v in values[i : i + BATCH])
        for i in range(0, len(values), BATCH)
    ]
    os.write(out, ("\n".join(lines) + "\n").encode())


def main():
    fifo = sys.argv[1]
    out = attach(fifo)
    carry = b""
    while True:
        chunk = sys.stdin.buffer.read(READ)
        if not chunk:
            break
        carry += chunk
        whole = len(carry) // 4 * 4
        if not whole:
            # A read may split a frame; the tail waits for the next one.
            continue
        body, carry = carry[:whole], carry[whole:]
        try:
            emit(out, struct.unpack("<%df" % (whole // 4), body))
        except OSError:
            # The player closed the read end: it quit, or `--scope-fifo` moved. Wait for it to come
            # back instead of dying — this runs as a session service, not as one player's child.
            os.close(out)
            out = attach(fifo)


if __name__ == "__main__":
    main()
