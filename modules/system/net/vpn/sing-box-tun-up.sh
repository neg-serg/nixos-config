#!/usr/bin/env bash
# sing-box full-TUN up (ExecStartPre of sing-box-tun.service):
# 1. generate /run/sing-box-tun/config.json from the SOCKS5 proxy config
#    (~/.config/sing-box-trojan/config.json — same outbounds/urltest "auto"),
# 2. set up policy routing so all non-private traffic goes via sb0.
set -euo pipefail

TUN_IFACE="sb0"
SRC_CFG="/home/neg/.config/sing-box-trojan/config.json"
OUT_CFG="/run/sing-box-tun/config.json"
ROUTE_TABLE="200"

mkdir -p /run/sing-box-tun

# --- 1. Generate TUN config (reuse the SOCKS5 proxy's outbounds) ---
if [ ! -f "$SRC_CFG" ]; then
  echo "ERROR: $SRC_CFG missing — run 'proxy gen' or 'proxy on' first" >&2
  exit 1
fi

SERVERS=$(python3 << 'PYEOF'
import json
src = json.load(open("/home/neg/.config/sing-box-trojan/config.json"))
cfg = {
    "log": {"level": "error"},
    "dns": {},
    "inbounds": [{
        "type": "tun", "tag": "tun-in",
        "interface_name": "sb0",
        "auto_route": False,
        "strict_route": False,
        "stack": "system",
        "mtu": 1500,
    }],
    "outbounds": src["outbounds"],
    "route": {"final": "auto"},
}
json.dump(cfg, open("/run/sing-box-tun/config.json", "w"), indent=2)
servers = sorted({o["server"] for o in src["outbounds"]
                  if o["type"] in ("vless", "hysteria2")})
print("\n".join(servers))
PYEOF
)

# Validate the generated config before touching any routing
sing-box check -c "$OUT_CFG" || { echo "ERROR: invalid TUN config" >&2; exit 1; }

# --- 2. Clean leftovers from a previous crashed run ---
ip rule del pref 200 2>/dev/null || true
ip route flush table "$ROUTE_TABLE" 2>/dev/null || true
resolvectl revert "$TUN_IFACE" 2>/dev/null || true

# --- 3. Policy routing ---
# VPN server IPs direct (avoid tunnel loop)
for ip in $SERVERS; do
  case "$ip" in
    *[!0-9.]*) continue ;; # hostname/IPv6 servers: urltest will avoid them
  esac
  ip rule add pref 100 to "$ip/32" lookup main 2>/dev/null || true
done
# Private/loopback/CGNAT direct — LAN, tailscale, localhost stay local
for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
  ip rule add pref 150 to "$net" lookup main 2>/dev/null || true
done
# Everything else → table 200 → sb0
ip rule add pref 200 lookup "$ROUTE_TABLE" 2>/dev/null || true
ip route add default dev "$TUN_IFACE" table "$ROUTE_TABLE" 2>/dev/null || true

# --- 4. DNS through the tunnel ---
resolvectl dns "$TUN_IFACE" 1.1.1.1 1.0.0.1 2>/dev/null || true
resolvectl domain "$TUN_IFACE" "~." 2>/dev/null || true

echo "TUN config: $OUT_CFG"
echo "Direct server IPs: $(echo "$SERVERS" | tr '\n' ' ')"
