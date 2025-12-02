import os
import shlex
import subprocess
import sys

GAMESCOPE = "gamescope"
GAME_RUN = "game-run"

flags = os.environ.get("GAMESCOPE_FLAGS", "-f --adaptive-sync")

cmd = [GAME_RUN, GAMESCOPE] + shlex.split(flags) + ["--"] + sys.argv[1:]
raise SystemExit(subprocess.call(cmd))
