import math
import shlex
import sys


target = os.environ.get("TARGET_FPS")
base = float(os.environ.get("NATIVE_BASE_FPS", "60"))
autoscale = os.environ.get("GAMESCOPE_AUTOSCALE") == "1"

out_w, out_h, rate = display_info()

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
