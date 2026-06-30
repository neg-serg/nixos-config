#!/usr/bin/env bash
# @script
# purpose: Enable hybrid VPN (Xray + sing-box TUN) via Salt states
#

set -euo pipefail

# Enable hybrid VPN (Xray + sing-box TUN) via Salt states
# Usage: ./enable-vpn-hybrid.sh [--enable-flags] [--apply]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOSTS_YAML="$PROJECT_ROOT/states/data/hosts.yaml"
CURRENT_HOST="$(hostname)"

ENABLE_FLAGS=false
APPLY_STATES=false

usage() {
    cat <<EOF
Enable hybrid VPN (Xray + sing-box TUN) configuration via Salt.

Usage: $0 [options]

Options:
  --enable-flags   Enable vpn_hybrid, xray, and singbox flags in hosts.yaml
  --apply          Apply Salt states after enabling flags
  --help           Show this help message

Steps:
1. Enable flags in hosts.yaml (--enable-flags)
2. Apply Salt states: sudo salt-call --local state.apply network,services
3. Import AmneziaVPN config: amnezia-import-tun-config import
4. Start services: sudo systemctl start xray && sudo systemctl start sing-box-tun-hybrid

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --enable-flags)
            ENABLE_FLAGS=true
            shift
            ;;
        --apply)
            APPLY_STATES=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ $ENABLE_FLAGS == false && $APPLY_STATES == false ]]; then
    echo "No actions specified. Use --enable-flags and/or --apply."
    echo
    usage
    exit 0
fi

# Step 1: Enable flags in hosts.yaml
if [[ $ENABLE_FLAGS == true ]]; then
    echo "Enabling VPN hybrid flags in hosts.yaml for host: $CURRENT_HOST"
    
    # Check if hosts.yaml exists
    if [[ ! -f "$HOSTS_YAML" ]]; then
        echo "Error: hosts.yaml not found at $HOSTS_YAML" >&2
        exit 1
    fi
    
    # Create a backup
    BACKUP="$HOSTS_YAML.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HOSTS_YAML" "$BACKUP"
    echo "Backup created: $BACKUP"
    
    # Use Python to update the YAML
    python3 - "$HOSTS_YAML" "$CURRENT_HOST" <<'PY'
import sys
import yaml
import copy

def deep_update(target, update):
    for k, v in update.items():
        if isinstance(v, dict) and k in target and isinstance(target[k], dict):
            deep_update(target[k], v)
        else:
            target[k] = v

hosts_yaml_path = sys.argv[1]
current_host = sys.argv[2]

with open(hosts_yaml_path, 'r') as f:
    data = yaml.safe_load(f)

# Ensure the current host exists in hosts section
if 'hosts' not in data:
    data['hosts'] = {}
if current_host not in data['hosts']:
    data['hosts'][current_host] = {}

# Ensure features.network exists
if 'features' not in data['hosts'][current_host]:
    data['hosts'][current_host]['features'] = {}
if 'network' not in data['hosts'][current_host]['features']:
    data['hosts'][current_host]['features']['network'] = {}

# Set the flags
data['hosts'][current_host]['features']['network']['vpn_hybrid'] = True
data['hosts'][current_host]['features']['network']['xray'] = True
data['hosts'][current_host]['features']['network']['singbox'] = True

# Also ensure vpn_split_router is false (optional)
if 'vpn_split_router' in data['hosts'][current_host]['features']['network']:
    data['hosts'][current_host]['features']['network']['vpn_split_router'] = False

with open(hosts_yaml_path, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, width=120)

print(f"Updated hosts.yaml: enabled vpn_hybrid, xray, and singbox for host '{current_host}'")
PY
    
    echo "Flags enabled. Please review the changes in $HOSTS_YAML"
fi

# Step 2: Apply Salt states
if [[ $APPLY_STATES == true ]]; then
    echo "Applying Salt states..."
    
    # Check if we can run salt-call
    if ! command -v salt-call >/dev/null 2>&1; then
        echo "Error: salt-call not found. Install Salt first." >&2
        exit 1
    fi
    
    # Apply network and services states
    sudo salt-call --local state.apply network,services
    
    echo "Salt states applied."
fi

# Print next steps
cat <<EOF

Next steps:
1. Import AmneziaVPN configuration (if not already done):
   amnezia-import-tun-config import
   
2. Start the services:
   sudo systemctl start xray
   sudo systemctl start sing-box-tun-hybrid
   
3. Check VPN status:
   curl --socks5 127.0.0.1:10808 https://ipinfo.io/json
   # or use the TUN interface directly
   ping -c 1 1.1.1.1
   
4. (Optional) Enable services at boot:
   sudo systemctl enable xray
   # sing-box-tun-hybrid has no [Install] section, manual start only

Troubleshooting:
- Check logs: sudo journalctl -u xray -u sing-box-tun-hybrid
- Verify Xray config: sudo cat /etc/xray/config.json
- Verify sing-box config: cat ~/.config/sing-box-tun/hybrid-config.json

EOF