set -euo pipefail

STATE_FILE="/var/lib/telegram-notify/windows-ready.sent"

# Маркер проверяем ДО проб: таймер дёргает юнит каждые 30 с, а уведомление
# отправляется один раз — в установившемся режиме выход мгновенный (было:
# две пробы с паузой 5 с на каждом запуске, 10 с в blame).
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
