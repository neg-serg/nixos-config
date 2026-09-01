"""Persist Hyprland scratchpad geometry across show/hide cycles (host odin).

Hyprland 0.56.2 (Lua config mode) specifics, verified against the running
instance and the v0.56.2 source:
- 'hyprctl events' / 'hyprctl -j events' return "unknown request" on this
  build, so the IPC socket2 stream is read directly:
  /run/user/<uid>/hypr/<signature>/.socket2.sock
- This build emits no move/resize events for in-place window changes:
  movewindow/movewindowv2 fire only when a window changes workspace, and no
  resizewindow event exists at all. User drags/resizes are therefore captured
  by a periodic 'hyprctl clients -j' poll instead.
- Scratchpad show/hide surfaces as activespecial/activespecialv2 events
  (workspace/workspacev2 fire for regular workspace switches).

Geometry is applied with the Lua dispatchers:
    hl.dsp.window.move({window="address:0x...", x=.., y=..})
    hl.dsp.window.resize({window="address:0x...", x=.., y=..})
NOTE: resize keeps the window center fixed, so apply resize BEFORE move.
"""

import json
import os
import select
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

# Scratchpad classes managed by hyprscratch (hyprland.lua + hyprscratch.conf)
SCRATCHPAD_CLASSES = {
    "KotatogramDesktop",
    "Skype",
    "Slack",
    "TelegramDesktop",
    "org.telegram.desktop",
    "zoom",
    "music",
    "mutterfox",
    "neomutt",
    "ncpamixer",
    "com.saivert.pwvucontrol",
    "torrment",
    "teardown",
    "vpn",
    "rebuild",
}

POLL_INTERVAL = 1.0  # seconds between geometry polls (captures drags/resizes)
WRITE_THROTTLE = 0.5  # minimum seconds between geometry.json writes
HYPCTL_TIMEOUT = 2.0  # guard for every hyprctl call
APPLY_DELAY = 0.25  # delay after a special workspace becomes active

_sig = ""
_geometry: dict = {}
_last_write = 0.0
_dirty = False
_last_apply: dict = {}


def hypr_dir() -> Path:
    return Path(f"/run/user/{os.getuid()}/hypr")


def instance_signature() -> str:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "").strip()
    if sig:
        return sig
    if hypr_dir().is_dir():
        entries = sorted(d.name for d in hypr_dir().iterdir() if d.is_dir())
        if entries:
            return entries[-1]
    raise RuntimeError("no Hyprland instance found")


def socket_path(sig: str) -> Path:
    return hypr_dir() / sig / ".socket2.sock"


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(
        Path.home() / ".local/state"
    )
    d = Path(base) / "hyprscratch"
    d.mkdir(parents=True, exist_ok=True)
    return d


def geometry_file() -> Path:
    return state_dir() / "geometry.json"


def load_geometry() -> dict:
    try:
        data = json.loads(geometry_file().read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def write_geometry(data: dict) -> None:
    p = geometry_file()
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, p)  # atomic


