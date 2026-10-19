#!/usr/bin/env bash
# Launch the player for a few seconds and capture the screen; the app exits by itself so no
# window is ever killed (window unmap is what tripped hy3 earlier).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
"$here/launch-live.sh" --size=1600x1000 --shot-after=420 > /dev/null 2>&1 &
sleep 3
env -u LD_LIBRARY_PATH grim /tmp/live-screen.png 2> /tmp/live-grim.log
wait
magick /tmp/live-screen.png -format "screen %wx%h\n" info: > /tmp/live-geo.txt 2>&1
