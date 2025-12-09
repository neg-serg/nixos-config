import json
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

flags = ["-f", "--adaptive-sync"]
if rate:
    flags += ["-r", rate]
flags += [
    "-W",
    out_w,
    "-H",
    out_h,
]

if len(sys.argv) == 1:
    try:
        cmd_str = subprocess.check_output(
            [
                H["ZENITY"],
                "--entry",
                "--title=Gamescope Quality",
                "--text=Command to run:",
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

# Debug logging
try:
    with open("/tmp/gamescope_wrapper_debug.log", "a") as f:
        f.write(f"Wrapper Args: {args}\n")
except Exception:
    pass

# Exclude broken games from gamescope
cmd_str_check = " ".join(args)
# Soulstone Survivors (2066020) hangs with gamescope
if "Soulstone" in cmd_str_check or "2066020" in cmd_str_check:
    cmd = [H["GAME_RUN"]] + args
else:
    cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args

raise SystemExit(subprocess.call(cmd))
