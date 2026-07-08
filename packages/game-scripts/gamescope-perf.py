import shlex
import sys


out_w, out_h, rate = display_info()

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

cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args

raise SystemExit(subprocess.call(cmd))
