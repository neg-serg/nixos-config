import shlex
import sys


out_w, out_h, rate = display_info()

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

cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args

raise SystemExit(subprocess.call(cmd))
