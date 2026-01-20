#!/usr/bin/env bash
set -e

# profile-deploy.sh
#
# Comprehensive profiling for the 'just deploy' workflow (NixOS configuration).
#
# USAGE:
#   ./scripts/dev/profile-deploy.sh [hostname]
#
# DESCRIPTION:
#   This script performs a detailed performance analysis of the deployment process.
#   It isolates the two main phases of a NixOS deployment:
#   1. Nix Evaluation (instantiation): Profiled using Valgrind (Callgrind) to identify
#      slow functions and attribute evaluations in the Nix code.
#   2. Real-world Deployment: Timed using 'time' to measure actual wall-clock
#      performance of the full 'just deploy' command.
#
#   Results are saved in a timestamped directory under benchmarks/.

# --- Configuration ---
HOST="${1:-$(hostname)}"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPO_ROOT="$(git rev-parse --show-toplevel)"
OUT_DIR="$REPO_ROOT/benchmarks/${TIMESTAMP}_${HOST}"

# Ensure output directory exists
mkdir -p "$OUT_DIR"

echo "================================================================"
echo "  NixOS Deployment Profiler"
echo "================================================================"
echo "Target Host : $HOST"
echo "Date        : $TIMESTAMP"
echo "Output Dir  : $OUT_DIR"
echo "================================================================"
echo ""

# --- Phase 1: Nix Evaluation Profiling (Valgrind/Callgrind) ---
# This is the most critical part for debugging "slow config evaluation".
# We use nix-instantiate to compute the .drv file without building it.
# We wrap it in valgrind to trace every function call in the Nix evaluator.

echo "[Phase 1/2] Profiling Nix Evaluation with Valgrind (Callgrind)..."
echo "  > This uses the C++ Nix evaluator and is VERY slow (20x-50x)."
echo "  > It measures CPU instructions, not wall time."
echo "  > Please wait..."

# Note: We use --dry-run on nix build or nix-instantiate.
# The Justfile uses: nix build .#nixosConfigurations.{{host}}.config.system.build.toplevel
# We replicate that logic for instantiation.

TARGET_ATTR=".#nixosConfigurations.${HOST}.config.system.build.toplevel"

# We use nix-instantiate directly as it's cleaner for profiling than 'nix build --dry-run'
# which might invoke other CLI overhead.
# We redirect stdout/stderr to separate logs.

valgrind \
  --tool=callgrind \
  --callgrind-out-file="$OUT_DIR/callgrind.out" \
  --trace-children=yes \
  nix build "$TARGET_ATTR" --dry-run > "$OUT_DIR/eval_stdout.log" 2> "$OUT_DIR/eval_stderr.log"

echo "  > Evaluation profile saved to: $OUT_DIR/callgrind.out"
echo "  > You can analyze this file using 'kcachegrind' or 'qcachegrind'."
echo ""

# --- Phase 2: Full Deployment Benchmark (Wall Clock) ---
# This measures the actual time it takes to run 'just deploy', including
# evaluation (without valgrind overhead), build (if needed), and activation.
# We use the GNU 'time' utility for detailed stats (memory, I/O).

echo "[Phase 2/2] Benchmarking 'just deploy' (Real World Performance)..."
echo "  > Running: just deploy host=\"$HOST\""

TIME_OUT="$OUT_DIR/time_stats.txt"

# Ensure we have the 'time' binary (bash builtin 'time' is less verbose)
TIME_BIN=$(which time || echo "time")

# We use a custom format for 'time' to capture useful metrics
# %E: Elapsed real time
# %U: User CPU time
# %S: System CPU time
# %P: CPU percentage
# %M: Max resident set size (kbytes)
TIME_FMT="Real: %E\nUser: %U\nSys:  %S\nCPU:  %P\nMaxMem: %Mk"

# Run the command
{
  $TIME_BIN -f "$TIME_FMT" just deploy host="$HOST"
} 2> "$TIME_OUT"

echo "  > Benchmark complete."
echo "  > Stats saved to: $TIME_OUT"
echo ""
cat "$TIME_OUT"
echo ""

echo "================================================================"
echo "Profiling Complete."
echo "Archive: $OUT_DIR"
echo "================================================================"
