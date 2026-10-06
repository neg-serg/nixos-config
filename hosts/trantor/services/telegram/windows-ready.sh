set -euo pipefail

STATE_FILE="/var/lib/telegram-notify/windows-ready.sent"

# The marker is checked BEFORE the probes: the timer fires the unit every 30 s and the notification
# is sent once — in the steady state the exit is instant (it used to be:
# two probes with a 5 s pause on every run, 10 s in blame).
[ -e "$STATE_FILE" ] && exit 0

ok=0
for _ in 1 2; do
  if (exec 3<> /dev/tcp/127.0.0.1/3389) 2> /dev/null; then
    ok=1
  else
    ok=0
    break
  fi
  sleep 2
done

if [ "$ok" != 1 ]; then
  rm -f "$STATE_FILE"
  exit 0
fi

@sender@ "🪟 таз загрузился" "Windows-VM доступна по RDP (127.0.0.1:3389)"
touch "$STATE_FILE"
