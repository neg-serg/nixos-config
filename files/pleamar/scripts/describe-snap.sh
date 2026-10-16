#!/usr/bin/env bash
# describe-snap.sh - commit and verify `pleamar --say NAME describe json`.
#
# Starts one scene in a sandbox (pleamar-wm headless when available; with
# --live, directly in the current session), waits until its socket answers
# `pleamar --say NAME describe`, captures `describe json` into
# tests/<scene>.describe.json and kills what it started. Without --update the
# captured tree is diffed against the committed snapshot and the script exits
# non-zero on drift, printing a human-readable summary.
#
# Usage: describe-snap.sh [--update] [--timeout N] [--scene NAME]
#                         [--live] [--keep-tmp] [SCENE]
# Environment: PLEAMAR_BIN (default: pleamar), PLEAMAR_WM_BIN (default:
# pleamar-wm).
#
# Exit: 0 snapshot matches (or was written with --update), 1 drift or the scene
# failed to answer, 2 usage or missing-tool error.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOL_NAME="describe-snap"

# ---- defaults ---------------------------------------------------------------

SNAP_UPDATE=0
LIVE=0
KEEP_TMP=0
SOFT=0
TIMEOUT=15
SCENE_ARG=""

PLEAMAR_BIN="${PLEAMAR_BIN:-pleamar}"
PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"
SOFT_ICD="${PLEAMAR_SOFT_ICD:-/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json}"

TEMPROOT=""
STARTED_PIDS=()
SNAP_TMP=""

PLEAMAR=""
PLEAMAR_WM=""
JQ=""
RUNNER_PID=""
SCENE_NAME=""
SCENE_FILE=""
SCENE_LOG=""

# ---- output helpers ---------------------------------------------------------

say() { printf 'describe-snap: %s\n' "$*"; }
warn() { printf 'describe-snap: warning: %s\n' "$*" >&2; }
fail() {
  printf 'describe-snap: error: %s\n' "$*" >&2
  exit 1
}
die() {
  printf 'describe-snap: error: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat << 'EOF'
describe-snap.sh - commit and verify `pleamar --say NAME describe json`

Starts one scene without touching the live session (pleamar-wm headless when
available; --live runs it in the current session instead), waits for its
socket, captures the agent tree into tests/<scene>.describe.json and kills
what it started.

Usage:
  describe-snap.sh [options] [SCENE]

  SCENE may be a scene name (shells/<name>/<name>.plm) or a path to a .plm
  file. With no SCENE and exactly one scene in the tree, that one is used.

Options:
  --update          write/rewrite the snapshot instead of diffing it
  --scene NAME      same as the positional SCENE
  --timeout N       seconds to wait for the socket (default: 15)
  --live            use the ambient environment: starts a real surface in the
                    current session when WAYLAND_DISPLAY is set (killed after)
  --keep-tmp        keep the per-run temp dir for debugging
  --soft            software Vulkan: export VK_ICD_FILENAMES=<lavapipe>
                    (default /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json)
                    unless VK_ICD_FILENAMES is already set; not the default
  -h, --help        this text

Environment:
  PLEAMAR_BIN       pleamar binary (default: pleamar from PATH)
  PLEAMAR_WM_BIN    pleamar-wm binary (default: pleamar-wm from PATH)
  PLEAMAR_SOFT_ICD  ICD used by --soft
  VK_ICD_FILENAMES  honoured when already set; --soft never overrides it

Exit status:
  0  snapshot matches, or --update wrote it
  1  drift, missing committed snapshot, or the scene never answered
  2  bad usage, or the required tool is not available
EOF
}

# ---- cleanup ----------------------------------------------------------------

