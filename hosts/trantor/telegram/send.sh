set -euo pipefail

TOKEN="$(cat @botToken@)"
CHAT_ID="$(cat @chatId@)"
export TOKEN CHAT_ID

# Three shapes:
#
#   telegram-send <msg> [detail] [attempts]
#       the historical plain-text form: `detail` is appended after a colon and
#       a timestamp is added unless TELEGRAM_SEND_PLAIN=1 is set;
#   telegram-send --html-file <path> [attempts]
#       a finished HTML body (rendered by nixos-rollout-report) posted with
#       parse_mode=HTML, so one message can carry a bold title, inline code and
#       an expandable quotation instead of a flat line;
#   telegram-send --html-file - [attempts]
#       the same body on stdin.
#
# 6 attempts, not 12: the boot notifier runs before the socks proxy (a *user*
# unit) exists, so the first attempts cannot succeed no matter how many there
# are — systemd restarts the unit after login and that attempt delivers.
mode=plain
if [ "${1:-}" = "--html-file" ]; then
  mode=html
  source_arg=${2:?usage: telegram-send --html-file <path|-> [attempts]}
  attempts=${3:-6}
  if [ "$source_arg" = "-" ]; then
    msg=$(cat)
  else
    msg=$(cat "$source_arg")
  fi
  [ -n "$msg" ] || {
    echo "telegram-send: the HTML body is empty ($source_arg)" >&2
    exit 2
  }
else
  msg="$1"
  detail="${2:-}"
  attempts="${3:-6}"
  if [ -n "$detail" ]; then
    msg="$msg: $detail"
  fi
  if [ -z "${TELEGRAM_SEND_PLAIN:-}" ]; then
    msg="$msg ($(date '+%Y-%m-%d %H:%M %Z'))"
  fi
fi

# One Bot API call. -f turns an HTTP error (400 on unparsable markup) into exit
# status 22, which send_chunk() uses to fall back to plain text.
post() {
  local text=$1 parse=$2
  local args=(
    -sf -o /dev/null
    --connect-timeout 5 --max-time 15
    --proxy socks5h://127.0.0.1:10808
    --data-urlencode "chat_id=$CHAT_ID"
    --data-urlencode "text=$text"
  )
  if [ "$parse" = html ]; then
    args+=(--data-urlencode "parse_mode=HTML")
    # No link preview: a rollout report is text, and a card under it only eats
    # the screen on a phone.
    args+=(--data-urlencode 'link_preview_options={"is_disabled":true}')
  fi
  # --connect-timeout/--max-time keep this bounded: without them a connection
  # to a proxy that is not up yet hangs until the kernel gives up (2026-10-01:
  # one telegram-notify-boot run sat 1 h 1 min for its 12 attempts).
  curl "${args[@]}" "https://api.telegram.org/bot$TOKEN/sendMessage"
}

# The fallback body for a rejected markup: plain prose. Tags first, then the
# entities, &amp; last so a decoded & cannot start a second entity.
strip_html() {
  printf '%s' "$1" | sed \
    -e 's/<[^>]*>//g' \
    -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e 's/&apos;/'\''/g' \
    -e 's/&amp;/\&/g'
}

# Deliver one chunk, retrying the same way the plain sender always has. When
# the API rejects the HTML (exit 22), the same text goes out as plain prose
# rather than being lost; the switch is per chunk and per attempt.
send_chunk() {
  local text=$1 parse=${2:-none} attempt=1 rc=0
  while [ "$attempt" -le "$attempts" ]; do
    rc=0
    post "$text" "$parse" || rc=$?
    if [ "$rc" = 0 ]; then
      return 0
    fi
    if [ "$rc" = 22 ] && [ "$parse" = html ]; then
      echo "telegram-send: Telegram rejected the HTML, sending plain text" >&2
      text=$(strip_html "$text")
      parse=none
      continue
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  return 1
}

# Telegram caps a message at 4096 UTF-8 characters. Split between lines, never
# inside one, so no tag or word is cut: a rendered report keeps at least one
# message per section and a very long one arrives as a few consecutive parts.
send_html() {
  local text=$1 limit=3900 buf="" line failed=0
  if [ "${#text}" -le "$limit" ]; then
    send_chunk "$text" html || failed=1
  else
    while IFS= read -r line; do
      if [ -n "$buf" ] && [ $((${#buf} + ${#line})) -gt "$limit" ]; then
        send_chunk "$buf" html || failed=1
        buf=""
      fi
      buf+="$line"$'\n'
    done <<< "$text"
    if [ -n "$buf" ]; then
      send_chunk "$buf" html || failed=1
    fi
  fi
  return "$failed"
}

if [ "$mode" = html ]; then
  if ! send_html "$msg"; then
    echo "telegram-send: could not deliver the HTML message after $attempts attempts" >&2
    exit 1
  fi
else
  if ! send_chunk "$msg" none; then
    echo "telegram-send: could not deliver message after $attempts attempts" >&2
    exit 1
  fi
fi
