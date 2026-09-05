#!/usr/bin/env python3
"""renoise-osc - send OSC messages to the Renoise built-in OSC server.

Usage:
  renoise-osc [--host H] [--port P] eval '<lua expression>'
  renoise-osc [--host H] [--port P] reverb [--track master|N] [--wet X]
  renoise-osc [--host H] [--port P] load '<plugin name>'
  renoise-osc [--host H] [--port P] transport <start|stop|continue|panic|toggle>
  renoise-osc [--host H] [--port P] status
  renoise-osc [--host H] [--port P] <osc-pattern> [args...]

Defaults: 127.0.0.1:9002 (UDP), overridable with RENOISE_OSC_HOST /
RENOISE_OSC_PORT. Renoise Preferences -> OSC must be set to protocol UDP on
the same port -- run 'renoise-osc-config' to apply that to Config.xml while
Renoise is closed.

'eval' runs arbitrary Renoise Lua remotely via /renoise/evaluate.
'reverb' inserts the native Reverb FX: --track master (default) or a
1-based track number; --wet 0..1 sets the device Send parameter (default:
leave the preset value).
'load' inserts a new instrument and loads a VST plugin into it by name
(e.g. 'renoise-osc load Legend HZ'); starts Renoise first if needed.
'transport' wraps the documented /renoise/transport/* paths; 'toggle' maps
to a Lua transport start/stop based on the current playing state.
'status' reports whether Renoise is running and whether its OSC UDP port
is bound (no replies exist in the Renoise OSC API, so this is a local
process/port check, not a round-trip).

Bare numeric args become OSC floats; everything else is a string.
"""

import os
import socket
import struct
import subprocess
import sys
import time

DEFAULT_HOST = os.environ.get("RENOISE_OSC_HOST", "127.0.0.1")
DEFAULT_PORT = int(os.environ.get("RENOISE_OSC_PORT", "9002"))


def osc_string(b: bytes) -> bytes:
    return b + b"\x00" * (4 - (len(b) % 4))


def build_message(pattern: str, args):
    tags = b","
    payload = b""
    for a in args:
        if isinstance(a, float):
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
    """True once something listens on host:port (UDP) -- /proc scan, no bind."""
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
    """Scan /proc/<pid>/comm for the Renoise process (name may be truncated)."""
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
    """Start Renoise (pw-jack wrapper on PATH) and wait for the OSC UDP port."""
    if udp_port_bound(host, port):
        return True
    print("renoise not running - starting it ...")
    try:
        subprocess.Popen(
            ["renoise"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
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
        f"-- check Preferences -> OSC (protocol UDP, port {port}).",
        file=sys.stderr,
    )
    return False


def lua_reverb(track_sel: str, wet) -> str:
    """Build a single-chunk Lua expression: insert native Reverb on the
    master track or a specific track, optionally set its Send parameter."""
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
    """Insert a new instrument and load a VST plugin into it by name."""
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
    """Toggle playback; Renoise's OSC set has no toggle path, so use Lua."""
    return (
        "if renoise.transport.playing then renoise.transport:stop() "
        "else renoise.transport:start() end"
    )


def send(host: str, port: int, pattern: str, args) -> int:
    msg = build_message(pattern, args)
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


def cmd_status(host: str, port: int) -> int:
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
            "Renoise is up but the OSC UDP port is closed -- check "
            "Preferences -> OSC: server enabled, protocol UDP, port matches.",
            file=sys.stderr,
        )
        return 1
    return 0


def main(argv):
    host, port = DEFAULT_HOST, DEFAULT_PORT
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
        else:
            rest.append(a)
            i += 1
    if not rest:
        print(__doc__)
        return 2
    cmd = rest[0]
    if cmd == "eval":
        pattern, args = "/renoise/evaluate", [" ".join(rest[1:])]
    elif cmd == "reverb":
        track_sel, wet = "master", None
        j = 1
        while j < len(rest):
            a = rest[j]
            if a == "--track" and j + 1 < len(rest):
                track_sel = rest[j + 1]
                j += 2
            elif a == "--wet" and j + 1 < len(rest):
                try:
                    wet = max(0.0, min(1.0, float(rest[j + 1])))
                except ValueError:
                    print(
                        f"invalid --wet value: {rest[j + 1]!r}",
                        file=sys.stderr,
                    )
                    return 2
                j += 2
            else:
                j += 1
        pattern, args = "/renoise/evaluate", [lua_reverb(track_sel, wet)]
    elif cmd == "load":
        plugin = " ".join(rest[1:]).strip() or "Legend HZ"
        if not start_renoise(host, port):
            return 1
        pattern, args = "/renoise/evaluate", [lua_load_plugin(plugin)]
    elif cmd == "transport":
        action = rest[1] if len(rest) > 1 else ""
        if action == "toggle":
            pattern, args = "/renoise/evaluate", [lua_transport_toggle()]
        elif action in ("start", "stop", "continue", "panic"):
            pattern, args = f"/renoise/transport/{action}", []
        else:
            print(
                "usage: renoise-osc transport <start|stop|continue|panic|toggle>",
                file=sys.stderr,
            )
            return 2
    elif cmd == "status":
        return cmd_status(host, port)
    else:
        pattern = cmd
        args = []
        for a in rest[1:]:
            try:
                args.append(float(a))
            except ValueError:
                try:
                    args.append(int(a))
                except ValueError:
                    args.append(a)
    return send(host, port, pattern, args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
