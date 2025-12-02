import os
import subprocess
import sys

CPUSET = os.environ.get("GAME_PIN_CPUSET", "@pinDefault@")
if len(sys.argv) <= 1:
    print("Usage: game-run <command> [args...]", file=sys.stderr)
    sys.exit(1)

cmd = [
    "systemd-run",
    "--user",
    "--scope",
    "--same-dir",
    "--collect",
    "-p",
    "Slice=games.slice",
    "-p",
    "CPUWeight=10000",
    "-p",
    "IOWeight=10000",
    "-p",
    "TasksMax=infinity",
    "game-affinity-exec",
    "--cpus",
    CPUSET,
    "--",
] + sys.argv[1:]

raise SystemExit(subprocess.call(cmd))
