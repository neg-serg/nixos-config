#!/usr/bin/env python3
"""glm-osc - OSC bridge to Genelec SAM monitors via genlc (no official GLM).

Listens on UDP 127.0.0.1:9000 (set GLM_OSC_HOST/PORT). Message map:
  /glm/volume <dB>          absolute volume (float dB)
  /glm/volume/ratio <0..1>  absolute volume as linear ratio
  /glm/volume/up <dB>       relative up   (stateful)
  /glm/volume/down <dB>     relative down (stateful)
  /glm/mute <0|1>           set mute
  /glm/mute/toggle          toggle mute (stateful)
  /glm/power <1|0|2>        on / off / toggle
  /glm/led <color> [pulse]  LED: green|red|yellow|off, optional pulse
  /glm/status               replies /glm/status/reply with JSON (discover+poll)
  /glm/discover             replies /glm/discover/reply

Env: GENLC_CLI (venv genlc binary), HIDAPI_LIB (dir with libhidapi*),
     GLM_OSC_STATE (json state file for volume/mute/power persistence).
"""

import json
import math
import os
import subprocess
from pathlib import Path
from pythonosc import dispatcher, osc_server
from pythonosc.udp_client import SimpleUDPClient

STATE_FILE = Path(os.environ.get("GLM_OSC_STATE", "/tmp/glm-osc-state.json"))
GENLC = os.environ.get("GENLC_CLI", "/tmp/glm-osc-venv/bin/genlc")
# Set by the wrapper (--set-default HIDAPI_LIB). When it is empty the inherited
# LD_LIBRARY_PATH is kept instead of clobbering it with a stale store path.
HIDAPI_LIB = os.environ.get("HIDAPI_LIB", "")

DEFAULT = {"volume_db": -20.0, "muted": False, "power": True}


def load_state():
    try:
        return {**DEFAULT, **json.loads(STATE_FILE.read_text())}
    except Exception:
        return dict(DEFAULT)


def save_state(st):
    try:
        STATE_FILE.write_text(json.dumps(st))
    except Exception:
        pass


def run_genlc(*args, timeout=40):
    env = dict(os.environ)
    if HIDAPI_LIB:
        env["LD_LIBRARY_PATH"] = HIDAPI_LIB
    r = subprocess.run(
        [GENLC, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=env,
    )
    return r


def reply_to(addr, path, payload):
    try:
        ip, port = addr
        SimpleUDPClient(ip, port).send_message(path, payload)
    except Exception:
        pass


class Bridge:
    def __init__(self):
        self.state = load_state()

    # --- volume -------------------------------------------------------
    def volume(self, addr, db):
        try:
            db = float(db)
        except (TypeError, ValueError):
            return
        r = run_genlc("set-volume", "--volume", f"{db:.2f}dB")
        if r.returncode == 0:
            self.state["volume_db"] = db
            save_state(self.state)
            print(f"/glm/volume {db:.2f}dB OK")
        else:
            print(f"/glm/volume FAIL: {r.stderr.strip()[-200:]}")

    def volume_ratio(self, addr, ratio):
        try:
            ratio = float(ratio)
        except (TypeError, ValueError):
            return
        r = max(ratio, 1e-4)
        self.volume(addr, 20 * math.log10(r))

    def volume_rel(self, addr, delta):
        try:
            delta = float(delta)
        except (TypeError, ValueError):
            return
        self.volume(addr, self.state.get("volume_db", -20.0) + delta)

    # --- mute ---------------------------------------------------------
    def mute(self, addr, on):
        cmd = "mute" if float(on) else "unmute"
        r = run_genlc(cmd)
        if r.returncode == 0:
            self.state["muted"] = bool(float(on))
            save_state(self.state)
            print(f"/glm/mute {on} OK")
        else:
            print(f"/glm/mute FAIL: {r.stderr.strip()[-200:]}")

    def mute_toggle(self, addr):
        self.mute(addr, int(not self.state.get("muted", False)))

    # --- power --------------------------------------------------------
    def power(self, addr, on):
        try:
            on = float(on)
        except (TypeError, ValueError):
            return
        cmd = "wakeup" if on else "shutdown"
        r = run_genlc(cmd)
        if r.returncode == 0:
            self.state["power"] = bool(on)
            save_state(self.state)
            print(f"/glm/power {on} OK")
        else:
            print(f"/glm/power FAIL: {r.stderr.strip()[-200:]}")

    def power_toggle(self, addr):
        self.power(addr, int(not self.state.get("power", True)))

    # --- LED ----------------------------------------------------------
    def led(self, addr, color, pulse=0):
        args = ["bypass", "--led-color", str(color)]
        args.append("--led-pulsing" if float(pulse) else "--led-solid")
        r = run_genlc(*args)
        ok = "OK" if r.returncode == 0 else "FAIL: " + r.stderr.strip()[-200:]
        print(f"/glm/led {color} {ok}")

    # --- status -------------------------------------------------------
    def status(self, client_addr, *_):
        out = {"ok": False}
        r = run_genlc("poll", "--count", "1")
        out["poll_rc"] = r.returncode
        out["poll"] = r.stdout.strip()[:2000]
        if r.returncode != 0:
            out["error"] = r.stderr.strip()[-300:]
        out["state"] = self.state
        reply_to(client_addr, "/glm/status/reply", json.dumps(out))
        print("/glm/status -> reply")

    def discover(self, client_addr, *_):
        r = run_genlc("discover")
        out = {"ok": r.returncode == 0, "output": r.stdout.strip()[:2000]}
        if r.returncode != 0:
            out["error"] = r.stderr.strip()[-300:]
        reply_to(client_addr, "/glm/discover/reply", json.dumps(out))
        print("/glm/discover -> reply")


def main():
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--host", default=os.environ.get("GLM_OSC_HOST", "127.0.0.1")
    )
    ap.add_argument(
        "--port", type=int, default=int(os.environ.get("GLM_OSC_PORT", "9000"))
    )
    args = ap.parse_args()

    b = Bridge()
    d = dispatcher.Dispatcher()
    d.map("/glm/volume", b.volume)
    d.map("/glm/volume/ratio", b.volume_ratio)
    d.map("/glm/volume/up", b.volume_rel)
    d.map("/glm/volume/down", lambda addr, db: b.volume_rel(addr, -float(db)))
    d.map("/glm/mute", b.mute)
    d.map("/glm/mute/toggle", b.mute_toggle)
    d.map("/glm/power", b.power)
    d.map("/glm/power/toggle", b.power_toggle)
    d.map("/glm/led", b.led)
    d.map("/glm/status", b.status, needs_reply_address=True)
    d.map("/glm/discover", b.discover, needs_reply_address=True)
    d.set_default_handler(lambda addr, *a: print(f"unhandled: {addr} {a}"))

    server = osc_server.ThreadingOSCUDPServer((args.host, args.port), d)
    print(f"glm-osc listening on {args.host}:{args.port} (genlc: {GENLC})")
    server.serve_forever()


if __name__ == "__main__":
    main()
