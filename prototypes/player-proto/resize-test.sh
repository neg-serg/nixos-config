#!/usr/bin/env bash
# Start small, resize at runtime, then let the app dump the presented frame:
# proves that layout + swapchain follow a live resize (and the HiDPI scale change).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: > /tmp/resize-test.txt
PLAYER_DUMP_SWAPCHAIN=/tmp/p-resize.ppm "$here/launch-live.sh" --size=800x600 --shot-after=400 >/dev/null 2>&1 &
app=$!
sleep 1
addr=$(hyprctl -j clients | jq -r '[.[] | select(.class=="player")] | last | .address // empty')
echo "addr=$addr" >> /tmp/resize-test.txt
[ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.resize({ x = 1400, y = 900, window = \"address:$addr\" })" >> /tmp/resize-test.txt 2>&1
sleep 4
env -u LD_LIBRARY_PATH grim -g "$(hyprctl -j clients | jq -r '[.[] | select(.class==\"player\")] | last | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" /tmp/p-resize-screen.png >> /tmp/resize-test.txt 2>&1
sleep 1
pkill -f "target/release/player"