terminate() {
  local pid=$1
  local pgid=""
  local i=0
  if [ -z "$pid" ]; then
    return 0
  fi
  if ! kill -0 "$pid" 2> /dev/null; then
    return 0
  fi
  pgid="$(ps -o pgid= -p "$pid" 2> /dev/null | tr -d ' ' || true)"
  if [ -n "$pgid" ] && [ "$pgid" = "$pid" ]; then
    kill -TERM -- "-$pid" 2> /dev/null || true
  else
    kill -TERM "$pid" 2> /dev/null || true
  fi
  while [ "$i" -lt 30 ]; do
    if ! kill -0 "$pid" 2> /dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  if [ -n "$pgid" ] && [ "$pgid" = "$pid" ]; then
    kill -KILL -- "-$pid" 2> /dev/null || true
  else
    kill -KILL "$pid" 2> /dev/null || true
  fi
  return 0
}

cleanup() {
  local code=$?
  local pid=""
  trap - EXIT INT TERM
  if [ "${#STARTED_PIDS[@]}" -gt 0 ]; then
    for pid in "${STARTED_PIDS[@]}"; do
      terminate "$pid"
    done
  fi
  if [ -n "$SNAP_TMP" ] && [ -e "$SNAP_TMP" ]; then
    rm -f -- "$SNAP_TMP"
  fi
  if [ -n "$TEMPROOT" ] && [ "$KEEP_TMP" -eq 0 ]; then
    rm -rf -- "$TEMPROOT"
  fi
  exit "$code"
}

trap cleanup EXIT INT TERM

# ---- small helpers ----------------------------------------------------------

