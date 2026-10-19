#!/usr/bin/env bash
# Dump the frame that actually goes to the compositor (works at any size, no offscreen copy).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
rm -f /tmp/frame.ppm
PLAYER_DUMP_SWAPCHAIN=/tmp/frame.ppm PLAYER_DEBUG_DRAW=1 "$here/launch-live.sh" "$@" --shot-after=240 >/dev/null 2>&1
