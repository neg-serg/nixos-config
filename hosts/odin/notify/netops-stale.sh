set -euo pipefail

CURL=@curl@/bin/curl
NTFY_URL="http://127.0.0.1:2586/system"

# 1. Age (days) of the last commit that touched flake.lock.
last=$(git -C /etc/nixos log -1 --format=%cs -- flake.lock || true)
if [ -z "$last" ]; then
  echo "ntfy-system-stale: no flake.lock commit date found" >&2
  exit 0
fi
last_epoch=$(date -d "$last" +%s)
now_epoch=$(date +%s)
age=$(((now_epoch - last_epoch) / 86400))

# 2. Fresh enough -> silent exit.
if [ "$age" -le 14 ]; then
  exit 0
fi

# 3. Post an info/low reminder to the local ntfy `system` topic.
msg="Флейк не обновлялся $age дней (последний раз $last). Пора nix flake update."
$CURL -sS -m 5 -X POST \
  -H "Title: Система" \
  -H "Priority: low" \
  --data "$msg" \
  "$NTFY_URL" > /dev/null 2>&1 || true
exit 0
