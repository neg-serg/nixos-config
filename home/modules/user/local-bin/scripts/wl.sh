#!/usr/bin/env bash
# wl: set a random wallpaper from ~/pic/wl or ~/pic/black using swww
# Ensures calls are serialized so rapid keypresses queue instead of racing.
# Usage: wl

set -euo pipefail

# Acquire a simple lock (queue) using an atomic directory creation.
# This prevents overlapping swww img calls which can glitch transitions.
lock_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wl.lock.d"
acquire_lock() {
  local attempts=0
  while ! mkdir "$lock_dir" 2> /dev/null; do
    # Clean up stale lock if the recorded PID no longer exists
    if [ -f "$lock_dir/pid" ]; then
      local pid
      pid="$(cat "$lock_dir/pid" 2> /dev/null || true)"
      if [ -n "${pid}" ] && ! kill -0 "$pid" 2> /dev/null; then
        rm -rf "$lock_dir" 2> /dev/null || true
        continue
      fi
    fi
    attempts=$((attempts + 1))
    # Wait a bit and keep trying (effectively queues callers)
    sleep 0.2
    # Optional: break after ~60s to avoid hanging forever
    [ $attempts -ge 300 ] && break
  done
  echo $$ > "$lock_dir/pid" 2> /dev/null || true
}
release_lock() {
  [ -d "$lock_dir" ] && rm -rf "$lock_dir" 2> /dev/null || true
}
trap release_lock EXIT INT TERM

# Best-effort initialize swww (ignore if already running)
ensure_swww() {
  if ! swww query > /dev/null 2>&1; then
    swww init > /dev/null 2>&1 || true
    # Give the daemon a brief moment to come up
    sleep 0.05
  fi
}

pick_random_image() {
  # Collect candidate images and pick one at random
  # Exclude VCS dirs entirely: .git, .hg, .svn, .bzr
  # Use find to avoid extra dependencies; ignore errors if folders are missing
  find "$HOME/pic/wl" "$HOME/pic/black" \
    \( -type d \( -name .git -o -name .hg -o -name .svn -o -name .bzr \) -prune \) -o -type f -print 2> /dev/null \
    | shuf -n 1
}

main() {
  acquire_lock
  ensure_swww

  local img
  img="$(pick_random_image || true)"
  [ -n "${img}" ] || exit 1
  # Safety: refuse VCS paths even if selected (belt-and-suspenders)
  if is_vcs_path "$img"; then
    exit 0
  fi

  # Apply wallpaper with a smooth transition; keep fast FPS as before
  swww img --transition-fps 240 "$img" > /dev/null 2>&1 || true
}

main "$@"
# Never use images from any VCS directory (.git, .hg, .svn, .bzr)
is_vcs_path() {
  case "${1%/}" in
    */.git | */.git/* | .git | .git/*) return 0 ;;
    */.hg | */.hg/* | .hg | .hg/*) return 0 ;;
    */.svn | */.svn/* | .svn | .svn/*) return 0 ;;
    */.bzr | */.bzr/* | .bzr | .bzr/*) return 0 ;;
    *) return 1 ;;
  esac
}
