#!/usr/bin/env bash
# Dump the frame that actually goes to the compositor (works at any size, no offscreen copy).
#
#   ./dumpframe.sh --size=1440x900 --scale=1 --shot-after=200   # -> /tmp/frame.ppm 1440x900
#   ./dumpframe.sh --size=1440x900 --scale=2 --shot-after=200   # -> /tmp/frame.ppm 2880x1800
#
# The app is a real windowed run: it dumps the presented swapchain image at the --shot-after
# frame and then exits by itself, so this script returns without an external kill.
#
# Determinism: --scale pins the device scale and --size is then the logical layout size, so the
# physical swapchain is derived as size * scale. Both captures carry the same logical layout, and
# the 2x one is authored at twice the device resolution instead of being upscaled — that is what
# makes a 1x/2x pair comparable. Without --scale the monitor decides and the two captures can
# land on different layouts.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${PLAYER_DUMP_SWAPCHAIN:-/tmp/frame.ppm}
log=/tmp/live-app.log

# The app reads the first occurrence of each flag, so only supply a default for a value the
# caller did not pass — a caller-provided --shot-after or --render-size wins.
frame=240
size=1440x900
scale=""
render=""
for arg in "$@"; do
  case "$arg" in
    --shot-after=*) frame=${arg#--shot-after=} ;;
    --size=*) size=${arg#--size=} ;;
    --scale=*) scale=${arg#--scale=} ;;
    --render-size=*) render=${arg#--render-size=} ;;
  esac
done

extra=(--shot-after="$frame")
if [ -n "$scale" ] && [ -z "$render" ]; then
  # Derive the physical swapchain from the logical size so the layout canvas is exactly --size.
  render=$(awk -v s="$size" -v n="$scale" 'BEGIN {
    split(s, d, "x");
    if (d[1] + 0 <= 0 || d[2] + 0 <= 0 || n + 0 <= 0) { print ""; exit }
    printf "%dx%d", d[1] * n + 0.5, d[2] * n + 0.5
  }')
  if [ -z "$render" ]; then
    echo "dumpframe: cannot derive a render size from --size=$size --scale=$scale" >&2
    exit 2
  fi
  extra+=(--render-size="$render")
fi

rm -f "$out"
PLAYER_DUMP_SWAPCHAIN="$out" PLAYER_DEBUG_DRAW=1 \
  "$here/launch-live.sh" "$@" "${extra[@]}" >/dev/null 2>&1
status=$?

if [ ! -s "$out" ]; then
  echo "dumpframe: the app exited ($status) without a frame at $out; see $log" >&2
  exit 1
fi
# The second header line of a P6 PPM is "<width> <height>": the reliable proof that the dump
# really happened at the requested resolution.
dims=$(head -c 64 "$out" | awk 'NR==2 { print $1"x"$2 }')
want=${render:-surface}
if [ -n "$render" ] && [ "$dims" != "$render" ]; then
  echo "dumpframe: asked for $render but the dump is $dims (see the [event] swapchain line)" >&2
  exit 1
fi
echo "dumpframe: $out $dims (wanted $want) scale=${scale:-monitor} frame=$frame size=$size"
