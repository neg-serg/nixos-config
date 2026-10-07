#!/bin/bash
# Show the nixie tube or the lamp workbench on an invisible monitor and take its
# picture, so tuning them never takes over the screen the user is working on.
#
# The compositor gets one extra output — a headless monitor called `lab`, four
# times the size of the tube's own pixels — and the harness is started there.
# Nothing of this touches the workspaces the user is on: no window is moved, no
# focus is taken, no wall to look at changes. `grim -o lab` then reads only that
# monitor, at the device pixel scale the acceptance limits in
# scripts/dev/nixie-metrics.py are written for (2 px per logical px).
#
# usage: nixie-shot.sh [OUT.png] [digits|lab|preview] [--keep]
#   digits (default) — ten numerals and one unlit tube, the A1..A7 harness
#   lab              — the workbench with its handles (env LAB_* apply)
#   preview          — the login card, the tube as the screen shows it
#   --keep           — leave the harness running on the lab monitor
set -e

out="${1:-/tmp/nixie-shot.png}"
what="${2:-digits}"
keep=""
for arg in "$@"; do [ "$arg" = "--keep" ] && keep="--keep"; done

case "$what" in
  digits)  config="files/quickshell/greeter/digits.qml" ;;
  lab)     config="files/quickshell/greeter/tube-lab.qml" ;;
  preview) config="files/quickshell/greeter/preview.qml" ;;
  *) echo "unknown harness: $what (digits|lab|preview)" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/../.."

# 1. the invisible monitor: 3840x2160 at scale 2 is the reference geometry
if ! hyprctl monitors -j | grep -q '"name": "lab"'; then
  hyprctl output create headless lab >/dev/null
  sleep 2
fi
hyprctl eval 'hl.monitor({ output = "lab", mode = "3840x2160@60", position = "1920x0", scale = 2 })' >/dev/null
sleep 1

# 2. the harness, fresh so it reads the .qsb that is on disk
pkill -f "$(basename "$config")" 2>/dev/null || true
sleep 1
(setsid qs -p "$config" > /tmp/nixie-harness.log 2>&1 &)
sleep 6

addr=$(hyprctl clients -j | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    if c['class'] == 'org.quickshell': print(c['address']); break
")
if [ -z "$addr" ]; then
  echo "the harness window did not appear:" >&2
  tail -3 /tmp/nixie-harness.log >&2
  exit 1
fi

# 3. onto the invisible monitor, floating, at the size the harness asks for
hyprctl dispatch "hl.dsp.window.move({ monitor = \"lab\", window = \"address:$addr\" })" >/dev/null
sleep 1
hyprctl dispatch "hl.dsp.window.float({ window = \"address:$addr\" })" >/dev/null
sleep 0.5
case "$what" in
  digits)  w=1600; h=420 ;;
  preview) w=1600; h=1000 ;;
  *)       w=660;  h=980 ;;
esac
hyprctl dispatch "hl.dsp.window.resize({ x = $w, y = $h, window = \"address:$addr\" })" >/dev/null
sleep 1
# the corner of that monitor, so the whole harness is inside the capture
read -r mx my <<< "$(python3 -c "
import json, subprocess
mo = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
mon = next(m for m in mo if m['name'] == 'lab')
print(mon['x'], mon['y'])
")"
hyprctl dispatch "hl.dsp.window.move({ x = $mx, y = $my, window = \"address:$addr\" })" >/dev/null
sleep 1

# 4. the picture: the lab monitor only, at device pixels
grim -o lab -s 2 "$out"
python3 - "$out" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
print(f"{sys.argv[1]}: {im.size[0]}x{im.size[1]} device px — "
      f"measure with: python3 scripts/dev/nixie-metrics.py {sys.argv[1]} --mode digits --check")
PY

if [ "$keep" != "--keep" ]; then
  pkill -f "$(basename "$config")" 2>/dev/null || true
fi
