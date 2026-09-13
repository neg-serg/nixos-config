set -euo pipefail
MODE="${1:-prepare}"
BIN="@nfqws@"

case "$MODE" in
  prepare | preflight)
    [ -x "$BIN" ] || {
      echo "ERROR: nfqws not found at $BIN" >&2
      exit 1
    }
    "$BIN" --dry-run @strategyFlags@ > /dev/null 2>&1 \
      || {
        echo "ERROR: nfqws --dry-run failed" >&2
        exit 1
      }
    echo "[OK] nfqws present and config valid"
    ;;
  preview)
    echo "[INFO] zapret2: @nfqws@"
    echo "       flags: @strategyFlags@"
    ;;
  smoke)
    "$BIN" --version
    ;;
  activate)
    systemctl start zapret2
    echo "[OK] zapret2 activated"
    ;;
  deactivate)
    systemctl stop zapret2
    echo "[OK] zapret2 deactivated"
    ;;
  *)
    echo "Usage: $0 {prepare|preflight|preview|smoke|activate|deactivate}"
    exit 1
    ;;
esac
