#!/usr/bin/env bash
# Watch Hyprland's client list while the player starts, to see whether a window ever maps.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=/tmp/watch.txt
: > "$out"
"$here/launch-live.sh" --size=1200x800 --shot=/tmp/watch-self.ppm --shot-after=300 >/dev/null 2>&1 &
app=$!
for i in $(seq 1 16); do
  sleep 0.5
  n=$(hyprctl -j clients | jq -r '[.[] | select(.title|test("Player"; "i"))] | length')
  titles=$(hyprctl -j clients | jq -r '[.[] | .title] | join(" | ")')
  total=$(hyprctl -j clients | jq -r 'length')
  echo "t=${i} player_windows=$n total=$total titles=[$titles]" >> "$out"
done
hyprctl -j clients | jq -r '.[] | select(.title|test("Player")) | "\(.class)|\(.title)|at=\(.at)|size=\(.size)|ws=\(.workspace.name)|mapped=\(.mapped)"' >> "$out" 2>&1
wait "$app" 2>/dev/null
rg -c "\[frame\]" /tmp/live-app.log >> "$out" 2>&1
