#!/usr/bin/env bash
# @script
# purpose: Launch zen-browser with VPN SOCKS5 proxy
#

set -euo pipefail

# Launch zen-browser with VPN SOCKS5 proxy
# Usage: zen-vpn.sh [browser-args]

PROXY="socks5://127.0.0.1:10808"
ZEN_BIN="${ZEN_BIN:-zen-browser}"

# Check if VPN is running
if ! curl --max-time 2 --socks5 127.0.0.1:10808 --silent https://httpbin.org/ip >/dev/null 2>&1; then
    echo "❌ VPN SOCKS5 proxy not working on 127.0.0.1:10808"
    echo "Start VPN first: just vpn-start"
    exit 1
fi

echo "🚀 Starting zen-browser with VPN proxy ($PROXY)"
echo "   All traffic will go through the VPN"

# Set proxy environment variables
export ALL_PROXY="$PROXY"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export NO_PROXY="localhost,127.0.0.1,::1"

# Also set for possible internal browser proxy detection
export SOCKS_PROXY="127.0.0.1:10808"
export SOCKS_SERVER="127.0.0.1:10808"

# Launch zen-browser with any passed arguments
# Add proxy flags for Chromium-based browsers
exec "$ZEN_BIN" \
  --proxy-server="socks5://127.0.0.1:10808" \
  --host-resolver-rules="MAP * 0.0.0.0 , EXCLUDE 127.0.0.1" \
  "$@"