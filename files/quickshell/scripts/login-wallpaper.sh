#!/bin/sh
# qs login layer: resolve the wallpaper for the login screen.
#
# Difference from the greeter path (modules/user/session/greetd/wallpaper.sh):
# the login layer runs as the main user inside the session compositor, so it
# reads the user's own state directly instead of the copy the greeter had to
# make into /home/greeter/.cache. Same source priority, so the login screen
# shows the same image the desktop will use.
#
# Output: $QS_LOGIN_STATE_DIR/wallpaper (absolute path, one line) — the wrapper
# exports QS_LOGIN_STATE_DIR; the fallback matches its default.
# Exit 0 even when nothing is found — the QML falls back to its dot grid.

set -u

rt="${QS_LOGIN_STATE_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-login}"
mkdir -p "$rt"

src=""

# 1) Live path: wl / quickshell write it on every img/random/restore.
notify="$HOME/.cache/quickshell-wallpaper-path"
if [ -f "$notify" ]; then
  candidate="$(head -n1 "$notify" 2> /dev/null | tr -d '[:space:]' || true)"
  if [ -n "$candidate" ] && [ -r "$candidate" ]; then
    src="$candidate"
  fi
fi

# 2) wl daemon state — the usual source on a fresh boot, before any notify file.
if [ -z "$src" ]; then
  state="$HOME/.local/state/wl/state.json"
  if [ -f "$state" ]; then
    candidate="$(jq -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state" 2> /dev/null || true)"
    if [ -n "$candidate" ] && [ -r "$candidate" ]; then
      src="$candidate"
    fi
  fi
fi

# 3) Any wallpaper from the collection (random pick keeps the first boot varied).
if [ -z "$src" ]; then
  src="$(find "$HOME/pic/wl" -maxdepth 1 -type f 2> /dev/null | sort -R | head -n1 || true)"
fi

# 4) Hardcoded fallback.
if [ -z "$src" ] || [ ! -r "$src" ]; then
  src="$HOME/pic/wl/waterfall_jungle_dark_150290_3840x2400.jpg"
fi

if [ -r "$src" ]; then
  printf '%s\n' "$src" > "$rt/wallpaper.tmp" && mv -f "$rt/wallpaper.tmp" "$rt/wallpaper"
else
  : > "$rt/wallpaper"
fi
