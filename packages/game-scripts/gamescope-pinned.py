import os
import shlex
import subprocess
import sys

GAMESCOPE = "gamescope"
GAME_RUN = "game-run"

flags = os.environ.get("GAMESCOPE_FLAGS", "-f --adaptive-sync")


args = sys.argv[1:]
# Exclude broken games from gamescope
cmd_str_check = " ".join(args)
# Soulstone Survivors (2066020) hangs with gamescope
if "Soulstone" in cmd_str_check or "2066020" in cmd_str_check:
    cmd = [GAME_RUN] + args
else:
    cmd = [GAME_RUN, GAMESCOPE] + shlex.split(flags) + ["--"] + args
raise SystemExit(subprocess.call(cmd))
