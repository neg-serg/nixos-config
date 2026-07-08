import os
import shlex
import subprocess
import sys


out_w, out_h, rate = display_info()

flags = ["-f", "--adaptive-sync", "--hdr-enabled"]
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
                "--title=Gamescope HDR",
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


cmd = [H["GAME_RUN"], H["GAMESCOPE"]] + flags + ["--"] + args

raise SystemExit(subprocess.call(cmd))
