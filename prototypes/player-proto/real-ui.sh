#!/usr/bin/env bash
# Real-session run: launch the player, wait for its window, float+resize+focus it,
# capture the whole screen with grim, bench frame cost on RADV, stop.
# Launched from Hyprland (hl.dsp.exec_cmd), i.e. outside the agent sandbox.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/tmp/real-ui.txt}
SHOT=${SHOT:-/tmp/real-ui.png}
BIN=$here/target/release/player
[ -s "$here/.libs" ] || "$here/libs.sh" > "$here/.libs"
libs=$(cat "$here/.libs")
run() { env -u LD_LIBRARY_PATH LD_LIBRARY_PATH="$libs" "$@"; }

{
  echo "=== launch ==="
  run "$BIN" > /tmp/real-ui-app.log 2>&1 &
  app=$!
  addr=""
  for _ in $(seq 1 40); do
    sleep 0.25
    addr=$(hyprctl -j clients 2>/dev/null | jq -r '[.[] | select(.title|test("Player — MPD"))] | last | .address // empty')
    [ -n "$addr" ] && break
  done
  echo "player window: ${addr:-none}"
  if [ -n "$addr" ]; then
    hyprctl dispatch "hl.dsp.window.float({ window = \"address:$addr\" })" >/dev/null 2>&1
    sleep 0.3
    hyprctl dispatch "hl.dsp.window.resize({ x = 1440, y = 900, window = \"address:$addr\" })" >/dev/null 2>&1
    sleep 0.3
    hyprctl dispatch "hl.dsp.window.focus({ window = \"address:$addr\" })" >/dev/null 2>&1
    hyprctl -j clients | jq -r --arg a "$addr" '.[] | select(.address==$a) | "geometry: \(.at) \(.size) floating=\(.floating) workspace=\(.workspace.name)"'
    sleep 2
    env -u LD_LIBRARY_PATH grim "$SHOT" && magick "$SHOT" -format "shot mean=%[mean] std=%[standard-deviation] %wx%h\n" info:
  fi
  echo "=== app log ==="
  tail -3 /tmp/real-ui-app.log
  kill "$app" 2>/dev/null
  wait "$app" 2>/dev/null
  echo "=== frame cost (RADV, offscreen) ==="
  run "$BIN" --bench=300 --shot-after=60 2>&1 | rg "^(bench|frame):"
  echo "=== done ==="
} > "$OUT" 2>&1
