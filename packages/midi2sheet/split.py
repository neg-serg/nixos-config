#!/usr/bin/env python3
"""Split a single-track piano MIDI into treble (pitch >= threshold) and bass
(pitch < threshold) tracks so a notation tool can engrave a grand staff.

Pure stdlib. Handles running status, meta events (tempo/time-signature), and
writes a format-1, two-track MIDI with a piano program change per track.
"""

import argparse
import struct


def vlv(n):
    """Encode a variable-length quantity (most significant group first)."""
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def read_vlv(data, i):
    v = 0
    while True:
        c = data[i]
        i += 1
        v = (v << 7) | (c & 0x7F)
        if not c & 0x80:
            return v, i


def parse(path):
    data = open(path, "rb").read()
    assert data[0:4] == b"MThd", "not a MIDI file"
    fmt, ntrk, div = struct.unpack(">HHH", data[8:14])
    tracks = []
    i = 14
    for _ in range(ntrk):
        assert data[i : i + 4] == b"MTrk", "bad track tag at %d" % i
        ln = struct.unpack(">I", data[i + 4 : i + 8])[0]
        tracks.append(data[i + 8 : i + 8 + ln])
        i += 8 + ln
    return fmt, div, tracks


def decode_events(trk):
    """Decode a track chunk into (abs_tick, event) pairs with running status
    resolved. Channel events are (status, d1, d2) or (status, d1) tuples."""
    events = []
    j = 0
    tick = 0
    running = None
    while j < len(trk):
        d, j = read_vlv(trk, j)
        tick += d
        st = trk[j]
        if st == 0xFF:
            j += 1
            mt = trk[j]
            j += 1
            ml, j = read_vlv(trk, j)
            m = trk[j : j + ml]
            j += ml
            events.append((tick, (0xFF, mt, m)))
            running = None
        elif st & 0x80:
            running = st
            hi = st & 0xF0
            if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
                events.append((tick, (st, trk[j + 1], trk[j + 2])))
                j += 3
            elif hi in (0xC0, 0xD0):
                events.append((tick, (st, trk[j + 1])))
                j += 2
            else:
                events.append((tick, (st,)))
                j += 1
        else:
            # running status data bytes
            if running is None:
                raise ValueError("running status without context")
            hi = running & 0xF0
            if hi in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
                events.append((tick, (running, st, trk[j + 1])))
                j += 2
            elif hi in (0xC0, 0xD0):
                events.append((tick, (running, st)))
                j += 1
    return events


def encode_events(events):
    """Encode sorted (tick, event) pairs as an MTrk chunk with full status
    bytes (no running status)."""
    body = bytearray()
    prev = 0
    for tick, ev in events:
        body += vlv(tick - prev)
        prev = tick
        if ev[0] == 0xFF:
            _, mt, m = ev
            body += bytes([0xFF, mt]) + vlv(len(m)) + m
        else:
            body += bytes(ev)
    return b"MTrk" + struct.pack(">I", len(body)) + bytes(body)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", help="input MIDI file")
    ap.add_argument("output", help="output split MIDI file")
    ap.add_argument(
        "--threshold",
        type=int,
        default=60,
        help="split pitch (MIDI note number, default 60 = C4)",
    )
    args = ap.parse_args()

    fmt, div, tracks = parse(args.input)
    if fmt == 1:
        evs = []
        for trk in tracks:
            evs.extend(decode_events(trk))
    else:
        evs = decode_events(tracks[0])
    evs.sort(key=lambda e: e[0])

    treble = []
    bass = []
    tempo = 500000
    timesig = None
    for tick, ev in evs:
        if ev[0] == 0xFF:
            mt = ev[1]
            if mt == 0x51:
                tempo = struct.unpack(">I", b"\x00" + ev[2])[0]
                treble.append((tick, ev))
                bass.append((tick, ev))
            elif mt == 0x58:
                timesig = ev[2]
                treble.append((tick, ev))
                bass.append((tick, ev))
            elif mt == 0x2F:  # end of track
                treble.append((tick, ev))
                bass.append((tick, ev))
            continue
        st = ev[0]
        hi = st & 0xF0
        if hi == 0x90 and ev[2] > 0:
            pitch = ev[1]
            (treble if pitch >= args.threshold else bass).append((tick, ev))
        elif hi in (0x80, 0x90):  # note-off / velocity-0 note-on
            pitch = ev[1]
            note_off = (0x80 | (st & 0x0F), pitch, ev[2])
            (treble if pitch >= args.threshold else bass).append(
                (tick, note_off)
            )
        # control changes / pitch bend are dropped (not needed for notation)

    # Piano program change at tick 0 of each hand.
    treble.insert(0, (0, (0xC0, 0)))
    bass.insert(0, (0, (0xC0, 0)))
    for lst in (treble, bass):
        lst.sort(key=lambda e: e[0])

    header = b"MThd" + struct.pack(">IHHH", 6, 1, 2, div)
    with open(args.output, "wb") as f:
        f.write(header)
        f.write(encode_events(treble))
        f.write(encode_events(bass))
    print(
        "wrote %s (tempo=%d timesig=%s treble=%d bass=%d)"
        % (args.output, tempo, timesig, len(treble), len(bass))
    )


if __name__ == "__main__":
    main()
