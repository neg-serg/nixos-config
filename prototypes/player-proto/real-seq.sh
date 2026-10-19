#!/usr/bin/env bash
# Real-GPU verification (run from Hyprland, i.e. RADV available):
#   1) scripted keys + offscreen captures at a fixed 1440x900 size
#   2) frame-cost bench of the same UI
# Self-terminating: no window management, no kills.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
LOG=${LOG:-/tmp/real-seq.log}
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
run() { env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$(cat "$here/.libs")" "$@" >> "$LOG" 2>&1; }
rm -f /tmp/radv-*.ppm
: > "$LOG"
run "$here/target/release/player" --render-size=1440x900 --shot-seq=/tmp/radv --keys=down,down,tab,space
run "$here/target/release/player" --render-size=1440x900 --bench=300 --shot-after=60
echo "exit=$? shots=$(ls /tmp/radv-*.ppm 2>/dev/null | wc -l)" >> "$LOG"
