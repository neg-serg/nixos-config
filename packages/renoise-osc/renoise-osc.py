#!/usr/bin/env python3
"""renoise-osc - send OSC messages to Renoise built-in OSC server.

Usage:
  renoise-osc [--host H] [--port P] eval '<lua expression>'
  renoise-osc [--host H] [--port P] reverb [--track master|N] [--wet X]
  renoise-osc [--host H] [--port P] load '<plugin name>'
  renoise-osc [--host H] [--port P] <osc-pattern> [args...]

Defaults: 127.0.0.1:9000 (Renoise Preferences -> OSC -> enable server).

'eval' runs arbitrary Renoise Lua remotely via /renoise/evaluate.
'reverb' inserts the native Reverb FX: --track master (default) or a
1-based track number; --wet 0..1 sets the device Send parameter (default:
leave the preset value).
'load' inserts a new instrument and loads a VST plugin into it by name
(e.g. 'renoise-osc load Legend HZ'); starts Renoise first if needed.

Bare numeric args become OSC floats; everything else is a string.
"""

import socket
import struct
import subprocess
import sys
import time


def osc_string(b: bytes) -> bytes:
    return b + b"\x00" * (4 - (len(b) % 4))


def build_message(pattern: str, args):
    tags = b","
    payload = b""
    for a in args:
        if isinstance(a, float):
            tags += b"f"
            payload += struct.pack(">f", a)
        else:
            tags += b"s"
            payload += osc_string(str(a).encode("utf-8"))
    return osc_string(pattern.encode("utf-8")) + osc_string(tags) + payload


def _port_open(host: str, port: int) -> bool:
    try:
        s = socket.create_connection((host, port), timeout=0.3)
        s.close()
        return True
    except OSError:
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


def main(argv):
    host, port = "127.0.0.1", 9000
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--host" and i + 1 < len(argv):
            host, i = argv[i + 1], i + 2
        elif a == "--port" and i + 1 < len(argv):
            try:
                port = int(argv[i + 1])
            except ValueError:
                pass
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
                    pass
                j += 2
            else:
                j += 1
        pattern, args = "/renoise/evaluate", [lua_reverb(track_sel, wet)]
    elif cmd == "load":
        plugin = " ".join(rest[1:]).strip() or "Legend HZ"
        pattern, args = "/renoise/evaluate", [lua_load_plugin(plugin)]
        # Renoise not up yet? start it and wait for the OSC server.
        if not _port_open(host, port):
            print("renoise not running - starting it ...")
            subprocess.Popen(
                ["renoise"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            for _ in range(45):
                time.sleep(1)
                if _port_open(host, port):
                    break
    else:
        pattern = cmd
        args = []
        for a in rest[1:]:
            try:
                args.append(float(a))
            except ValueError:
                args.append(a)
    msg = build_message(pattern, args)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(msg, (host, port))
    print(f"{pattern} -> {host}:{port} ({len(msg)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
