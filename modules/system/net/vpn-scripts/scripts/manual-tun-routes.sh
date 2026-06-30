#!/usr/bin/env bash
# @script
# purpose: Manual TUN interface setup for sing-box when auto_route fails
#

set -euo pipefail

# Manual TUN interface setup for sing-box when auto_route fails
# Usage: manual-tun-routes.sh start|stop

CONFIG="/home/neg/.config/sing-box-tun/config-no-auto-route.json"
TUN_IFACE="sb0"
TUN_IP="172.19.0.1"
TUN_PREFIX="30"  # /30 = 172.19.0.0-172.19.0.3

# Table ID for split tunneling (must be > 0 and not conflict with existing)
ROUTE_TABLE=200
ROUTE_TABLE_NAME="vpn-tun"

start() {
    echo "=== Starting manual TUN setup ==="
    
    # Kill existing processes
    pkill -f "sing-box.*$CONFIG" 2>/dev/null || true
    sleep 1
    
    # Clean up existing interface
    sudo ip link delete "$TUN_IFACE" 2>/dev/null || true
    
    echo "1. Starting sing-box with auto_route=false..."
    cd "$(dirname "$CONFIG")"
    /usr/bin/sing-box run -c "$(basename "$CONFIG")" > /tmp/singbox-manual.log 2>&1 &
    SINGBOX_PID=$!
    sleep 3
    
    if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then
        echo "❌ Failed to start sing-box"
        cat /tmp/singbox-manual.log
        exit 1
    fi
    
    echo "✅ sing-box started (PID $SINGBOX_PID)"
    
    # Check if TUN interface exists
    if ! ip link show "$TUN_IFACE" 2>/dev/null; then
        echo "❌ TUN interface $TUN_IFACE not created"
        kill "$SINGBOX_PID" 2>/dev/null
        exit 1
    fi
    
    echo "2. Setting up manual routing..."
    
    # Bring interface up
    sudo ip link set "$TUN_IFACE" up
    
    # Add IP address if not already assigned
    if ! ip addr show "$TUN_IFACE" | grep -q "$TUN_IP"; then
        sudo ip addr add "$TUN_IP/$TUN_PREFIX" dev "$TUN_IFACE"
    fi
    
    # Create custom routing table if it doesn't exist
    # Ensure /etc/iproute2 directory exists
    if [[ ! -d /etc/iproute2 ]]; then
        sudo mkdir -p /etc/iproute2
    fi
    if [[ ! -f /etc/iproute2/rt_tables ]]; then
        sudo touch /etc/iproute2/rt_tables
    fi
    if ! grep -q "^$ROUTE_TABLE" /etc/iproute2/rt_tables 2>/dev/null; then
        echo "$ROUTE_TABLE $ROUTE_TABLE_NAME" | sudo tee -a /etc/iproute2/rt_tables >/dev/null
    fi
    
    # Add routes to custom table
    # Default route via TUN interface
    sudo ip route add default dev "$TUN_IFACE" table "$ROUTE_TABLE"
    
    # Local network direct routes
    sudo ip route add 192.168.0.0/16 dev eno1 table "$ROUTE_TABLE" 2>/dev/null || true
    sudo ip route add 10.0.0.0/8 dev eno1 table "$ROUTE_TABLE" 2>/dev/null || true
    sudo ip route add 172.16.0.0/12 dev eno1 table "$ROUTE_TABLE" 2>/dev/null || true
    
    # Add routing rule: traffic from TUN interface uses custom table
    sudo ip rule add from "$TUN_IP" table "$ROUTE_TABLE" pref 100
    
    # Alternatively, use policy-based routing for all traffic
    # sudo ip rule add fwmark 1 table "$ROUTE_TABLE" pref 200
    
    echo "3. Testing connectivity..."
    
    # Test DNS
    echo "DNS test (should show VPN IP):"
    curl --max-time 5 --interface "$TUN_IFACE" https://httpbin.org/ip 2>/dev/null | grep origin || echo "Direct test failed"
    
    # Test that direct connection still works
    echo "Direct connection test (should show local IP):"
    curl --max-time 5 https://httpbin.org/ip 2>/dev/null | grep origin || echo "VPN test failed"
    
    echo ""
    echo "=== ✅ MANUAL TUN SETUP COMPLETE ==="
    echo "TUN interface: $TUN_IFACE"
    echo "TUN IP: $TUN_IP/$TUN_PREFIX"
    echo "Routing table: $ROUTE_TABLE ($ROUTE_TABLE_NAME)"
    echo ""
    echo "To route specific traffic through VPN:"
    echo "  sudo ip route add <destination> dev $TUN_IFACE"
    echo ""
    echo "To stop: sudo $0 stop"
    echo ""
    
    # Save PID for cleanup
    echo "$SINGBOX_PID" > /tmp/singbox-manual.pid
    echo "$TUN_IFACE" > /tmp/tun-interface.name
}

stop() {
    echo "=== Stopping manual TUN setup ==="
    
    # Kill sing-box
    if [[ -f /tmp/singbox-manual.pid ]]; then
        local pid
        pid=$(cat /tmp/singbox-manual.pid)
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping sing-box (PID $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f /tmp/singbox-manual.pid
    fi
    
    # Get interface name
    local iface="sb0"
    if [[ -f /tmp/tun-interface.name ]]; then
        iface=$(cat /tmp/tun-interface.name)
        rm -f /tmp/tun-interface.name
    fi
    
    # Clean up routing
    sudo ip rule del from "172.19.0.1" table "$ROUTE_TABLE" pref 100 2>/dev/null || true
    sudo ip rule del fwmark 1 table "$ROUTE_TABLE" pref 200 2>/dev/null || true
    sudo ip route flush table "$ROUTE_TABLE" 2>/dev/null || true
    
    # Delete interface
    sudo ip link delete "$iface" 2>/dev/null || true
    
    echo "✅ Cleanup complete"
}

case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    *)
        echo "Usage: $0 start|stop"
        echo ""
        echo "Manual TUN routing setup for sing-box when auto_route fails."
        echo "This script creates TUN interface and sets up split tunneling."
        exit 1
        ;;
esac