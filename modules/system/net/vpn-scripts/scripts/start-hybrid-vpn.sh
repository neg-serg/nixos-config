#!/usr/bin/env bash
# @script
# purpose: Hybrid VPN setup: Xray handles XHTTP transport, sing-box handles TUN interface
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/pretty.sh"


# Hybrid VPN setup: Xray handles XHTTP transport, sing-box handles TUN interface
# Xray runs the AmneziaVPN config with XHTTP+REALITY
# sing-box creates TUN interface and routes traffic through Xray SOCKS5 proxy

XRAY_CONFIG="${1:-$HOME/.config/sing-box-tun/config.json}"
SINGBOX_CONFIG="${2:-$HOME/.config/sing-box-tun/config-singbox-hybrid-final.json}"
XRAY_BIN="${XRAY_BIN:-$HOME/.local/bin/xray}"
SINGBOX_BIN="${SINGBOX_BIN:-/usr/bin/sing-box}"
TIMEOUT=30
SOCKS5_PORT=10808
TEST_URL="https://httpbin.org/ip"

XRAY_PID=""
SINGBOX_PID=""
OVERALL_RESULT=0
BACKUP_DIR=""

# Current flow with validation points:
# 1. Pre‑start: binaries, configs, port availability
# 2. Before Xray start: verify no conflicting process
# 3. After Xray start: verify SOCKS5 proxy responsiveness
# 4. Before sing‑box start: verify Xray is healthy
# 5. After sing‑box start: verify TUN interface created
# 6. After TUN setup: verify routing rules
# 7. Cleanup: restore previous routing state

