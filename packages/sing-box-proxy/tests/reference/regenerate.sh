#!/usr/bin/env bash
# Regenerate the golden fixtures from the legacy shell proxy's Python oracle.
#
# The oracle bodies are not committed (they are unformatted Python and would
# fail the repository's ruff/black gates). This script extracts them from the
# legacy shell script into a throwaway directory, then runs them over the
# committed synthetic fixtures. It only works while the legacy script exists:
#
#     PROXY_LEGACY=/path/to/packages/local-bin/bin/proxy tests/reference/regenerate.sh
#
# No network is needed: the node lists are synthetic and obviously fake.
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
crate=$(cd -- "$here/../.." && pwd)
fixtures="$crate/tests/fixtures"
golden="$fixtures/golden"
legacy="${PROXY_LEGACY:-/etc/nixos/packages/local-bin/bin/proxy}"
tmp=$(mktemp -d /tmp/sing-box-proxy-golden.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

if [ ! -f "$legacy" ]; then
  echo "legacy shell proxy not found: $legacy" >&2
  echo "the committed goldens already exist; PROXY_LEGACY=<path> to regenerate" >&2
  exit 1
fi
python3 "$here/extract_oracle.py" "$legacy" "$tmp"

mkdir -p "$golden/gen" "$golden/bootstrap"

# Command substitution semantics of the shell script: drop trailing newlines.
strip_nl() {
  local v
  v=$(cat "$1")
  printf '%s' "$v"
}

gen_case() {
  local case=$1 nodes=$2 tg=$3 lan=$4 expect=$5
  local dir="$tmp/gen-$case"
  mkdir -p "$dir"
  local env_args=(
    "NODES_FILE=$fixtures/nodes/$nodes"
    "CFG_PATH=$dir/config.json"
    "LAN_AUTH=$(strip_nl "$fixtures/lan/$lan")"
  )
  if [ -n "$tg" ]; then
    env_args+=("TG_NODES_FILE=$fixtures/tg/$tg")
  fi
  local rc=0
  env "${env_args[@]}" python3 "$tmp/gen_cfg.py" 2> "$golden/gen/$case.stderr" || rc=$?
  if [ "$rc" -ne "$expect" ]; then
    echo "FAIL $case: exit $rc, expected $expect" >&2
    exit 1
  fi
  if [ -f "$dir/config.json" ]; then
    cp "$dir/config.json" "$golden/gen/$case.json"
  fi
  echo "gen/$case: rc=$rc"
}

# The legacy patcher writes the healed config and then calls os.chmod without
# importing os: every changed case exits 1 with a NameError after the write
# (unchanged cases never reach the call). Only the deterministic `:: Config:`
# log lines are kept in the golden (the traceback carries the throwaway path
# and changes with formatting); the Rust port performs the chmod and exits 0
# (documented intentional deviation).
bootstrap_case() {
  local case=$1 lan=$2 expect=$3
  local dir="$tmp/boot-$case"
  mkdir -p "$dir"
  cp "$fixtures/bootstrap/$case.json" "$dir/config.json"
  local rc=0
  python3 "$tmp/bootstrap_patch.py" "$dir/config.json" \
    "$(strip_nl "$fixtures/lan/$lan")" 2> "$tmp/boot-$case.stderr" || rc=$?
  if [ "$rc" -ne "$expect" ]; then
    echo "FAIL bootstrap/$case: exit $rc, expected $expect" >&2
    exit 1
  fi
  grep '^:: ' "$tmp/boot-$case.stderr" > "$golden/bootstrap/$case.stderr" || true
  cp "$dir/config.json" "$golden/bootstrap/$case.json"
  echo "bootstrap/$case: rc=$rc"
}

gen_case mixed_nolan mixed.txt "" empty.txt 0
gen_case mixed_lan mixed.txt "" lan_on.txt 0
gen_case edge_nolan edge.txt "" empty.txt 0
gen_case mixed_tg mixed.txt tg_mixed.txt empty.txt 0
gen_case no_nodes no_nodes.txt "" empty.txt 1

bootstrap_case old_no_tg lan_on.txt 1
bootstrap_case empty_tg empty.txt 1
bootstrap_case final_noop lan_on.txt 0
bootstrap_case lan_sync lan_on.txt 1
bootstrap_case lan_remove empty.txt 1
bootstrap_case reordered_dns empty.txt 0

echo "goldens rewritten under $golden"
