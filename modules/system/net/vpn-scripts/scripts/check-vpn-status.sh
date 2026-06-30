#!/usr/bin/env bash
# @script
# purpose: VPN Status Check Script
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/pretty.sh"


# VPN Status Check Script
# Usage: ./check-vpn-status.sh

echo "🛡️  VPN Status Check"
echo "=================="

# Check if SOCKS5 proxy is listening
if ss -tlnp | grep -q ":10808"; then
    echo "✅ SOCKS5 proxy: 127.0.0.1:10808 (listening)"
    PROXY_LISTENING=1
else
    echo "❌ SOCKS5 proxy: Not listening on 127.0.0.1:10808"
    PROXY_LISTENING=0
fi

echo ""

# Get IP addresses
echo "🌐 IP Address Comparison:"
echo "------------------------"

VPN_IP=""
DIRECT_IP=""

if [[ "$PROXY_LISTENING" -eq 1 ]]; then
    VPN_IP=$(timeout 5 curl --socks5 127.0.0.1:10808 --silent https://ifconfig.me 2>/dev/null || echo "")
    if [[ -n "$VPN_IP" ]]; then
        echo "Through VPN:    $VPN_IP"
    else
        echo "Through VPN:    No response (VPN may be down)"
    fi
else
    echo "Through VPN:    Not available (proxy not listening)"
fi

DIRECT_IP=$(timeout 5 curl --silent https://ifconfig.me 2>/dev/null || echo "")
if [[ -n "$DIRECT_IP" ]]; then
    echo "Direct:         $DIRECT_IP"
else
    echo "Direct:         No response (check internet connection)"
fi

echo ""

# Determine status
if [[ -n "$VPN_IP" && -n "$DIRECT_IP" ]]; then
    if [[ "$VPN_IP" != "$DIRECT_IP" ]]; then
        echo "🎉 STATUS: VPN ACTIVE - IP changed (blocking bypassed!)"
    else
        echo "⚠️  STATUS: VPN connected but IP unchanged"
        echo "   This could mean:"
        echo "   - VPN server is blocked"
        echo "   - Using same exit node"
        echo "   - VPN configuration issue"
    fi
elif [[ -n "$VPN_IP" && -z "$DIRECT_IP" ]]; then
    echo "✅ STATUS: VPN working (direct connection failed)"
elif [[ -z "$VPN_IP" && -n "$DIRECT_IP" ]]; then
    echo "❌ STATUS: VPN not responding (direct connection works)"
else
    echo "❌ STATUS: No internet connection"
fi

echo ""

# Quick connectivity test to common sites
if [[ "$PROXY_LISTENING" -eq 1 && -n "$VPN_IP" ]]; then
    echo "🔗 Quick connectivity test through VPN:"
    echo "--------------------------------------"
    
    sites=(
        "Google|https://google.com"
        "GitHub|https://github.com"
        "Twitter/X|https://x.com"
        "Telegram|https://t.me"
        "RuTracker|https://rutracker.org"
    )
    
    for site in "${sites[@]}"; do
        name="${site%|*}"
        url="${site#*|}"
        
        echo -n "   $name: "
        if timeout 3 curl --socks5 127.0.0.1:10808 --silent --head "$url" 2>/dev/null | head -1 | grep -q "HTTP"; then
            echo "✅ Accessible"
        else
            echo "❌ Not accessible"
        fi
    done
fi

echo ""

# Xray process check
echo "⚙️  Process Check:"
echo "----------------"
if pgrep -af "xray.*config.json" >/dev/null; then
    echo "✅ Xray process: Running"
    pgrep -af "xray.*config.json" | head -1
else
    echo "❌ Xray process: Not found"
    echo "   Start with: ~/.local/bin/xray run -config ~/.config/sing-box-tun/config.json"
fi

echo ""

# Recommendations
echo "💡 Recommendations:"
echo "-----------------"
if [[ "$PROXY_LISTENING" -eq 0 ]]; then
    echo "1. Start VPN: ~/.local/bin/xray run -config ~/.config/sing-box-tun/config.json &"
elif [[ -z "$VPN_IP" ]]; then
    echo "1. VPN not responding - check logs: ~/.local/bin/xray run -config ~/.config/sing-box-tun/config.json"
    echo "2. Re-import config: scripts/amnezia-import-tun-config.sh import"
elif [[ "$VPN_IP" == "$DIRECT_IP" ]]; then
    echo "1. IP unchanged - try different VPN server in AmneziaVPN"
    echo "2. Re-import config: scripts/amnezia-import-tun-config.sh import"
else
    echo "1. VPN working correctly! Use:"
    echo "   curl --socks5 127.0.0.1:10808 https://any-site.com"
    echo "   export ALL_PROXY=socks5://127.0.0.1:10808"
fi

echo ""
echo "📋 Quick commands:"
echo "   Test: curl --socks5 127.0.0.1:10808 https://ifconfig.me"
echo "   Stop: pkill -f 'xray.*config.json'"
echo "   Start: ~/.local/bin/xray run -config ~/.config/sing-box-tun/config.json &"