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
        return sorted(
            mons,
            key=lambda m: (
                m.get("refreshRate", 0),
                (m.get("width", 0) * m.get("height", 0)),
            ),
            reverse=True,
        )[0]
    return None


mon_env = os.environ.get("GAMESCOPE_MON")
target = os.environ.get("TARGET_FPS")
base = float(os.environ.get("NATIVE_BASE_FPS", "60"))
autoscale = os.environ.get("GAMESCOPE_AUTOSCALE") == "1"

out_w = os.environ.get("GAMESCOPE_OUT_W") or ""
out_h = os.environ.get("GAMESCOPE_OUT_H") or ""
mons = get_monitors()
mon = pick_monitor(mon_env, mons)
if not out_w or not out_h:
    if mon:
        out_w = out_w or str(mon.get("width", 3840))
        out_h = out_h or str(mon.get("height", 2160))
    else:
        out_w = out_w or "3840"
        out_h = out_h or "2160"

if mon_env:
    try:
        subprocess.run(
            [H["HYPRCTL"], "dispatch", "focusmonitor", mon_env],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass

rate = os.environ.get("GAMESCOPE_RATE")
if not rate and mon:
    rr = mon.get("refreshRate")
    if rr:
        rate = str(int(round(rr)))

# Heuristic autoscale
scale = 1.0
if target or autoscale:
    t = float(target or 120)
    if base > 0 and t > 0:
        scale = max(0.5, min(1.0, math.sqrt(base / t)))
game_w = str(int(round(int(out_w) * scale)))
game_h = str(int(round(int(out_h) * scale)))

flags = ["-f", "--adaptive-sync"]
if rate:
    flags += ["-r", rate]
flags += [
    "-w",
    game_w,
    "-h",
    game_h,
    "-W",
    out_w,
    "-H",
    out_h,
    "--fsr-sharpness",
    "3",
]

if len(sys.argv) == 1:
    prompt = f"Command to run (scale {scale:.3f}"
    if target:
        prompt += f", target {target} FPS"
    prompt += "):"
    try:
        cmd_str = subprocess.check_output(
            [
                H["ZENITY"],
                "--entry",
                "--title=Gamescope Target FPS",
                f"--text={prompt}",
            ],
            text=True,
        ).strip()
    except Exception:
        cmd_str = ""
    if not cmd_str:
        sys.exit(0)
    args = shlex.split(cmd_str)
else:
    args = sys.argv[1:]

cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args
raise SystemExit(subprocess.call(cmd))
