set -euo pipefail

TOKEN="$(cat @botToken@)"
CHAT_ID="$(cat @chatId@)"
export TOKEN CHAT_ID

msg="$1"
detail="${2:-}"
attempts="${3:-12}"
if [ -n "$detail" ]; then
  msg="$msg: $detail"
fi
# Callers that already format their own time (e.g. the morning digest)
# set TELEGRAM_SEND_PLAIN=1 to suppress the appended timestamp.
if [ -z "${TELEGRAM_SEND_PLAIN:-}" ]; then
  msg="$msg ($(date '+%Y-%m-%d %H:%M %Z'))"
fi

for _ in $(seq 1 "$attempts"); do
  if curl -sf -o /dev/null \
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
