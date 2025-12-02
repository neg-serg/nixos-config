import subprocess
import sys

GAME_RUN = "game-run"

cmd = [GAME_RUN] + sys.argv[1:]
raise SystemExit(subprocess.call(cmd))
