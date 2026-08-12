#!/usr/bin/env bash
# sing-box full-TUN post (ExecStartPost of sing-box-tun.service):
# wait for the sb0 interface created by sing-box, then set up policy routing
# so all non-private traffic goes via sb0, plus DNS through the tunnel.
set -euo pipefail

TUN_IFACE="sb0"
ROUTE_TABLE="200"

# Wait for sing-box to create the TUN interface (it gets its address from the
# config's `address` field)
for _ in $(seq 1 30); do
  ip link show "$TUN_IFACE" > /dev/null 2>&1 && break
  sleep 0.3
done
ip link show "$TUN_IFACE" > /dev/null 2>&1 || {
  echo "ERROR: $TUN_IFACE not created by sing-box" >&2
  exit 1
}

# Clean leftovers from a previous crashed run
while ip rule del pref 200 2> /dev/null; do :; done
ip route flush table "$ROUTE_TABLE" 2> /dev/null || true
resolvectl revert "$TUN_IFACE" 2> /dev/null || true

# --- Policy routing ---
# VPN server IPs direct (avoid tunnel loop) — from the generated config
SERVERS=$(python3 -c '
import json
cfg = json.load(open("/run/sing-box-tun/config.json"))
print("\n".join(sorted({o["server"] for o in cfg["outbounds"]
                        if o["type"] in ("vless", "hysteria2")})))
' 2> /dev/null || true)
for ip in $SERVERS; do
  case "$ip" in
    *[!0-9.]*) continue ;; # hostname/IPv6 servers: urltest will avoid them
  esac
  ip rule add pref 100 to "$ip/32" lookup main 2> /dev/null || true
done
# Private/loopback/CGNAT direct — LAN, tailscale, localhost stay local
for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
  ip rule add pref 150 to "$net" lookup main 2> /dev/null || true
done
# Everything else → table 200 → sb0
ip rule add pref 200 lookup "$ROUTE_TABLE" 2> /dev/null || true
ip route add default dev "$TUN_IFACE" table "$ROUTE_TABLE" 2> /dev/null || true

# --- DNS through the tunnel ---
resolvectl dns "$TUN_IFACE" 1.1.1.1 1.0.0.1 2> /dev/null || true
resolvectl domain "$TUN_IFACE" "~." 2> /dev/null || true

echo "TUN routing up: $(ip rule | grep -cE 'pref (100|150|200)') rules, table $ROUTE_TABLE default dev $TUN_IFACE"
