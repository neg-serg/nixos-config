#!/usr/bin/env bash
# sing-box full-TUN down (ExecStopPost of sing-box-tun.service):
# remove routing/rules/DNS set up by sing-box-tun-up.sh.
set -uo pipefail

TUN_IFACE="sb0"
ROUTE_TABLE="200"

ip rule del pref 200 2>/dev/null || true
for net in 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16; do
  ip rule del pref 150 to "$net" lookup main 2>/dev/null || true
done
ip rule del pref 100 2>/dev/null || true
ip route flush table "$ROUTE_TABLE" 2>/dev/null || true
resolvectl revert "$TUN_IFACE" 2>/dev/null || true
ip link del "$TUN_IFACE" 2>/dev/null || true

echo "sing-box TUN teardown complete"