def hyprctl(args, timeout=HYPCTL_TIMEOUT):
    env = dict(os.environ)
    env["HYPRLAND_INSTANCE_SIGNATURE"] = _sig
    try:
        r = subprocess.run(
            ["hyprctl", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    return r.stdout if r.returncode == 0 else None


def clients_json():
    out = hyprctl(["-j", "clients"])
    if out is None:
        return []
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return []


def norm_addr(a: str) -> str:
    return a.strip().lower().removeprefix("0x")


def flush_if_due() -> None:
    """Write pending geometry once the write throttle has elapsed."""
    global _last_write, _dirty
    if not _dirty:
        return
    now = time.monotonic()
    if now - _last_write < WRITE_THROTTLE:
        return
    try:
        write_geometry(_geometry)
        _last_write = now
        _dirty = False
    except OSError as e:
        print(f"geometry write failed: {e}", file=sys.stderr)


def record_geometry(cls: str, cl: dict) -> None:
    global _dirty
    at = cl.get("at") or [0, 0]
    size = cl.get("size") or [0, 0]
    entry = {
        "at": [int(at[0]), int(at[1])],
        "size": [int(size[0]), int(size[1])],
    }
    if _geometry.get(cls) == entry:
        return
    _geometry[cls] = entry
    _dirty = True
    flush_if_due()


def poll_clients() -> None:
    for cl in clients_json():
        if not cl.get("mapped"):
            continue
        cls = cl.get("class", "")
        if cls in SCRATCHPAD_CLASSES:
            record_geometry(cls, cl)


def dispatch_lua(expr: str) -> bool:
    env = dict(os.environ)
    env["HYPRLAND_INSTANCE_SIGNATURE"] = _sig
    try:
        r = subprocess.run(
            ["hyprctl", "dispatch", expr],
            capture_output=True,
            text=True,
            timeout=HYPCTL_TIMEOUT,
            env=env,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError) as e:
        print(f"dispatch failed: {e}", file=sys.stderr)
        return False
    ok = r.returncode == 0 and "ok" in r.stdout.lower()
    if not ok:
        print(
            f"dispatch rejected: {expr} -> {r.stdout.strip() or r.stderr.strip()}",
            file=sys.stderr,
        )
    return ok


def apply_geometry_for_workspace(ws_name: str) -> None:
    time.sleep(APPLY_DELAY)
    for cl in clients_json():
        if not cl.get("mapped"):
            continue
        ws = (cl.get("workspace") or {}).get("name", "")
        if ws != ws_name:
            continue
        cls = cl.get("class", "")
        entry = _geometry.get(cls)
        if not entry:
            continue
        addr = norm_addr(cl.get("address", ""))
        if not addr:
            continue
        size = entry["size"]
        at = entry["at"]
        # resize first: resize keeps the window center fixed, move sets position exactly
        dispatch_lua(
            f'hl.dsp.window.resize({{window="address:0x{addr}", x={size[0]}, y={size[1]}}})'
        )
        dispatch_lua(
            f'hl.dsp.window.move({{window="address:0x{addr}", x={at[0]}, y={at[1]}}})'
        )


def workspace_name_from_payload(name: str, payload: str) -> str:
    if name == "workspace":
        return payload.strip()
    if name == "workspacev2":
        parts = payload.split(",", 1)
        return parts[1].strip() if len(parts) > 1 else ""
    if name == "activespecial":
        return payload.split(",", 1)[0].strip()
    if name == "activespecialv2":
        parts = payload.split(",", 2)
        return parts[1].strip() if len(parts) > 1 else ""
    return ""


def handle_event(name: str, payload: str) -> None:
    if name in ("movewindow", "movewindowv2", "openwindow"):
        # payloads: movewindow  = {addr:x},{ws}   movewindowv2 = {addr:x},{id},{ws}
        #           openwindow  = {addr:x},{ws},{class},{title}
        addr = payload.split(",", 1)[0]
        target = norm_addr(addr)
        if target:
            for cl in clients_json():
                if norm_addr(cl.get("address", "")) == target:
                    cls = cl.get("class", "")
                    if cls in SCRATCHPAD_CLASSES:
                        record_geometry(cls, cl)
                    return
    elif name in (
        "workspace",
        "workspacev2",
        "activespecial",
        "activespecialv2",
    ):
        ws = workspace_name_from_payload(name, payload)
        if not ws or not ws.startswith("special:"):
            return
        now = time.monotonic()
        if now - _last_apply.get(ws, -10.0) < 1.0:
            return  # dedupe activespecial + activespecialv2 pairs
        _last_apply[ws] = now
        apply_geometry_for_workspace(ws)


def handle_line(line: str) -> None:
    if ">>" not in line:
        return
    name, _, payload = line.partition(">>")
    try:
        handle_event(name.strip(), payload)
    except (OSError, ValueError) as e:
        print(f"error handling event {name}: {e}", file=sys.stderr)


def on_term(signum, frame):
    global _dirty
    try:
        write_geometry(_geometry)
        _dirty = False
    except (OSError, TypeError, ValueError) as e:
        print(f"geometry flush on exit failed: {e}", file=sys.stderr)
    sys.exit(0)


def main() -> int:
    global _sig, _geometry, _last_write
    _sig = instance_signature()
    _geometry = load_geometry()
    _last_write = 0.0

    sock_file = socket_path(_sig)
    if not sock_file.exists():
        raise RuntimeError(f"Hyprland socket2 not found: {sock_file}")

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(str(sock_file))
    sock.setblocking(False)

    signal.signal(signal.SIGTERM, on_term)

    # Seed geometry for scratchpads that are already open.
    poll_clients()
    flush_if_due()

    buf = b""
    last_poll = time.monotonic()
    while True:
        now = time.monotonic()
        if now - last_poll >= POLL_INTERVAL:
            poll_clients()
            last_poll = now
        flush_if_due()
        r, _, _ = select.select([sock], [], [], 0.1)
        if r:
            try:
                chunk = sock.recv(65536)
            except OSError as e:
                print(f"socket read error: {e}", file=sys.stderr)
                return 1
            if not chunk:
                print("Hyprland IPC socket closed", file=sys.stderr)
                return 1  # systemd Restart=always brings us back
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                handle_line(line.decode(errors="replace"))


if __name__ == "__main__":
    sys.exit(main())
