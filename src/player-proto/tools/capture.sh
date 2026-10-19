#!/usr/bin/env bash
# Capture the frame that actually goes to the compositor.
#
# The player dumps its own presented swapchain image and exits by itself a couple of frames
# later, so this script never has to kill the app (killing it has taken the compositor down
# before). It works at any size and on both the software and the real GPU path, because the
# library resolution the binary used to need a wrapper for now happens inside the process
# (`src/preload.rs`).
#
#   tools/capture.sh                                # -> /tmp/frame.ppm, 1440x900, skin `neg`
#   tools/capture.sh --skin=neg-tunnel --size=1920x1080 --scale=2
#   OUT=/tmp/x.ppm tools/capture.sh --shot-after=180
#
# Options are passed straight through to the player; `--shot-after`, `--render-size` and
# `--shot` are the ones this script sets defaults for, and a caller-provided value wins (the
# app reads the first occurrence of each flag).
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
bin="$root/target/release/player"
out=${OUT:-/tmp/frame.ppm}
log=${LOG:-/tmp/player-capture.log}

frame=180
size=1440x900
# A capture is deterministic by definition, so the device scale is pinned to 1 unless the caller
# asks otherwise: letting the compositor pick it means the same command produces a different
# buffer on a HiDPI panel, and a late scale change mid-run rebuilds the swapchain under the dump.
scale=1
render=""
for arg in "$@"; do
  case "$arg" in
    --shot-after=*) frame=${arg#--shot-after=} ;;
    --size=*) size=${arg#--size=} ;;
    --scale=*) scale=${arg#--scale=} ;;
    --render-size=*) render=${arg#--render-size=} ;;
  esac
done

if [ ! -x "$bin" ]; then
  echo "capture: $bin is missing — run 'cargo build --release' first" >&2
  exit 2
fi

# `--size` is the logical layout size; `--scale` pins the device scale and the physical
# swapchain is derived from the two, so a 1x and a 2x capture describe the same layout and are
# comparable without upscaling either of them.
extra=(--shot-after="$frame")
if [ -n "$scale" ] && [ -z "$render" ]; then
  render=$(awk -v s="$size" -v n="$scale" 'BEGIN {
    split(s, d, "x");
    if (d[1] + 0 <= 0 || d[2] + 0 <= 0 || n + 0 <= 0) { print ""; exit }
    printf "%dx%d", d[1] * n + 0.5, d[2] * n + 0.5
  }')
  if [ -z "$render" ]; then
    echo "capture: cannot derive a render size from --size=$size --scale=$scale" >&2
    exit 2
  fi
  extra+=(--render-size="$render")
fi

rm -f "$out"
PLAYER_DUMP_SWAPCHAIN="$out" PLAYER_DEBUG_DRAW=1 \
  "$bin" "$@" "${extra[@]}" > "$log" 2>&1
status=$?

if [ ! -s "$out" ]; then
  echo "capture: the app exited ($status) without a frame at $out; see $log" >&2
  exit 1
fi
# The second header line of a P6 PPM is "<width> <height>": the reliable proof that the dump
# really happened at the requested resolution.
dims=$(head -c 64 "$out" | awk 'NR==2 { print $1"x"$2 }')
if [ -n "$render" ] && [ "$dims" != "$render" ]; then
  echo "capture: asked for $render but the dump is $dims (see the [swapchain] line in $log)" >&2
  exit 1
fi
echo "capture: $out $dims (scale=${scale:-monitor}) frame=$frame size=$size"
