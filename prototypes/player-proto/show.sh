#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
"$here/launch-live.sh" --shot-after=900 >/dev/null 2>&1 &
app=$!
sleep 4
geo=$(hyprctl -j clients | jq -r '[.[] | select(.class=="player")] | last | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
echo "geo=$geo" > /tmp/show.txt
env -u LD_LIBRARY_PATH grim -g "$geo" /tmp/show-win.png >> /tmp/show.txt 2>&1
kill "$app" 2>/dev/null
