#!/usr/bin/env bash
# Generate a flamegraph SVG of nix eval, using perf record + inferno (or flamegraph.pl
# fallback).  Profiles nix build --dry-run on a target host configuration.
#
# Usage:
#   ./nix-flamegraph.sh [hostname]
#
# Environment:
#   NIXPKGS_SLIM_PATH  path to local nixpkgs fork  (default: /tmp/nixpkgs-slim)
#
# Output:
#   benchmarks/<timestamp>_<host>/flamegraph.svg

set -euo pipefail

# ---- configuration ----

HOST="${1:-odin}"
NIXPKGS_PATH="${NIXPKGS_SLIM_PATH:-/tmp/nixpkgs-slim}"
TS=$(date +%Y-%m-%d_%H-%M-%S)
OUT_DIR="benchmarks/${TS}_${HOST}"

# ---- helpers ----

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "=== $* ==="
}

# ---- 1. check perf_event_paranoid ----

PARANOID=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo 2)
if [ "$PARANOID" -gt 1 ]; then
  cat >&2 <<EOF
Error: kernel.perf_event_paranoid=$PARANOID — must be ≤ 1 for perf record.
Options:
  (a) Run this script as root (sudo).
  (b) Relax the restriction:
        sudo sysctl kernel.perf_event_paranoid=1
      To make permanent:
        echo 'kernel.perf_event_paranoid=1' | sudo tee /etc/sysctl.d/99-perf.conf
EOF
  exit 1
fi

# ---- 2. detect flamegraph tools (inferno preferred) ----

COLLAPSE_CMD=""
FLAMEGRAPH_CMD=""
TOOL_SOURCE=""

if command -v inferno-collapse-perf &>/dev/null && command -v inferno-flamegraph &>/dev/null; then
  COLLAPSE_CMD="inferno-collapse-perf"
  FLAMEGRAPH_CMD="inferno-flamegraph"
  TOOL_SOURCE="inferno"
elif command -v stackcollapse-perf.pl &>/dev/null && command -v flamegraph.pl &>/dev/null; then
  COLLAPSE_CMD="stackcollapse-perf.pl"
  FLAMEGRAPH_CMD="flamegraph.pl"
  TOOL_SOURCE="flamegraph.pl (Perl)"
else
  cat >&2 <<EOF
Error: no flamegraph toolchain found.
Install one of:
  (a) Inferno — nix shell '.#inferno'
  (b) FlameGraph — nix shell nixpkgs#flamegraph
EOF
  exit 1
fi

info "Using $TOOL_SOURCE for flamegraph generation"

# ---- 3. create output directory ----

mkdir -p "$OUT_DIR"

# ---- 4. clear eval cache ----

info "Clearing nix eval cache"
rm -rf ~/.cache/nix/eval-cache-v*

# ---- 5. build eval target ----

EVAL_TARGET=".#nixosConfigurations.${HOST}.config.system.build.toplevel"
info "Eval target: $EVAL_TARGET"
info "Nixpkgs override: $NIXPKGS_PATH"

PERF_DATA="$OUT_DIR/perf.data"
STACKS_FOLDED="$OUT_DIR/stacks.folded"
FLAMEGRAPH_SVG="$OUT_DIR/flamegraph.svg"

# Determine if we need sudo for perf
PERF_CMD="perf"
CHOWN_NEEDED=false

if [ "$EUID" -ne 0 ]; then
  if command -v sudo &>/dev/null; then
    info "Non-root — wrapping perf with sudo"
    PERF_CMD="sudo perf"
    CHOWN_NEEDED=true
  else
    die "Not running as root and sudo is not available. Run as root or install sudo."
  fi
fi

# ---- 6. run perf record ----

NIX_COMMAND=(
  nix build "$EVAL_TARGET" --dry-run --override-input nixpkgs "$NIXPKGS_PATH"
)

info "Running perf record (--call-graph dwarf, -F 99)"
echo "Command: ${PERF_CMD} record -g --call-graph dwarf -F 99 -o \"$PERF_DATA\" -- ${NIX_COMMAND[*]}"

# shellcheck disable=SC2086
$PERF_CMD record -g --call-graph dwarf -F 99 -o "$PERF_DATA" -- "${NIX_COMMAND[@]}"

# If dwarf produced [unknown] symbols, re-run with frame-pointer
if perf script -i "$PERF_DATA" 2>/dev/null | head -100 | grep -q '\[unknown\]'; then
  echo ""
  echo "Note: DWARF unwinding produced [unknown] symbols in some frames."
  echo "Re-running with --call-graph fp for better native frames..."
  $PERF_CMD record -g --call-graph fp -F 99 -o "$PERF_DATA" -- "${NIX_COMMAND[@]}"
fi

info "Perf recording complete"

# ---- 7. fix ownership if run with sudo ----

if [ "$CHOWN_NEEDED" = true ]; then
  SUDO_USER="${SUDO_USER:-root}"
  info "Fixing ownership on $OUT_DIR to $SUDO_USER"
  sudo chown -R "$SUDO_USER:$SUDO_USER" "$OUT_DIR"
fi

# ---- 8. collapse stacks ----

info "Collapsing perf stacks"
perf script -i "$PERF_DATA" | "$COLLAPSE_CMD" > "$STACKS_FOLDED"

# ---- 9. generate flamegraph SVG ----

info "Generating flamegraph SVG"
"$FLAMEGRAPH_CMD" "$STACKS_FOLDED" > "$FLAMEGRAPH_SVG"

# ---- 10. cleanup intermediate files ----

info "Cleaning up intermediate files"
rm -f "$PERF_DATA" "$STACKS_FOLDED"

# ---- 11. done ----

echo ""
echo "============================================"
echo "  Flamegraph generated"
echo "============================================"
echo "  Host:       $HOST"
echo "  Tool:       $TOOL_SOURCE"
echo "  SVG:        $FLAMEGRAPH_SVG"
echo "  Size:       $(du -h "$FLAMEGRAPH_SVG" | cut -f1)"
echo "============================================"
