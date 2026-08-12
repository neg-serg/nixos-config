#!/usr/bin/env bash
# sing-box full-TUN up (ExecStartPre of sing-box-tun.service):
# generate /run/sing-box-tun/config.json from the SOCKS5 proxy config
# (~/.config/sing-box-trojan/config.json — same outbounds/urltest "auto")
# and validate it. Routing is set up by sing-box-tun-post.sh once sb0 exists.
set -euo pipefail

SRC_CFG="/home/neg/.config/sing-box-trojan/config.json"
OUT_CFG="/run/sing-box-tun/config.json"

mkdir -p /run/sing-box-tun

if [ ! -f "$SRC_CFG" ]; then
  echo "ERROR: $SRC_CFG missing — run 'proxy gen' or 'proxy on' first" >&2
  exit 1
fi

python3 << 'PYEOF'
import json
src = json.load(open("/home/neg/.config/sing-box-trojan/config.json"))
cfg = {
    "log": {"level": "error"},
    "dns": {},
    "inbounds": [{
        "type": "tun", "tag": "tun-in",
        "interface_name": "sb0",
        "address": ["172.19.0.1/30"],
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

sing-box check -c "$OUT_CFG" || {
  echo "ERROR: invalid TUN config" >&2
  exit 1
}
echo "TUN config: $OUT_CFG"
