#!/usr/bin/env bash
# Benchmark nix eval performance across system configurations.
# Runs hyperfine on 3 scenarios: full odin, odin-lite, upstream baseline.
# All use --override-input to ensure consistent nixpkgs.

set -euo pipefail

# To bypass git status scanning (Hot-path #1, 8-9% eval time), set
# NIXPKGS_SLIM_PATH=path:/tmp/nixpkgs-slim which tells nix to treat the
# input as a plain filesystem path, skipping git operations entirely.
NIXPKGS_PATH="${NIXPKGS_SLIM_PATH:-/tmp/nixpkgs-slim}"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BENCH_DIR="benchmarks"
mkdir -p "$BENCH_DIR"

# ---- helpers ----

bench() {
  local label="$1" # short label for filename
  local cmd="$2"   # full nix command to benchmark

  local json_out="$BENCH_DIR/bench_${label}_${DATE}.json"

  echo "=== Benchmark: $label ==="
  echo "Command: $cmd"
  echo "Output: $json_out"
  echo ""

  hyperfine \
    --warmup 2 \
    --runs 12 \
    --prepare "rm -rf ~/.cache/nix/eval-cache-v*" \
    --export-json "$json_out" \
    "$cmd"

  echo ""
}

# ---- scenarios ----

SCENARIO_FULL="nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --override-input nixpkgs ${NIXPKGS_PATH}"
SCENARIO_LITE="nix build .#nixosConfigurations.odin-lite.config.system.build.toplevel --dry-run --override-input nixpkgs ${NIXPKGS_PATH}"
# Upstream uses NIXPKGS_UPSTREAM (or raw nixpkgs without override) — stability baseline that should NOT change across optimization rounds
SCENARIO_UPSTREAM="nix eval ${NIXPKGS_UPSTREAM:-nixpkgs}#legacyPackages.x86_64-linux.hello.outPath --raw"

bench "full_odin" "$SCENARIO_FULL"
bench "odin_lite" "$SCENARIO_LITE"
bench "upstream" "$SCENARIO_UPSTREAM"

# ---- summary ----

echo "============================================"
echo "  Benchmark Summary — $DATE"
echo "============================================"

extract_mean() {
  local json="$1"
  jq -r '.results[0].mean' "$json" 2> /dev/null || echo "N/A"
}

for label in full_odin odin_lite upstream; do
  json="$BENCH_DIR/bench_${label}_${DATE}.json"
  mean=$(extract_mean "$json")
  echo "  $label: $mean s"
done

echo "============================================"
echo "Results written to $BENCH_DIR/bench_*_${DATE}.json"
