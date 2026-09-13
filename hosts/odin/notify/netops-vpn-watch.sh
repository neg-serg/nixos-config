set -euo pipefail

STATE=/var/lib/telegram-vpn-watch
IP_FILE="$STATE/ip.txt"
DOWN_MARKER="$STATE/down"
SYSCTL=@systemd@/bin/systemctl
CURL=@curl@/bin/curl
SEND=@sender@/bin/telegram-send

# Delivery failure is not a unit failure; the shared sender retries
# ~1 min through the socks proxy on its own.
send() { # $1 = message text
  "$SEND" "$1" || true
}

# 1. Down (stopped manually / inactive) is a normal action here — record
#    the down edge and stay silent (no Telegram spam).
if ! $SYSCTL is-active --quiet wg-quick-vpn-odin; then
  touch "$DOWN_MARKER"
  exit 0
fi

# 2. Tunnel is active. Fetch the public egress IP; when the tunnel is up
#    the default route already egresses through it. Fall back to the
#    socks proxy variant if the direct fetch fails.
ip=$($CURL -sf -m 10 https://api.ipify.org || true)
if [ -z "$ip" ]; then
  ip=$($CURL -sf -m 10 --proxy @socksProxy@ https://api.ipify.org || true)
fi
if [ -z "$ip" ]; then
  echo "telegram-vpn-watch: could not fetch public IP" >&2
  exit 0 # leave state untouched; retry next tick
fi

prev=""
if [ -f "$IP_FILE" ]; then
  prev=$(cat "$IP_FILE")
fi

# 3. Down->up transition: notify "поднят".
if [ -f "$DOWN_MARKER" ]; then
  rm -f "$DOWN_MARKER"
  send "🌐 VPN поднят (IP: $ip)"
  printf '%s\n' "$ip" > "$IP_FILE"
  exit 0
fi

# First observation while already up (fresh state): record, notify once.
if [ -z "$prev" ]; then
  send "🌐 VPN поднят (IP: $ip)"
  printf '%s\n' "$ip" > "$IP_FILE"
  exit 0
fi

# IP changed while the tunnel stayed up: notify, keep the same marker.
if [ "$prev" != "$ip" ]; then
  send "🌐 VPN: публичный IP сменился $prev -> $ip"
fi
printf '%s\n' "$ip" > "$IP_FILE"
exit 0
