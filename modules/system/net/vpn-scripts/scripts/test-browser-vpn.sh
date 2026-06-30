#!/usr/bin/env bash
# @script
# purpose: Test browser VPN integration
#

# Test browser VPN integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/pretty.sh"


echo "=== Testing Browser VPN Integration ==="
echo

# Check TUN interface
echo "1. Checking TUN interface..."
if ip link show sb0 >/dev/null 2>&1; then
    echo "✅ TUN interface sb0 exists"
    ip addr show sb0 | grep -E "inet|inet6" || echo "⚠️  No IP address assigned"
else
    echo "❌ TUN interface sb0 not found"
fi

echo

# Check routing
echo "2. Checking routing tables..."
if ip route show table vpn-tun >/dev/null 2>&1; then
    echo "✅ VPN routing table exists"
    echo "   Routes in vpn-tun table:"
    ip route show table vpn-tun | sed 's/^/   /'
else
    echo "❌ VPN routing table not found"
fi

echo

# Check iptables rules
echo "3. Checking iptables rules..."
if sudo iptables -t mangle -L OUTPUT 2>/dev/null | grep -q "vpn-tun"; then
    echo "✅ iptables rules for VPN exist"
    echo "   Marking rules:"
    sudo iptables -t mangle -L OUTPUT -v | grep -E "MARK|vpn-tun" | sed 's/^/   /'
else
    echo "❌ iptables rules not found"
fi

echo

# Test connectivity
echo "4. Testing connectivity..."
echo "   Testing direct connection (should work):"
if curl -s --max-time 5 https://httpbin.org/ip >/dev/null; then
    echo "   ✅ Direct connection works"
else
    echo "   ❌ Direct connection failed"
fi

echo
echo "   Testing VPN connection (should work for RKN domains):"
echo "   Testing with example RKN domain (0-63.ru):"
if curl -s --max-time 5 --interface sb0 http://0-63.ru >/dev/null 2>&1; then
    echo "   ✅ VPN connection works for RKN domain"
else
    echo "   ⚠️  VPN connection test inconclusive (domain may not respond)"
fi

echo
echo "5. Testing browser proxy configuration..."
echo "   Current proxy settings for Zen browser:"
if [ -f ~/.config/zen-browser/profiles.ini ]; then
    echo "   ✅ Zen browser profile found"
    # Check if proxy is configured
    if grep -q "network.proxy" ~/.config/zen-browser/*.js 2>/dev/null; then
        echo "   ✅ Proxy settings found in browser config"
    else
        echo "   ⚠️  No proxy settings found in browser config"
        echo "   Note: Browser may need manual proxy configuration"
    fi
else
    echo "   ⚠️  Zen browser config not found"
fi

echo
echo "=== Summary ==="
echo "For browser to use VPN:"
echo "1. Ensure TUN interface sb0 exists"
echo "2. Configure browser to use SOCKS5 proxy: 127.0.0.1:10808"
echo "3. Or use system proxy settings"
echo "4. Test with blocked site (e.g., twitter.com)"
echo
echo "To configure Zen browser proxy:"
echo "  about:preferences#general → Network Settings → Settings..."
echo "  Select 'Manual proxy configuration'"
echo "  SOCKS Host: 127.0.0.1, Port: 10808"
echo "  Check 'Proxy DNS when using SOCKS v5'"
echo
echo "Alternative: Use the zen-vpn.sh helper script"