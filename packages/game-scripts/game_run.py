import os
import subprocess
import sys


# Fix for Unity games failing to find CA certs (Curl error 35)
if "SSL_CERT_FILE" not in os.environ:
    os.environ["SSL_CERT_FILE"] = "/etc/ssl/certs/ca-certificates.crt"

CPUSET = os.environ.get("GAME_PIN_CPUSET", "@pinDefault@")
if len(sys.argv) <= 1:
    print("Usage: game-run <command> [args...]", file=sys.stderr)
    sys.exit(1)

# Debug logging
# Debug logging
print(f"DEBUG_GAME_RUN Args: {sys.argv}", file=sys.stderr)
print(
    f"DEBUG_GAME_RUN Env SSL: {os.environ.get('SSL_CERT_FILE')}",
    file=sys.stderr,
)
print(
    f"DEBUG_GAME_RUN Pin: {os.environ.get('GAME_PIN_CPUSET')}",
    file=sys.stderr,
)

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
