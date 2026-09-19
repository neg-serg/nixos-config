#!/bin/sh
# qs login layer: resolve the wallpaper for the login screen.
#
# Difference from the old greeter path (modules/user/session/greetd/wallpaper.sh):
# the login layer runs as the main user inside the session compositor, so it reads
# the user's own state directly instead of the copy the greeter had to make into
# /home/greeter/.cache.
#
# The resolution itself lives in wl-wallpaper-resolve.sh (same directory) so that
# this script and the session's own restore path cannot drift apart: wl-daemon
# already paints the wallpaper behind the login screen's lock surface — the
# session wrapper starts it before the compositor comes up — and the login layer
# paints the same file on top, so releasing the lock changes nothing.
# Before that split this script carried its own fallback chain, and when wl's state
# named a deleted file (2026-09-19) it silently picked a *random* image: the login
# screen then showed a wallpaper the session never used, and the desktop itself
# came up black (wl restore paints nothing and still exits 0).
#
# Output: $QS_LOGIN_STATE_DIR/wallpaper (absolute path, one line) — the wrapper
# exports QS_LOGIN_STATE_DIR; the fallback matches its default.
# Exit 0 even when nothing is found — the QML then paints its dot grid.

set -u

rt="${QS_LOGIN_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-login}"
mkdir -p "$rt"

here="$(dirname "$0")"
src=""
if [ -x "$here/wl-wallpaper-resolve.sh" ]; then
  src="$("$here/wl-wallpaper-resolve.sh" 2> /dev/null || true)"
fi

if [ -n "$src" ] && [ -r "$src" ]; then
  printf '%s\n' "$src" > "$rt/wallpaper.tmp" && mv -f "$rt/wallpaper.tmp" "$rt/wallpaper"
else
  : > "$rt/wallpaper"
fi