# Validation functions
check_prerequisites() {
    echo "=== Checking prerequisites ==="
    
    # Check binaries
    if [[ ! -x "$XRAY_BIN" ]]; then
        echo "❌ xray binary not found or not executable: $XRAY_BIN" >&2
        return 1
    fi
    echo "✅ xray binary: $XRAY_BIN"
    
    if [[ ! -x "$SINGBOX_BIN" ]]; then
        echo "❌ sing-box binary not found or not executable: $SINGBOX_BIN" >&2
        return 1
    fi
    echo "✅ sing-box binary: $SINGBOX_BIN"
    
    # Check configs
    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo "❌ Xray config not found: $XRAY_CONFIG" >&2
        return 1
    fi
    echo "✅ Xray config: $XRAY_CONFIG"
    
    if [[ ! -f "$SINGBOX_CONFIG" ]]; then
        echo "❌ sing-box config not found: $SINGBOX_CONFIG" >&2
        return 1
    fi
    echo "✅ sing-box config: $SINGBOX_CONFIG"
    
    # Check port availability (optional, warn if occupied)
    if ss -tlnp | grep -q ":$SOCKS5_PORT"; then
        local pid
        pid=$(ss -tlnp | grep ":$SOCKS5_PORT" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
        if [[ "$pid" != "$$" ]] && ! pgrep -f "xray.*config.json" | grep -q "$pid"; then
            echo "⚠️  Port $SOCKS5_PORT already in use by PID $pid" >&2
            echo "   If it's an existing Xray process, it will be killed later" >&2
        fi
    fi
    
    # Validate sing-box config syntax
    local check_output
    if ! check_output=$("$SINGBOX_BIN" check -c "$SINGBOX_CONFIG" 2>&1); then
        echo "❌ sing-box config syntax check failed" >&2
        echo "$check_output" >&2
        return 1
    fi
    echo "✅ sing-box config syntax valid"
    
    echo "✅ All prerequisites satisfied"
    return 0
}

test_socks5_proxy() {
    local timeout=${1:-10}
    local test_url=${2:-"https://httpbin.org/ip"}
    local port=${3:-$SOCKS5_PORT}
    
    echo "Testing SOCKS5 proxy (127.0.0.1:$port)..."
    
    # Wait for port to become available
    local attempts=0
    while ! ss -tlnp | grep -q ":$port"; do
        sleep 1
        attempts=$((attempts + 1))
        if [[ $attempts -ge 5 ]]; then
            echo "❌ SOCKS5 proxy not listening on port $port after 5 seconds" >&2
            return 1
        fi
    done
    
    # Test connectivity through proxy
    local curl_output
    if curl_output=$(curl --max-time "$timeout" --socks5 "127.0.0.1:$port" --silent --fail --show-error "$test_url" 2>&1); then
        echo "✅ SOCKS5 proxy works!"
        return 0
    else
        echo "❌ SOCKS5 proxy test failed (port $port): $curl_output" >&2
        return 1
    fi
}

verify_tun_interface() {
    echo "Verifying TUN interface setup..."
    
    # Check interface exists
    if ! ip link show sb0 >/dev/null 2>&1; then
        echo "❌ TUN interface sb0 not found" >&2
        return 1
    fi
    echo "✅ TUN interface sb0 exists"
    
    # Check interface is UP
    if ! ip link show sb0 | grep -q "state UP"; then
        echo "⚠️  TUN interface sb0 is not UP" >&2
        # Continue anyway, it might come up later
    else
        echo "✅ TUN interface sb0 is UP"
    fi
    
    # Check IP address assigned
    if ! ip addr show sb0 | grep -q "inet "; then
        echo "⚠️  TUN interface sb0 has no IP address" >&2
    else
        echo "✅ TUN interface sb0 has IP address"
        ip addr show sb0 | grep "inet " | head -1
    fi
    
    # Check routing table for VPN routes (table 200)
    if ip route show table 200 >/dev/null 2>&1; then
        echo "✅ VPN routing table (200) exists"
        local route_count; route_count=$(ip route show table 200 | wc -l)
        echo "   Found $route_count route(s) in table 200"
    else
        echo "⚠️  VPN routing table (200) not found" >&2
    fi
    
    # Test basic connectivity through TUN (optional)
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo "✅ Basic connectivity via TUN works"
    else
        echo "⚠️  Basic ping test failed (may be firewall)" >&2
    fi
    
    return 0
}

backup_routes() {
    local backup_dir="${1:-/tmp/vpn-backup-$$}"
    
    echo "Backing up current routing state to $backup_dir..."
    
    mkdir -p "$backup_dir"
    
    # Backup main routing table
    ip route show > "$backup_dir/routes-main.txt" 2>/dev/null || true
    
    # Backup table 200 if exists
    ip route show table 200 > "$backup_dir/routes-table200.txt" 2>/dev/null || true
    
    # Backup ip rules
    ip rule show > "$backup_dir/ip-rules.txt" 2>/dev/null || true
    
    # Backup interface configuration
    ip addr show > "$backup_dir/ip-addr.txt" 2>/dev/null || true
    
    echo "✅ Routing backup saved to $backup_dir"
    echo "$backup_dir"
}

# shellcheck disable=SC2329  # function is for manual/emergency use
restore_routes() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir" ]]; then
        echo "⚠️  No backup directory found: $backup_dir" >&2
        return 1
    fi
    
    echo "Restoring routing state from $backup_dir..."
    
    # Clean up any VPN-specific routes/rules first
    sudo ip route flush table 200 2>/dev/null || true
    sudo ip rule del pref 100 2>/dev/null || true
    sudo ip rule del pref 200 2>/dev/null || true
    
    # Note: We don't automatically restore from backup because
    # network state may have changed. Instead, we log what was backed up
    # and rely on the existing cleanup of VPN-specific artifacts.
    
    echo "✅ VPN-specific routing artifacts removed"
    echo "   Original state backed up in: $backup_dir"
    
    # Keep backup for inspection
    return 0
}

# shellcheck disable=SC2329  # function is called via trap
cleanup() {
    local backup_dir="${1:-}"
    
    echo ""
    echo "=== Cleanup ==="
    
    # Stop sing-box
    if [[ -n "$SINGBOX_PID" ]] && kill -0 "$SINGBOX_PID" 2>/dev/null; then
        echo "Stopping sing-box (PID $SINGBOX_PID)..."
        kill "$SINGBOX_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$SINGBOX_PID" 2>/dev/null; then
            kill -9 "$SINGBOX_PID" 2>/dev/null || true
        fi
        wait "$SINGBOX_PID" 2>/dev/null || true
    fi
    
    # Stop xray
    if [[ -n "$XRAY_PID" ]] && kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "Stopping xray (PID $XRAY_PID)..."
        kill "$XRAY_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$XRAY_PID" 2>/dev/null; then
            kill -9 "$XRAY_PID" 2>/dev/null || true
        fi
        wait "$XRAY_PID" 2>/dev/null || true
    fi
    
    # Clean up TUN interface
    sudo ip link delete sb0 2>/dev/null || true
    sudo ip route flush table 200 2>/dev/null || true
    sudo ip rule del pref 100 2>/dev/null || true
    sudo ip rule del pref 200 2>/dev/null || true
    
    # Restore routes from backup if provided
    if [[ -n "$backup_dir" ]] && [[ -d "$backup_dir" ]]; then
        echo "Routing backup available at: $backup_dir"
        echo "   Inspect if network connectivity issues persist"
    fi
    
    echo "Cleanup complete"
}




