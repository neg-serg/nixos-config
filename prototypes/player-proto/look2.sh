#!/usr/bin/env bash
# Capture the player's own window (not the whole screen) a few seconds after start.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: > /tmp/look2.txt
"$here/launch-live.sh" --size=1200x800 --shot-after=900 > /dev/null 2>&1 &
app=$!
sleep 5
geo=$(hyprctl -j clients | jq -r '[.[] | select(.title|test("Player"))] | last | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
echo "geo=$geo" >> /tmp/look2.txt
env -u LD_LIBRARY_PATH grim -g "$geo" /tmp/look2-win.png >> /tmp/look2.txt 2>&1
magick /tmp/look2-win.png -format "win %wx%h mean=%[mean] std=%[standard-deviation]\n" info: >> /tmp/look2.txt 2>&1
kill "$app" 2> /dev/null