resolve_bin() {
  local val=$1
  if [ -z "$val" ]; then
    return 1
  fi
  case "$val" in
    */*)
      if [ -x "$val" ]; then
        printf '%s\n' "$val"
        return 0
      fi
      ;;
    *)
      if command -v "$val" > /dev/null 2>&1; then
        command -v "$val"
        return 0
      fi
      ;;
  esac
  return 1
}

require_uint() {
  local value=$1
  local name=$2
  case "$value" in
    '' | *[!0-9]*)
      die "$name must be a positive integer (got '$value')"
      ;;
  esac
  if [ "$value" -lt 1 ]; then
    die "$name must be at least 1"
  fi
}

setup_env() {
  TEMPROOT="$(mktemp -d "${PLEAMAR_TMPDIR:-/tmp}/pleamar-${TOOL_NAME}.XXXXXX")"
  if [ "$LIVE" -eq 1 ]; then
    warn "using the ambient environment (--live)"
    return 0
  fi
  mkdir -p -- "$TEMPROOT/home" "$TEMPROOT/config" "$TEMPROOT/data" \
    "$TEMPROOT/cache" "$TEMPROOT/state" "$TEMPROOT/run" "$TEMPROOT/pleamar-config"
  chmod 700 -- "$TEMPROOT/run"
  export HOME="$TEMPROOT/home"
  export XDG_CONFIG_HOME="$TEMPROOT/config"
  export XDG_DATA_HOME="$TEMPROOT/data"
  export XDG_CACHE_HOME="$TEMPROOT/cache"
  export XDG_STATE_HOME="$TEMPROOT/state"
  export XDG_RUNTIME_DIR="$TEMPROOT/run"
  export PLEAMAR_CONFIG="$TEMPROOT/pleamar-config"
  unset WAYLAND_DISPLAY WAYLAND_SOCKET 2> /dev/null || true
  say "hermetic environment under $TEMPROOT"
}

apply_soft() {
  if [ "$SOFT" -eq 0 ]; then
    return 0
  fi
  if [ -n "${VK_ICD_FILENAMES:-}" ]; then
    say "--soft: VK_ICD_FILENAMES is already set, keeping it ($VK_ICD_FILENAMES)"
    return 0
  fi
  if [ -f "$SOFT_ICD" ]; then
    export VK_ICD_FILENAMES="$SOFT_ICD"
    say "--soft: VK_ICD_FILENAMES=$SOFT_ICD (Mesa lavapipe)"
    return 0
  fi
  warn "--soft: $SOFT_ICD does not exist; continuing without software Vulkan"
  return 0
}

is_part_file() {
  local file=$1
  head -n 5 -- "$file" 2> /dev/null | grep -qE '^[[:space:]]*part[[:space:]]+[A-Za-z_]'
}

resolve_scene() {
  local arg=$1
  local file=""
  local dir=""
  local base=""
  local found=0
  SCENE_NAME=""
  SCENE_FILE=""
  if [ -n "$arg" ]; then
    if [ -f "$arg" ]; then
      SCENE_FILE="$arg"
      SCENE_NAME="$(basename -- "$arg" .plm)"
      return 0
    fi
    for dir in "$PROJECT_DIR"/shells/*/; do
      if [ ! -d "$dir" ]; then
        continue
      fi
      base="$(basename -- "$dir")"
      if [ "$base" = "$arg" ] && [ -f "$dir$base.plm" ]; then
        SCENE_NAME="$base"
        SCENE_FILE="$dir$base.plm"
        return 0
      fi
    done
    for file in "$PROJECT_DIR"/shells/*/"$arg".plm; do
      if [ -f "$file" ]; then
        SCENE_NAME="$arg"
        SCENE_FILE="$file"
        return 0
      fi
    done
    return 1
  fi
  for file in "$PROJECT_DIR"/shells/*/*.plm; do
    if [ ! -f "$file" ]; then
      continue
    fi
    if is_part_file "$file"; then
      continue
    fi
    SCENE_NAME="$(basename -- "$file" .plm)"
    SCENE_FILE="$file"
    found=$((found + 1))
  done
  if [ "$found" -eq 1 ]; then
    return 0
  fi
  if [ "$found" -eq 0 ]; then
    say "no scene found under $PROJECT_DIR/shells"
    return 1
  fi
  say "several scenes found; name one of them:"
  for file in "$PROJECT_DIR"/shells/*/*.plm; do
    if [ -f "$file" ] && ! is_part_file "$file"; then
      say "  $(basename -- "$file" .plm)"
    fi
  done
  return 1
}

start_runner() {
  local file=$1
  local budget=$2
  local autostart=""
  RUNNER_PID=""
  SCENE_LOG="$TEMPROOT/scene.log"
  if [ "$LIVE" -eq 1 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    say "starting the scene in the current session (--live)"
    setsid "$PLEAMAR" --scene "$file" --no-hud --seconds "$budget" >> "$SCENE_LOG" 2>&1 &
    RUNNER_PID=$!
    STARTED_PIDS+=("$RUNNER_PID")
    return 0
  fi
  if [ -n "$PLEAMAR_WM" ]; then
    say "starting the scene in pleamar-wm headless"
    autostart="$TEMPROOT/autostart"
    printf '%s --scene %s --no-hud\n' "$PLEAMAR" "$file" > "$autostart"
    PLEAMAR_WM_AUTOSTART="$autostart" \
      PLEAMAR_HEADLESS_AT=1 \
      PLEAMAR_HEADLESS_PNG="$TEMPROOT/headless.png" \
      setsid "$PLEAMAR_WM" headless --seconds "$budget" >> "$SCENE_LOG" 2>&1 &
    RUNNER_PID=$!
    STARTED_PIDS+=("$RUNNER_PID")
    return 0
  fi
  if [ "$LIVE" -eq 1 ]; then
    say "--live was given but WAYLAND_DISPLAY is unset"
    return 1
  fi
  return 1
}

# Where the scene put its socket: a bare pleamar listens in $XDG_RUNTIME_DIR/pleamar,
# while under pleamar-wm's own session the directory is $XDG_RUNTIME_DIR/pleamar-<display>.
# PLEAMAR_SOCKETS is what `--say` consults, so it is discovered and exported here.
find_socket_dir() {
  local name=$1
  local sock
  sock=$(find "${XDG_RUNTIME_DIR:-/tmp}" -maxdepth 2 -type s -name "${name}.sock" 2> /dev/null | head -n 1) || true
  [ -n "$sock" ] || return 1
  dirname "$sock"
}

wait_for_socket() {
  local name=$1
  local limit=$2
  local i=0
  while [ "$i" -lt $((limit * 4)) ]; do
    if [ -z "${PLEAMAR_SOCKETS:-}" ]; then
      if found=$(find_socket_dir "$name"); then
        export PLEAMAR_SOCKETS="$found"
      fi
    fi
    if "$PLEAMAR" --say "$name" describe > /dev/null 2>&1; then
      return 0
    fi
    if [ -n "$RUNNER_PID" ] && ! kill -0 "$RUNNER_PID" 2> /dev/null; then
      return 2
    fi
    sleep 0.25
    i=$((i + 1))
  done
  return 1
}

stop_scene() {
  if [ -n "$SCENE_NAME" ]; then
    "$PLEAMAR" --say "$SCENE_NAME" quit > /dev/null 2>&1 || true
  fi
  if [ -n "$RUNNER_PID" ]; then
    terminate "$RUNNER_PID"
  fi
  return 0
}

canonicalize() {
  local file=$1
  local first
  first=$(head -c 1 -- "$file" 2> /dev/null || true)
  case "$first" in
    "{" | "[")
      if [ -n "$JQ" ]; then
        "$JQ" -S . "$file"
      else
        cat -- "$file"
      fi
      ;;
    *)
      # The 0.4.11 build answers `describe` with the human-readable tree (its
      # json form arrived later): normalise trailing whitespace, mask the parts
      # that move on their own (the clock in a label) and diff text.
      sed -e 's/[[:space:]]*$//' -e 's/[0-9][0-9]:[0-9][0-9]/HH:MM/g' -- "$file"
      ;;
  esac
}

show_log_tail() {
  printf 'describe-snap: last lines of %s:\n' "$SCENE_LOG" >&2
  tail -n 15 -- "$SCENE_LOG" >&2 2> /dev/null || true
}

drift_summary() {
  local old=$1
  local new=$2
  local added=""
  local removed=""
  local key=""
  local old_val=""
  local new_val=""
  added="$(diff -u -- "$old" "$new" | grep -c '^+[^+]' || true)"
  removed="$(diff -u -- "$old" "$new" | grep -c '^-[^-]' || true)"
  say "drift: +${added}/-${removed} lines"
  if [ -n "$JQ" ] && [ "$(head -c 1 -- "$old" 2> /dev/null || true)" = "{" ]; then
    while IFS= read -r key; do
      if ! "$JQ" -e --arg k "$key" 'has($k)' "$old" > /dev/null 2>&1; then
        say "  + top-level key added: $key"
      elif ! "$JQ" -e --arg k "$key" 'has($k)' "$new" > /dev/null 2>&1; then
        say "  - top-level key removed: $key"
      else
        old_val="$("$JQ" -cS --arg k "$key" '.[$k]' "$old")"
        new_val="$("$JQ" -cS --arg k "$key" '.[$k]' "$new")"
        if [ "$old_val" != "$new_val" ]; then
          say "  ~ top-level key changed: $key"
        fi
      fi
    done < <({
      "$JQ" -r 'keys_unsorted[]' "$old" 2> /dev/null || true
      "$JQ" -r 'keys_unsorted[]' "$new" 2> /dev/null || true
    } | sort -u)
  fi
  say "  first changed lines:"
  diff -u -- "$old" "$new" | grep -E '^[-+][^-+]' | head -n 20 | sed 's/^/    /' || true
}

# ---- main -------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --update)
      SNAP_UPDATE=1
      shift
      ;;
    --timeout)
      TIMEOUT="${2:?--timeout needs a number}"
      shift 2
      ;;
    --scene)
      if [ -n "$SCENE_ARG" ]; then
        die "more than one scene given"
      fi
      SCENE_ARG="${2:?--scene needs a scene name}"
      shift 2
      ;;
    --live)
      LIVE=1
      shift
      ;;
    --keep-tmp)
      KEEP_TMP=1
      shift
      ;;
    --soft)
      SOFT=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      if [ -n "$SCENE_ARG" ]; then
        die "more than one scene given"
      fi
      SCENE_ARG="$1"
      shift
      ;;
  esac
done

require_uint "$TIMEOUT" "--timeout"

PLEAMAR="$(resolve_bin "$PLEAMAR_BIN" || true)"
if [ -z "$PLEAMAR" ]; then
  die "pleamar not found (PLEAMAR_BIN='$PLEAMAR_BIN'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar"
fi
PLEAMAR_WM="$(resolve_bin "$PLEAMAR_WM_BIN" || true)"
JQ="$(resolve_bin jq || true)"

setup_env
apply_soft

if ! resolve_scene "$SCENE_ARG"; then
  die "cannot resolve the scene (pass a name like 'proof' or a .plm path)"
fi

if ! start_runner "$SCENE_FILE" "$((TIMEOUT + 15))"; then
  die "no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='$PLEAMAR_WM_BIN'); pass --live to start the scene in the current session, or install pleamar-wm"
fi

wait_rc=0
wait_for_socket "$SCENE_NAME" "$TIMEOUT" || wait_rc=$?
if [ "$wait_rc" -eq 2 ]; then
  say "the runner exited before the scene answered"
  show_log_tail
  die "scene '$SCENE_NAME' never came up (see log above; --keep-tmp keeps the sandbox)"
fi
if [ "$wait_rc" -ne 0 ]; then
  say "the scene did not answer 'describe' within ${TIMEOUT}s"
  show_log_tail
  die "scene '$SCENE_NAME' never answered (see log above; --keep-tmp keeps the sandbox)"
fi

RAW="$TEMPROOT/describe.raw"
FIRST=""
if "$PLEAMAR" --say "$SCENE_NAME" describe json > "$RAW" 2> "$TEMPROOT/describe.err"; then
  FIRST=$(head -c 1 -- "$RAW" 2> /dev/null || true)
fi
case "$FIRST" in
  "{" | "[") : ;; # a machine-readable tree
  *)
    if ! "$PLEAMAR" --say "$SCENE_NAME" describe > "$RAW" 2> "$TEMPROOT/describe.err"; then
      printf 'describe-snap: error: describe failed:\n' >&2
      head -n 5 -- "$TEMPROOT/describe.err" >&2 2> /dev/null || true
      show_log_tail
      die "could not capture the agent tree"
    fi
    ;;
esac

OLD="$TEMPROOT/old.json"
NEW="$TEMPROOT/new.json"
if ! canonicalize "$RAW" > "$NEW" 2> "$TEMPROOT/jq.err"; then
  printf 'describe-snap: error: the agent tree could not be normalised:\n' >&2
  head -n 5 -- "$RAW" >&2 2> /dev/null || true
  die "cannot snapshot the agent tree (--keep-tmp keeps the raw output)"
fi

SNAP="$PROJECT_DIR/tests/$SCENE_NAME.describe.json"

stop_scene

if [ "$SNAP_UPDATE" -eq 1 ]; then
  if [ -f "$SNAP" ]; then
    if ! canonicalize "$SNAP" > "$OLD" 2> /dev/null; then
      fail "the committed snapshot $SNAP is not valid JSON; fix it by hand or delete it and re-run with --update"
    fi
    if cmp -s "$OLD" "$NEW"; then
      say "snapshot unchanged: $SNAP"
      exit 0
    fi
    drift_summary "$OLD" "$NEW"
  fi
  mkdir -p -- "$PROJECT_DIR/tests"
  SNAP_TMP="$SNAP.tmp.$$"
  cp -- "$NEW" "$SNAP_TMP"
  mv -f -- "$SNAP_TMP" "$SNAP"
  SNAP_TMP=""
  say "wrote $SNAP ($(wc -c < "$SNAP" | tr -d ' ') bytes)"
  exit 0
fi

if [ ! -f "$SNAP" ]; then
  fail "no committed snapshot at $SNAP; run: describe-snap.sh --update $SCENE_NAME"
fi
if ! canonicalize "$SNAP" > "$OLD" 2> /dev/null; then
  fail "the committed snapshot $SNAP is not valid JSON; regenerate it with --update"
fi
if cmp -s "$OLD" "$NEW"; then
  say "snapshot matches: $SNAP"
  exit 0
fi
drift_summary "$OLD" "$NEW"
fail "describe tree drifted from $SNAP (review the drift above; --update rewrites it)"
