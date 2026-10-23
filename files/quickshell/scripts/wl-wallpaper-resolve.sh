#!/bin/sh
# Wallpaper resolver — one answer for both halves of the login.
#
# Two things paint a wallpaper: the login layer (files/quickshell/greeter/login.qml,
# fed by files/quickshell/scripts/login-wallpaper.sh) and wl-daemon, which paints the desktop *and*
# already paints it behind the login screen's lock surface (the session wrapper
# starts the daemon before the compositor shows the login screen, see
# modules/user/session/greetd/session-wrapper.sh + the login branch of
# files/gui/hypr/hyprland.lua). Any disagreement between the two is visible as a
# jump/flash exactly when the lock is released, so both ask this script.
#
# Priority — the first candidate that is a readable file wins:
#   1. ~/.cache/quickshell-wallpaper-path — what the session last applied, whichever
#                                           program applied it: wl-state-sync writes it
#                                           in wl mode, the picker's scripts/wallpaper-apply
#                                           writes it while the picker paints (the default)
#   2. wl state.json                      — what the wl daemon itself uses
#   3. last-good                          — last path that existed when checked
#   4. any image in ~/pic/wl (random)     — keeps a fresh install from a blank screen
#
# The notify file goes first because in picker mode wl's state is a leftover from
# before the switch and would pin the login screen to the old wallpaper.
#
# 2026-09-19: state.json and the notify file both named
# ~/pic/wl/light/ball_glow_light_192913_3840x2400.jpg, which no longer exists
# (the collection had been reorganised). login-wallpaper.sh validated the path and
# silently fell back to a *random* image, so the login screen showed a wallpaper
# the session never used, while `wl restore` exits 0 without painting anything —
# the desktop came up black. Wallpapers get deleted, renamed and moved all the
# time, so every candidate is checked here instead of being trusted, and the
# session side (wlRestoreRetry / ~/.local/bin/wl-restore) repairs wl's state from
# this answer.
#
# Prints an absolute path on stdout, or nothing when the collection is empty.
# Always exits 0 — the caller decides what an empty answer means (the login layer
# paints its dot grid).

set -u

home="${HOME:?HOME is not set}"
state="$home/.local/state/wl/state.json"
notify="$home/.cache/quickshell-wallpaper-path"
last_good="$home/.local/state/wl/last-good"

# Surrounding whitespace/newlines only: a wallpaper name may contain spaces, so
# `tr -d '[:space:]'` (what the callers used before) would corrupt such a path.
trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Prints the path and succeeds when it is a readable regular file.
usable() {
  candidate="$(trim "${1:-}")"
  if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -r "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

if [ -r "$notify" ]; then
  usable "$(head -n1 "$notify" 2> /dev/null || true)" && exit 0
fi

if [ -r "$state" ]; then
  usable "$(jq -r '.outputs | to_entries | .[0].value.wallpaper_path // empty' "$state" 2> /dev/null || true)" && exit 0
fi

if [ -r "$last_good" ]; then
  usable "$(head -n1 "$last_good" 2> /dev/null || true)" && exit 0
fi

# Nothing usable is on record: pick one from the collection (one level of
# subdirectories — the themed sets like light/ sit next to the loose images, and
# the old top-level-only `find` never saw them) and *remember* the pick. Remembering
# is what keeps the two callers in step: the login layer resolves first (it runs
# before the compositor), then wl-daemon's restore asks again a second or two later,
# and without a record each call would draw a different random image — a visible
# switch exactly when the lock is released. The record is last-good, i.e. "the file
# the last fallback landed on".
fallback="$(
  find "$home/pic/wl" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) \
    2> /dev/null | sort -R | head -n1 || true
)"
if usable "$fallback"; then
  mkdir -p "$(dirname "$last_good")" 2> /dev/null || true
  printf '%s\n' "$(trim "$fallback")" > "$last_good" 2> /dev/null || true
  exit 0
fi

exit 0