# Setup trap for cleanup
# shellcheck disable=SC2329  # function is called via trap
cleanup_wrapper() {
    cleanup "$BACKUP_DIR"
}
trap cleanup_wrapper EXIT INT TERM

# Phase 0: Prerequisite checks
if ! check_prerequisites; then
    echo "❌ Prerequisite checks failed" >&2
    exit 1
fi

echo "=== Starting Hybrid VPN (Xray + sing-box) ==="
echo "Xray config: $XRAY_CONFIG"
echo "sing-box config: $SINGBOX_CONFIG"
echo "Xray binary: $XRAY_BIN"
echo "sing-box binary: $SINGBOX_BIN"
echo ""

# Backup current routing state
BACKUP_DIR=$(backup_routes)

# Kill existing processes
pkill -f "xray.*$XRAY_CONFIG" 2>/dev/null || true
pkill -f "sing-box.*$SINGBOX_CONFIG" 2>/dev/null || true
sleep 2

# Clean up existing TUN interface
sudo ip link delete sb0 2>/dev/null || true

echo "=== Phase 1: Starting Xray (XHTTP + REALITY transport) ==="
cd "$(dirname "$XRAY_CONFIG")"
"$XRAY_BIN" run -config "$(basename "$XRAY_CONFIG")" &
XRAY_PID=$!
sleep 3

if ! kill -0 "$XRAY_PID" 2>/dev/null; then
    echo "❌ Failed to start xray" >&2
    exit 1
fi

echo "✅ Xray started (PID $XRAY_PID)"

# Test Xray SOCKS5 proxy
echo ""
if test_socks5_proxy "$TIMEOUT" "$TEST_URL" "$SOCKS5_PORT"; then
    echo "✅ Xray SOCKS5 proxy verified"
else
    echo "❌ Xray SOCKS5 proxy failed" >&2
    OVERALL_RESULT=1
    exit 1
fi

echo ""
echo "=== Phase 2: Starting sing-box (TUN interface) ==="

# Verify Xray is still running before starting sing-box
if ! kill -0 "$XRAY_PID" 2>/dev/null; then
    echo "❌ Xray process died before sing-box start" >&2
    OVERALL_RESULT=1
    exit 1
fi

# Check sing-box config (redundant but safe)
if ! "$SINGBOX_BIN" check -c "$SINGBOX_CONFIG" 2>&1; then
    echo "ERROR: sing-box config check failed" >&2
    exit 1
fi

# Start sing-box
"$SINGBOX_BIN" run -c "$SINGBOX_CONFIG" &
SINGBOX_PID=$!
sleep 5

if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then
    echo "❌ Failed to start sing-box" >&2
    OVERALL_RESULT=1
    exit 1
fi

echo "✅ sing-box started (PID $SINGBOX_PID)"

# Check TUN interface
echo ""
if verify_tun_interface; then
    echo "✅ TUN interface verified"
else
    echo "❌ TUN interface verification failed" >&2
    OVERALL_RESULT=1
    exit 1
fi

echo ""
if [[ "$OVERALL_RESULT" -eq 0 ]]; then
    echo "=== ✅ HYBRID VPN RUNNING SUCCESSFULLY ==="
    echo ""
    echo "Configuration:"
    echo "  • Xray: SOCKS5 proxy on 127.0.0.1:$SOCKS5_PORT (XHTTP+REALITY)"
    echo "  • sing-box: TUN interface sb0 with auto routing"
    echo "  • Traffic routing: Through TUN → Xray → VPN server"
    echo "  • Route backup: $BACKUP_DIR"
    echo ""
    echo "Press Ctrl+C to stop"
    echo ""
    
    # Keep running until interrupted
    while kill -0 "$XRAY_PID" 2>/dev/null && kill -0 "$SINGBOX_PID" 2>/dev/null; do
        sleep 5
    done
    
    echo "One of the services stopped"
    OVERALL_RESULT=1
else
    echo "=== ❌ HYBRID VPN FAILED ==="
fi

exit "$OVERALL_RESULT"
