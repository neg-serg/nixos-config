#!/usr/bin/env bash
# Launch the player for ~4 s and capture the actual screen plus its window metadata, so a
# "nothing is visible" report can be split into: not mapped / off-screen / behind / black.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=/tmp/look.txt
: > "$out"
"$here/launch-live.sh" --size=1200x800 --shot=/tmp/look-self.ppm --shot-after=240 > /dev/null 2>&1 &
app=$!
sleep 2
{
  echo "=== clients ==="
  hyprctl -j clients | jq -r '.[] | "\(.class)|\(.title)|at=\(.at)|size=\(.size)|ws=\(.workspace.name)|mapped=\(.mapped)|hidden=\(.hidden)|float=\(.floating)"'
  echo "=== monitors ==="
  hyprctl -j monitors | jq -r '.[] | "\(.name) \(.width)x\(.height) scale=\(.scale) ws=\(.activeWorkspace.name)"'
  echo "=== active ==="
  hyprctl -j activewindow | jq -r '"\(.class)|\(.title)|at=\(.at)|size=\(.size)"'
} >> "$out" 2>&1
env -u LD_LIBRARY_PATH grim /tmp/look-screen.png >> "$out" 2>&1 || echo "grim failed" >> "$out"
magick /tmp/look-screen.png -format "screen %wx%h mean=%[mean]\n" info: >> "$out" 2>&1
wait "$app" 2> /dev/null
tail -3 /tmp/live-app.log >> "$out" 2>&1
