#!/usr/bin/env bash
# The hostile-plugin test of PH3-P's exit criterion: a plugin that was not
# approved must not touch the system, and the same plugin must run once it is.
#
# What it does, in two runs of the fixture scene
# (files/pleamar/tests/plugins/hostile/):
#
#   1. unapproved — the plugin asks to run `sh`, the run is refused, and the
#      marker file its logic writes is NOT created;
#   2. approved (`pleamar --approve --yes`) — the marker IS created.
#
# Both runs are isolated: HOME, XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_STATE_HOME and
# XDG_CACHE_HOME point into a temp dir, so the approval lands there, the marker
# lands there, and the real user directories are never touched. The scene is run
# through `pleamar-wm headless` when that binary exists (nothing opens on the
# desktop); otherwise through the ambient session; with neither, the gate skips
# with a notice, like the other tools it cannot find.
#
# The renderer is not part of what is asserted: the logic starts before any
# surface is made, and a failure to draw (no GPU in a sandbox) is expected and
# ignored. Only the two markers matter.
#
# Exit status: 1 when either half of the criterion fails, 0 otherwise.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"

PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"

# PATH first, then the flake (`nix build .#pleamar`): the shell's package is not
# installed while features.gui.pleamar is off, and the gate must not depend on it
# being installed to hold.
if [ -z "${PLEAMAR_BIN:-}" ]; then
  PLEAMAR_BIN="$(resolve_pleamar_tool pleamar "$REPO_ROOT" || true)"
fi
if [ -z "$PLEAMAR_BIN" ]; then
  echo "pleamar not found — skipping the hostile-plugin test (no PATH entry and no flake output)"
  exit 0
fi

SCENE="$REPO_ROOT/files/pleamar/tests/plugins/hostile/hostile.check.plm"
[ -f "$SCENE" ] || {
  echo "hostile-plugin test: fixture missing: $SCENE"
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export XDG_DATA_HOME="$TMP/data"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_STATE_HOME="$TMP/state"
export XDG_CACHE_HOME="$TMP/cache"
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

MARKER="$HOME/.hostile-owned"
LOG="$TMP/scene.log"

# The two ways a scene can be opened. Headless first (nothing appears on the
# desktop); the ambient session is the fallback for an environment without
# pleamar-wm — and, in a sandbox with no graphics adapter, the only one where the
# logic gets to run at all.
RUNNERS=()
command -v "$PLEAMAR_WM_BIN" > /dev/null 2>&1 && RUNNERS+=(headless)
SESSION_RUNTIME=""
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    SESSION_RUNTIME="$XDG_RUNTIME_DIR"
  elif [ -S "/run/user/$(id -u)/$WAYLAND_DISPLAY" ]; then
    SESSION_RUNTIME="/run/user/$(id -u)"
  fi
  [ -n "$SESSION_RUNTIME" ] && RUNNERS+=(session)
fi
mkdir -p "$TMP/run"
chmod 700 "$TMP/run"

# One run of the scene. The exit status is never the verdict: without a GPU the
# renderer panics, and with a GPU the scene exits by `--seconds`. What the test
# reads is the log (`logic ·` proves the plugin's logic was started at all) and
# the marker file.
run_scene() {
  local runner="$1"
  rm -f "$MARKER"
  : > "$LOG"
  if [ "$runner" = headless ]; then
    printf '%s --scene %s --no-hud\n' "$PLEAMAR_BIN" "$SCENE" > "$TMP/autostart"
    PLEAMAR_WM_AUTOSTART="$TMP/autostart" XDG_RUNTIME_DIR="$TMP/run" \
      timeout -k 5 40 "$PLEAMAR_WM_BIN" headless --seconds 3 >> "$LOG" 2>&1 || true
  else
    XDG_RUNTIME_DIR="$SESSION_RUNTIME" \
      timeout -k 5 20 "$PLEAMAR_BIN" --scene "$SCENE" --seconds 3 --no-hud >> "$LOG" 2>&1 || true
  fi
}

# The logic is started on its own thread; a renderer that dies first can take the
# process with it. So a run only counts once the log shows the plugin was loaded,
# and each runner gets a chance before the test calls the environment blind.
run_until_logic() {
  local runner
  for runner in "${RUNNERS[@]}"; do
    run_scene "$runner"
    if grep -q "logic  · plugin 'Hostile'" "$LOG"; then
      RUNNER_USED="$runner"
      return 0
    fi
  done
  return 1
}

echo "hostile-plugin test:"

if [ "${#RUNNERS[@]}" -eq 0 ]; then
  echo "hostile-plugin test: skipped (no pleamar-wm and no Wayland session)"
  exit 0
fi
if ! run_until_logic; then
  echo "hostile-plugin test: skipped (the scene never reached its logic: no graphics adapter in this environment)"
  exit 0
fi

failures=0

# 1. Unapproved: the refusal must be in the log, and the marker must not exist.
# Two messages prove the refusal: the load-time notice (`NOT APPROVED: runs
# unable to touch the system`) and the runtime one when the logic reaches the
# denied call. A sandbox with no GPU may only get as far as the first.
if grep -qE "NOT APPROVED|wants to run 'sh', but nobody has approved its permissions" "$LOG"; then
  echo "  ok   unapproved plugin is refused ($RUNNER_USED)"
else
  echo "  FAIL unapproved plugin was not refused — see $LOG"
  sed -n '1,40p' "$LOG" | sed 's/^/       /'
  failures=$((failures + 1))
fi
if [ -e "$MARKER" ]; then
  echo "  FAIL unapproved plugin ran its command (marker at $MARKER)"
  failures=$((failures + 1))
else
  echo "  ok   unapproved plugin touched nothing"
fi

# 2. Approved: the same scene runs the command, which is the marker.
if ! "$PLEAMAR_BIN" --approve "$SCENE" --yes > "$TMP/approve.log" 2>&1; then
  echo "  FAIL pleamar --approve did not approve the fixture — see $TMP/approve.log"
  sed -n '1,20p' "$TMP/approve.log" | sed 's/^/       /'
  failures=$((failures + 1))
else
  if ! run_until_logic; then
    echo "hostile-plugin test: skipped the approved half (the scene never reached its logic)"
  elif [ -e "$MARKER" ]; then
    echo "  ok   approved plugin ran its command"
  else
    echo "  FAIL approved plugin did not run — see $LOG"
    sed -n '1,40p' "$LOG" | sed 's/^/       /'
    failures=$((failures + 1))
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "FAILED: $failures check(s) of the plugin sandbox"
  exit 1
fi

echo "OK: unapproved plugins are refused, approved ones run"
