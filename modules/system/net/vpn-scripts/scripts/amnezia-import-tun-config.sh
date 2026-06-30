#!/usr/bin/env bash
# @script
# purpose: Source: ~/.config/AmneziaVPN.ORG/AmneziaVPN.conf
#


set -euo pipefail

# Source: ~/.config/AmneziaVPN.ORG/AmneziaVPN.conf
# Output: ~/.config/sing-box-tun/config.json

SRC_CONFIG="${HOME}/.config/AmneziaVPN.ORG/AmneziaVPN.conf"
OUT_CONFIG="${HOME}/.config/sing-box-tun/config.json"

SHARED_PY_DIR="$(mktemp -d)"
trap 'rm -rf "${SHARED_PY_DIR}"' EXIT
SHARED_PY="${SHARED_PY_DIR}/_extract_payload.py"

cat > "${SHARED_PY}" <<'PY'
import base64
import json
import re


def extract_payload(data):
    match = re.search(r'last_config\s*=\s*@ByteArray\(([^)]*)\)', data, re.S)
    if match:
        blob = ''.join(match.group(1).split())
        padding = '=' * (-len(blob) % 4)
        try:
            decoded = base64.b64decode(blob + padding, validate=True)
            return json.loads(decoded.decode('utf-8'))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise SystemExit(f'invalid last_config payload: {exc}') from exc
    servers_match = re.search(r'serversList="(.*?)"\n', data, re.S)
    if not servers_match:
        raise SystemExit('could not locate serversList in AmneziaVPN.conf')
    servers_json = servers_match.group(1).replace('\\n', '').replace('\\"', '"')
    servers_json = servers_json.encode().decode('unicode_escape')
    try:
        servers = json.loads(servers_json)
    except json.JSONDecodeError as exc:
        raise SystemExit(f'invalid serversList JSON: {exc}') from exc
    if not servers:
        raise SystemExit('serversList is empty')
    server = servers[0]
    containers = server.get('containers', [])
    if not containers:
        raise SystemExit('no containers in server')
    container = containers[0]
    xray = container.get('xray', {})
    last_config_str = xray.get('last_config')
    if not last_config_str:
        raise SystemExit('last_config not found in xray container')
    last_config_str = last_config_str.encode().decode('unicode_escape')
    return json.loads(last_config_str)
PY

usage() {
	printf '%s\n' 'Usage: amnezia-import-tun-config.sh import|show-path|check'
}

write_runtime_config() {
	python3 - "$SRC_CONFIG" "$OUT_CONFIG" "$SHARED_PY" <<'PY'
import json
import sys
from pathlib import Path

exec(Path(sys.argv[3]).read_text())

src = Path(sys.argv[1])
out = Path(sys.argv[2])
data = src.read_text(encoding='utf-8', errors='strict')
payload = extract_payload(data)

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PY
	chmod 600 "$OUT_CONFIG"
	printf '%s\n' "$OUT_CONFIG"
}

check_runtime_config() {
	python3 - "$SRC_CONFIG" "$OUT_CONFIG" "$SHARED_PY" <<'PY'
import json
import sys
from pathlib import Path

exec(Path(sys.argv[3]).read_text())

src = Path(sys.argv[1])
out = Path(sys.argv[2])
if not src.is_file():
    raise SystemExit(f'missing source config: {src}')
if not out.is_file():
    raise SystemExit(f'missing runtime config: {out}')

data = src.read_text(encoding='utf-8', errors='strict')
expected = extract_payload(data)
current = json.loads(out.read_text(encoding='utf-8'))

current_route = current.get("route", {})
filtered_rules = [
    rule for rule in current.get("route", {}).get("rules", [])
    if rule.get("tag") != "vpn-split-router-managed"
]
if "route" in current:
    current_route["rules"] = filtered_rules
    current["route"] = current_route
expected.get("route", {}).setdefault("rules", [])

if current != expected:
    raise SystemExit(f'{out} does not match imported AmneziaVPN payload')

raise SystemExit(0)
PY
}

case "${1:-import}" in
import)
	if [[ ! -f "$SRC_CONFIG" ]]; then
		printf 'ERROR: missing source config: %s\n' "$SRC_CONFIG" >&2
		exit 1
	fi
	write_runtime_config
	;;
show-path)
	printf '%s\n' "$OUT_CONFIG"
	;;
check)
	check_runtime_config
	;;
*)
	usage >&2
	exit 2
	;;
esac
