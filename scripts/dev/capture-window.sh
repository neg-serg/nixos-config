#!/bin/sh
# Capture a quickshell window on screen without stealing the terminal's focus.
#
# The compositor this repo runs speaks Lua: every hyprctl dispatch here goes
# through `hl.dsp.*` (the legacy "hyprctl dispatch movewindow" form is a
# deprecated shorthand that mangles dispatchers). The terminal the caller runs in
# is stepped out to workspace 5 for the shot and put back afterwards.
#
# usage: capture-window.sh OUT.png [TYPED-TEXT]
#   TYPED-TEXT is sent to the window before the shot (e.g. a password for the
#   login preview, whose field is live).
out=${1:-/tmp/cap.png}
typed=$2

cat > /tmp/._cap_on.lua << 'LUA'
-- the terminal steps aside, the window under test takes the whole screen: a
-- tiled window next to the terminal is only half visible, and half a tube is not
-- a screenshot.
hl.dispatch(hl.dsp.focus({ window = "class:term" }))
hl.dispatch(hl.dsp.window.move({ workspace = 5 }))
hl.dispatch(hl.dsp.focus({ window = "class:org.quickshell" }))
hl.dispatch(hl.dsp.window.move({ workspace = 1 }))
-- floating and centred: the tiling layout puts a second window half off-screen,
-- and half a tube is not a screenshot
hl.dispatch(hl.dsp.window.float({ action = "set" }))
hl.dispatch(hl.dsp.window.center())
LUA
cat > /tmp/._cap_off.lua << 'LUA'
hl.dispatch(hl.dsp.focus({ window = "class:org.quickshell" }))
hl.dispatch(hl.dsp.window.float({ action = "unset" }))
hl.dispatch(hl.dsp.focus({ window = "class:term" }))
hl.dispatch(hl.dsp.window.move({ workspace = 1 }))
LUA

hyprctl eval "$(cat /tmp/._cap_on.lua)" > /dev/null
sleep 1
if [ -n "$typed" ]; then
  wtype -d 35 "$typed"
  sleep 0.6
fi
hyprctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if "quickshell" in c["class"]:
        print("shot of", c["class"], c["at"], c["size"])
'
grim "$out"
hyprctl eval "$(cat /tmp/._cap_off.lua)" > /dev/null
echo "saved $out"
