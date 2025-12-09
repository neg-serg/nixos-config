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


mon_env = os.environ.get("GAMESCOPE_MON")
out_w = os.environ.get("GAMESCOPE_OUT_W")
out_h = os.environ.get("GAMESCOPE_OUT_H")
mons = get_monitors()
mon = pick_monitor(mon_env, mons)
if not out_w or not out_h:
    if mon:
        out_w = out_w or str(mon.get("width", 3840))
        out_h = out_h or str(mon.get("height", 2160))
    else:
        out_w = out_w or "3840"
        out_h = out_h or "2160"

# focus chosen monitor
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

game_w = os.environ.get("GAMESCOPE_GAME_W")
game_h = os.environ.get("GAMESCOPE_GAME_H")
if not game_w or not game_h:
    game_w = game_w or str(int(int(out_w) * 2 / 3))
    game_h = game_h or str(int(int(out_h) * 2 / 3))

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
    try:
        cmd_str = subprocess.check_output(
            [
                H["ZENITY"],
                "--entry",
                "--title=Gamescope Performance",
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
print(f"DEBUG: gamescope-perf wrapper args: {args}", file=sys.stderr)

# Exclude broken games from gamescope
cmd_str_check = " ".join(args)
# Soulstone Survivors (2066020) hangs with gamescope
if "Soulstone" in cmd_str_check or "2066020" in cmd_str_check:
    # Disable gamemode as it fails to load libgamemode.so in this context
    os.environ["GAME_RUN_USE_GAMEMODE"] = "0"
    # Force X11 backend to avoid Wayland hangs with Unity
    os.environ["SDL_VIDEODRIVER"] = "x11"
    # Disable Mangohud to prevent overlay deadlocks
    os.environ["MANGOHUD"] = "0"

    # Inject arguments to force windowed mode AND force Vulkan backend
    forced_args = [
        "-screen-fullscreen",
        "0",
        "-screen-width",
        "1280",
        "-screen-height",
        "720",
        "-force-vulkan",
    ]
    # Append forced args to the END so they are passed to the game binary
    # and not interpreted as the executable by game-run
    # Restore usage of game-run wrapper (systemd isolation)
    cmd = [H["GAME_RUN"]] + args + forced_args
else:
    cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args

raise SystemExit(subprocess.call(cmd))
