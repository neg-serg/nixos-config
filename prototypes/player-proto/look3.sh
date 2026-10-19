#!/usr/bin/env bash
# Capture the player window twice: right after mapping and after the HiDPI rescale.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: > /tmp/look3.txt
"$here/launch-live.sh" --size=1200x800 --shot-after=900 >/dev/null 2>&1 &
app=$!
snap() {
  local tag=$1
  local geo
  geo=$(hyprctl -j clients | jq -r '[.[] | select(.title|test("Player"))] | last | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
  echo "$tag geo=$geo" >> /tmp/look3.txt
  [ -z "$geo" ] || [ "$geo" = "null" ] && { echo "$tag: no window" >> /tmp/look3.txt; return; }
  env -u LD_LIBRARY_PATH grim -g "$geo" "/tmp/look3-$tag.png" >> /tmp/look3.txt 2>&1
  magick "/tmp/look3-$tag.png" -format "$tag %wx%h mean=%[mean] std=%[standard-deviation]\n" info: >> /tmp/look3.txt 2>&1
}
sleep 1
snap early
sleep 5
snap late
kill "$app" 2>/dev/null
