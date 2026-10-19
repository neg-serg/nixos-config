#!/usr/bin/env bash
# Real-session measurement. Launched from Hyprland (hyprctl dispatch hl.dsp.exec_cmd),
# i.e. outside the agent sandbox, so /dev/dri is reachable and RADV is used.
# Everything is written to $OUT; brief windows will flash on screen.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/tmp/player-proto-real.txt}
BIN=${PROTO_BIN:-$here/target/release/player-proto}
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
libs=$(cat "$here/.libs")
run() { env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" "$BIN" "$@"; }

{
  echo "=== device / surface ==="
  run --frames 1 2>&1 | rg "^(device:|device extensions|swapchain:|hdr:)"
  echo "=== startup marks (single run) ==="
  run --frames 1 2> /dev/null | rg "^(exec->ctor|main|window|fonts_ready|instance|surface|device_enum|device|swapchain|pipelines|text_layout|atlas_upload|first_present) "
  echo "=== startup, 12 runs (json) ==="
  for _ in $(seq 1 12); do run --frames 1 --json 2> /dev/null | rg '^\{'; done
  echo "=== hdr first_present, 3 runs (json) ==="
  for _ in $(seq 1 3); do run --frames 1 --hdr --json 2> /dev/null | rg '^\{'; done
  echo "=== frame cost 1100x620 ==="
  run --bench 300 --size 1100x620 2> /dev/null | rg "^frame:"
  echo "=== frame cost 1920x1080 ==="
  run --bench 300 --size 1920x1080 2> /dev/null | rg "^frame:"
  echo "=== text layout ==="
  run --bench-layout 100 2> /dev/null | rg "layout bench"
  echo "=== offscreen shot ==="
  run --frames 1 --shot /tmp/real-shot.ppm 2>&1 | rg "^wrote|shot failed"
  echo "=== done ==="
} > "$OUT" 2>&1
