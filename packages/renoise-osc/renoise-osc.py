#!/usr/bin/env python3
"""renoise-osc — send OSC to the Renoise built-in OSC server (UDP :9002).

Usage:
  renoise-osc [--host H] [--port P] [--dry] <command> [args...]
  renoise-osc help [command]

Commands:
  status | eval '<lua>' | reverb [--track master|N] [--wet X]
  load '<plugin>'                     new instrument + VST (default Legend HZ)
  transport <start|stop|continue|panic|toggle>
  bpm <20..999> | lpb <1..255> | tpl <1..16>
  loop <pattern|block> <on|off> | loop-sequence <start> <end>
  track <idx|-1> mute|unmute|solo|volume|volume-db|post|post-db|pan [value]
  instr <idx|-1> volume-db|transpose <value> | macro <1..8> <0..1>
  device <track> <device> bypass <on|off>
  record [--out FILE] [--secs N] [--target NODE]
  <osc-pattern> [args...]             raw OSC message
--dry prints the OSC message instead of sending. Default port from env
RENOISE_OSC_PORT; protocol UDP (apply while Renoise is closed with
renoise-osc-config). See docs/howto/renoise-tidal-live.ru.md.
"""

import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_HOST = os.environ.get("RENOISE_OSC_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("RENOISE_OSC_PORT", "9002"))


def osc_string(b: bytes) -> bytes:
    return b + b"\x00" * (4 - (len(b) % 4))


def build_message(pattern: str, args):
    tags = b","
    payload = b""
    for a in args:
        if isinstance(a, bool):
            tags += b"T" if a else b"F"
        elif isinstance(a, float):
            tags += b"f"
            payload += struct.pack(">f", a)
        elif isinstance(a, int):
            tags += b"i"
            payload += struct.pack(">i", a)
        else:
            tags += b"s"
            payload += osc_string(str(a).encode("utf-8"))
    return osc_string(pattern.encode("utf-8")) + osc_string(tags) + payload


def udp_port_bound(host: str, port: int) -> bool:
    needle = f":{port:04X}"
    for table in ("/proc/net/udp", "/proc/net/udp6"):
        try:
            with open(table, encoding="ascii") as fh:
                for line in fh.readlines()[1:]:
                    if needle in line:
                        return True
        except OSError:
            continue
    return False


def renoise_running() -> bool:
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm", encoding="ascii") as fh:
                comm = fh.read().strip()
        except OSError:
            continue
        if comm.startswith("renoise"):
            return True
    return False


def start_renoise(host: str, port: int, wait_secs: int = 45) -> bool:
    if udp_port_bound(host, port):
        return True
    print("renoise not running - starting it ...")
    try:
        subprocess.Popen(
            ["renoise"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except OSError as exc:
        print(f"failed to start renoise: {exc}", file=sys.stderr)
        return False
    deadline = time.monotonic() + wait_secs
    while time.monotonic() < deadline:
        if udp_port_bound(host, port):
            return True
        time.sleep(1)
    print(
        f"renoise OSC UDP port {port} did not open within {wait_secs}s "
        f"— check Preferences -> OSC (protocol UDP, port {port}).",
        file=sys.stderr,
    )
    return False


def parse_num(s, what):
    try:
        return float(s)
    except ValueError:
        print(f"invalid {what}: {s!r}", file=sys.stderr)
        raise SystemExit(2)


def bool_arg(s, what):
    low = s.lower()
    if low in ("on", "true", "1", "yes"):
        return True
    if low in ("off", "false", "0", "no"):
        return False
    print(f"invalid boolean for {what}: {s!r} (use on/off)", file=sys.stderr)
    raise SystemExit(2)


def lua_reverb(track_sel: str, wet):
    if track_sel == "master":
        sel = (
            "local s=renoise.song() local t "
            "for _,x in ipairs(s.tracks) do if x.type==2 then t=x end end"
        )
    else:
        try:
            idx = int(track_sel)
        except ValueError:
            print(
                f"ignoring non-numeric track selector: {track_sel!r}",
                file=sys.stderr,
            )
            idx = 1
        sel = f"local s=renoise.song() local t=s.tracks[{idx}]"
    lua = (
        f"local ok,err=pcall(function() {sel} "
        "local d=nil for _,i in ipairs(t.available_device_infos) do "
        "if string.lower(i.name)=='reverb' then "
        "d=t:insert_device_at(i.path,#t.devices+1) break end end"
    )
    if wet is not None:
        lua += (
            f" if d then for _,p in ipairs(d.parameters) do "
            f"if p.name=='Send' then p.value={wet:.4f} end end end"
        )
    lua += " end) if not ok then print('renoise-reverb error: '..tostring(err)) end"
    return lua


def lua_load_plugin(name: str) -> str:
    esc = name.replace("\\", "\\\\").replace("'", "\\'")
    lower = name.lower().replace("'", "")
    lua = (
        "local ok,err=pcall(function() "
        "local s=renoise.song() "
        "local inst=s:insert_instrument_at(#s.instruments+1) "
        "local path=nil "
        "for _,i in ipairs(inst.plugin_properties.available_plugin_infos) do "
        f"if string.lower(i.name):find('{lower}',1,true) then path=i.path break end "
        "end "
        f"if not path then error('plugin not found: {esc}') end "
        "inst.plugin_properties:load_plugin(path) "
        "s.selected_instrument_index=#s.instruments "
        "end) "
        "if not ok then print('renoise-load error: '..tostring(err)) end"
    )
    return lua


def lua_transport_toggle() -> str:
    return (
        "if renoise.transport.playing then renoise.transport:stop() "
        "else renoise.transport:start() end"
    )


TRACK_OPS = {
    "mute": ("mute", 0),
    "unmute": ("unmute", 0),
    "solo": ("solo", 0),
    "volume": ("prefx_volume", 1),
    "volume-db": ("prefx_volume_db", 1),
    "post": ("postfx_volume", 1),
    "post-db": ("postfx_volume_db", 1),
    "pan": ("prefx_panning", 1),
}
INSTR_OPS = {"volume-db": "volume_db", "transpose": "transpose"}

TOPIC_HELP = {
    "record": "renoise-osc record [--out FILE] [--secs N] [--target NODE]\n"
    "  Default: ~/src/art/music/renoise/recordings/renoise-<ts>.wav on the\n"
    "  game-stereo sink (renoise-link feeds it); --target renoise captures\n"
    "  only Renoise. Offline render stays GUI: File -> Export Audio.",
    "loop": "renoise-osc loop <pattern|block> <on|off>\n"
    "renoise-osc loop-sequence <start> <end>",
    "transport": "renoise-osc transport <start|stop|continue|panic|toggle>",
}


def send(host, port, pattern, args=(), dry=False):
    msg = build_message(pattern, args)
    if dry:
        print(f"[dry] {pattern} {list(args)!r} ({len(msg)} bytes)")
        return 0
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.sendto(msg, (host, port))
    except OSError as exc:
        print(f"send to {host}:{port} failed: {exc}", file=sys.stderr)
        return 1
    finally:
        sock.close()
    print(f"{pattern} -> {host}:{port} ({len(msg)} bytes)")
    return 0


def cmd_status(host, port):
    running = renoise_running()
    bound = udp_port_bound(host, port)
    print(f"Renoise running:     {'yes' if running else 'no'}")
    print(f"OSC UDP {host}:{port}: {'bound' if bound else 'not bound'}")
    if not running and not bound:
        print(
            "start it with: renoise-osc load 'Legend HZ' (or just 'renoise')"
        )
        return 1
    if running and not bound:
        print(
            "Renoise is up but the OSC UDP port is closed — check Preferences -> OSC:",
            file=sys.stderr,
        )
        return 1
    return 0


def cmd_transport(host, port, action, dry):
    if action == "toggle":
        return send(
            host, port, "/renoise/evaluate", [lua_transport_toggle()], dry
        )
    if action in ("start", "stop", "continue", "panic"):
        return send(host, port, f"/renoise/transport/{action}", (), dry)
    print(
        "usage: renoise-osc transport <start|stop|continue|panic|toggle>",
        file=sys.stderr,
    )
    return 2


def cmd_timing(host, port, kind, value, dry):
    lo, hi = {"bpm": (20, 999), "lpb": (1, 255), "tpl": (1, 16)}[kind]
    v = max(lo, min(hi, parse_num(value, kind)))
    return send(host, port, f"/renoise/song/{kind}", [v], dry)


def cmd_loop(host, port, argv, dry):
    if len(argv) == 3 and argv[0] == "sequence":
        return send(
            host,
            port,
            "/renoise/transport/loop/sequence",
            [parse_num(argv[1], "start"), parse_num(argv[2], "end")],
            dry,
        )
    if len(argv) == 2:
        low = {"pattern": "loop/pattern", "block": "loop/block"}.get(argv[0])
        if low:
            return send(
                host,
                port,
                f"/renoise/transport/{low}",
                [bool_arg(argv[1], argv[0])],
                dry,
            )
    print(TOPIC_HELP["loop"], file=sys.stderr)
    return 2


def cmd_track(host, port, argv, dry):
    if len(argv) < 2:
        print(
            "usage: renoise-osc track <idx|-1> <mute|unmute|solo|volume|volume-db|post|post-db|pan> [value]",
            file=sys.stderr,
        )
        return 2
    idx, op = argv[0], argv[1]
    if op not in TRACK_OPS:
        print("track ops: " + ", ".join(TRACK_OPS), file=sys.stderr)
        return 2
    suffix, nvals = TRACK_OPS[op]
    vals = argv[2 : 2 + nvals]
    if len(vals) != nvals:
        print(f"track {op}: expected {nvals} value(s)", file=sys.stderr)
        return 2
    args = [parse_num(v, "value") for v in vals]
    return send(host, port, f"/renoise/song/track/{idx}/{suffix}", args, dry)


def cmd_instr(host, port, argv, dry):
    if len(argv) < 2:
        print(
            "usage: renoise-osc instr <idx|-1> <volume-db|transpose> <value> | macro <k> <val>",
            file=sys.stderr,
        )
        return 2
    idx, op = argv[0], argv[1]
    if op == "macro":
        if len(argv) != 4:
            print(
                "usage: renoise-osc instr <idx> macro <1..8> <0..1>",
                file=sys.stderr,
            )
            return 2
        k = int(parse_num(argv[2], "macro index"))
        if not 1 <= k <= 8:
            print("macro index must be 1..8", file=sys.stderr)
            return 2
        return send(
            host,
            port,
            f"/renoise/song/instrument/{idx}/macro{k}",
            [parse_num(argv[3], "value")],
            dry,
        )
    if op not in INSTR_OPS or len(argv) != 3:
        print(
            "instr ops: volume-db <db> | transpose <st> | macro <k> <val>",
            file=sys.stderr,
        )
        return 2
    return send(
        host,
        port,
        f"/renoise/song/instrument/{idx}/{INSTR_OPS[op]}",
        [parse_num(argv[2], "value")],
        dry,
    )


def cmd_device(host, port, argv, dry):
    if len(argv) != 4 or argv[2] != "bypass":
        print(
            "usage: renoise-osc device <track> <device> bypass <on|off>",
            file=sys.stderr,
        )
        return 2
    return send(
        host,
        port,
        f"/renoise/song/track/{argv[0]}/device/{argv[1]}/bypass",
        [bool_arg(argv[3], "bypass")],
        dry,
    )


def cmd_record(host, port, argv, dry):
    out = None
    secs = None
    target = "playback.game-stereo"
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--out" and i + 1 < len(argv):
            out = Path(argv[i + 1])
            i += 2
        elif a == "--secs" and i + 1 < len(argv):
            secs = max(0.0, parse_num(argv[i + 1], "--secs"))
            i += 2
        elif a == "--target" and i + 1 < len(argv):
            target = argv[i + 1]
            i += 2
        else:
            print(f"unknown record arg: {a}", file=sys.stderr)
            return 2
    if dry:
        shown = (
            str(out)
            if out
            else "<~/src/art/music/renoise/recordings/renoise-<ts>.wav>"
        )
        cmd = ["pw-record", "--target", target, "--rate", "48000"]
        if secs:
            cmd += ["-n", str(int(secs * 48000))]
        cmd.append(shown)
        print("[dry] " + " ".join(cmd))
        return 0
    if not udp_port_bound(host, port):
        print(
            "renoise OSC not bound — is Renoise running? (renoise-osc status)",
            file=sys.stderr,
        )
        return 1
    if out is None:
        outdir = Path.home() / "src/art/music/renoise/recordings"
        outdir.mkdir(parents=True, exist_ok=True)
        out = outdir / f"renoise-{time.strftime('%Y%m%d-%H%M%S')}.wav"
    cmd = ["pw-record", "--target", target, "--rate", "48000"]
    if secs:
        # pw-record has no --duration; stop after N samples at 48 kHz.
        cmd += ["-n", str(int(secs * 48000))]
    cmd.append(str(out))
    print(
        "Recording Renoise ("
        + target
        + ") -> "
        + str(out)
        + ("" if secs else "   Ctrl+C to stop.")
    )
    status = subprocess.run(cmd).returncode
    if status != 0:
        print(f"pw-record exited with {status}", file=sys.stderr)
        return 1
    return 0


def cmd_help(topic=None):
    if topic:
        text = TOPIC_HELP.get(topic)
        print(text if text else f"no extended help for {topic!r}")
        print()
    print(__doc__)
    return 0


def main(argv):
    host, port = DEFAULT_HOST, DEFAULT_PORT
    dry = False
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--host" and i + 1 < len(argv):
            host = argv[i + 1]
            i += 2
        elif a == "--port" and i + 1 < len(argv):
            try:
                port = int(argv[i + 1])
            except ValueError:
                print(
                    f"invalid --port value: {argv[i + 1]!r}", file=sys.stderr
                )
                return 2
            i += 2
        elif a == "--dry":
            dry = True
            i += 1
        elif a in ("-h", "--help"):
            return cmd_help()
        else:
            rest.append(a)
            i += 1
    if not rest:
        return cmd_help()
    cmd = rest[0]
    tail = rest[1:]
    if cmd == "help":
        return cmd_help(tail[0] if tail else None)
    if cmd == "status":
        return cmd_status(host, port)
    if cmd == "eval":
        return send(host, port, "/renoise/evaluate", [" ".join(tail)], dry)
    if cmd == "reverb":
        track_sel, wet = "master", None
        j = 0
        while j < len(tail):
            a = tail[j]
            if a == "--track" and j + 1 < len(tail):
                track_sel = tail[j + 1]
                j += 2
            elif a == "--wet" and j + 1 < len(tail):
                wet = max(0.0, min(1.0, parse_num(tail[j + 1], "--wet")))
                j += 2
            else:
                j += 1
        return send(
            host, port, "/renoise/evaluate", [lua_reverb(track_sel, wet)], dry
        )
    if cmd == "load":
        plugin = " ".join(tail).strip() or "Legend HZ"
        if not start_renoise(host, port):
            return 1
        return send(
            host, port, "/renoise/evaluate", [lua_load_plugin(plugin)], dry
        )
    if cmd == "transport":
        if not tail:
            return cmd_help("transport")
        return cmd_transport(host, port, tail[0], dry)
    if cmd in ("bpm", "lpb", "tpl"):
        if len(tail) != 1:
            print(f"usage: renoise-osc {cmd} <value>", file=sys.stderr)
            return 2
        return cmd_timing(host, port, cmd, tail[0], dry)
    if cmd == "loop":
        return cmd_loop(host, port, tail, dry)
    if cmd == "track":
        return cmd_track(host, port, tail, dry)
    if cmd == "instr":
        return cmd_instr(host, port, tail, dry)
    if cmd == "device":
        return cmd_device(host, port, tail, dry)
    if cmd == "record":
        return cmd_record(host, port, tail, dry)
    args = []
    for a in tail:
        try:
            args.append(float(a))
        except ValueError:
            args.append(a)
    return send(host, port, cmd, args, dry)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
