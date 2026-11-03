#!/bin/sh
# Capture a pleamar window on screen without stealing the terminal's focus.
#
# The compositor this repo runs speaks Lua: every hyprctl dispatch here goes
# through `hl.dsp.*` (the legacy "hyprctl dispatch movewindow" form is a
# deprecated shorthand that mangles dispatchers). The terminal the caller runs in
# is stepped out to workspace 5 for the shot and put back afterwards.
#
# The window is put FULL SCREEN, not floated and centred: the login screen is a
# lock face the size of the monitor, and its scenes lay themselves out from
# `screen.width`/`screen.height`. A 1280×804 floating window measures a different
# screen, so the greeter's own preview (`shells/lock/preview.plm`) has to be the
# monitor's size for its shot to say anything about the login screen — which is
# what this script is for.
#
# The window under test is the one class `pleamar` makes (its scenes are one
# binary; the preview scene's title is "pleamar · lock preview"). The Quickshell
# class this used to look for (`org.quickshell`) went away with that shell.
#
# usage: capture-window.sh OUT.png [TYPED-TEXT]
#   TYPED-TEXT is sent to the window before the shot (e.g. a password for the
#   login preview, whose field is live).
out=${1:-/tmp/cap.png}
typed=$2

cat > /tmp/._cap_on.lua << 'LUA'
-- the terminal steps aside, the window under test takes the whole screen: a
-- tiled window next to the terminal is only half visible, and half a card is
-- not a screenshot.
hl.dispatch(hl.dsp.focus({ window = "class:term" }))
hl.dispatch(hl.dsp.window.move({ workspace = 5 }))
hl.dispatch(hl.dsp.focus({ window = "class:pleamar" }))
hl.dispatch(hl.dsp.window.move({ workspace = 1 }))
hl.dispatch(hl.dsp.window.float({ action = "set" }))
hl.dispatch(hl.dsp.window.fullscreen({ action = "set" }))
LUA
cat > /tmp/._cap_off.lua << 'LUA'
hl.dispatch(hl.dsp.focus({ window = "class:pleamar" }))
hl.dispatch(hl.dsp.window.fullscreen({ action = "unset" }))
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
# What the shot holds, in the compositor's own words: a window that is not the
# monitor's size is a preview of the wrong screen.
hyprctl clients -j | jq -r '.[] | select(.class == "pleamar")
  | "shot of \(.class) at \(.at) size \(.size)"'
grim "$out"
hyprctl eval "$(cat /tmp/._cap_off.lua)" > /dev/null
echo "saved $out"
