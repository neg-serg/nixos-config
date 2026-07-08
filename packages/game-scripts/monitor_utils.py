import json
import math
import os
import shlex
import subprocess
import sys

H = {
    "HYPRCTL": "hyprctl",
    "ZENITY": "zenity",
    "GAME_RUN": "game-run",
    "GAMESCOPE": "gamescope",
}


def get_monitors():
    try:
        out = subprocess.check_output(
            [H["HYPRCTL"], "monitors", "-j"],
            text=True,
        )
        return json.loads(out)
    except Exception:
        return []


def pick_monitor(mon_name, mons):
    if mons:
        if mon_name:
            for m in mons:
                if m.get("name") == mon_name:
                    return m
        focused = [m for m in mons if m.get("focused")]
        if focused:
            return focused[0]
        # best by refresh then resolution
        return sorted(
            mons,
            key=lambda m: (
                m.get("refreshRate", 0),
                (m.get("width", 0) * m.get("height", 0)),
            ),
            reverse=True,
        )[0]
    return None


def display_info():
    """Resolve display parameters for gamescope wrappers.

    Priority: env vars (GAMESCOPE_OUT_W/OUT_H/RATE) → hyprctl auto-detect.
    Focuses the monitor specified in GAMESCOPE_MON if set.
    Returns (width, height, rate) — all strings or None.
    """
    mon_name = os.environ.get("GAMESCOPE_MON")
    out_w = os.environ.get("GAMESCOPE_OUT_W")
    out_h = os.environ.get("GAMESCOPE_OUT_H")

    mons = get_monitors()
    mon = pick_monitor(mon_name, mons)

    if not out_w or not out_h:
        if mon:
            out_w = out_w or str(mon.get("width", 3840))
            out_h = out_h or str(mon.get("height", 2160))
        else:
            out_w = out_w or "3840"
            out_h = out_h or "2160"

    rate = os.environ.get("GAMESCOPE_RATE")
    if not rate and mon:
        rr = mon.get("refreshRate")
        if rr:
            rate = str(int(round(rr)))

    # focus chosen monitor
    if mon_name:
        try:
            subprocess.run(
                [H["HYPRCTL"], "dispatch", "focusmonitor", mon_name],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    return (out_w, out_h, rate)
