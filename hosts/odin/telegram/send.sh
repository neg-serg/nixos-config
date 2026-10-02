set -euo pipefail

TOKEN="$(cat @botToken@)"
CHAT_ID="$(cat @chatId@)"
export TOKEN CHAT_ID

msg="$1"
detail="${2:-}"
# 6 attempts, not 12: the boot notifier runs before the socks proxy (a *user*
# unit) exists, so the first attempts cannot succeed no matter how many there
# are — systemd restarts the unit after login and that attempt delivers.
attempts="${3:-6}"
if [ -n "$detail" ]; then
  msg="$msg: $detail"
fi
# Callers that already format their own time (e.g. the morning digest)
# set TELEGRAM_SEND_PLAIN=1 to suppress the appended timestamp.
if [ -z "${TELEGRAM_SEND_PLAIN:-}" ]; then
  msg="$msg ($(date '+%Y-%m-%d %H:%M %Z'))"
fi

for _ in $(seq 1 "$attempts"); do
  # --connect-timeout/--max-time keep this bounded: without them a connection to
  # a proxy that is not up yet hangs until the kernel gives up (2026-10-01: one
  # telegram-notify-boot run sat 1 h 1 min for its 12 attempts).
  if curl -sf -o /dev/null \
    --connect-timeout 5 --max-time 15 \
    --proxy socks5h://127.0.0.1:10808 \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$msg" \
    "https://api.telegram.org/bot$TOKEN/sendMessage"; then
    exit 0
  fi
  sleep 5
done
echo "telegram-send: could not deliver message after $attempts attempts" >&2
exit 1
