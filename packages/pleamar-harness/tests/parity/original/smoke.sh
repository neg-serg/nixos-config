#!/usr/bin/env bash
# smoke.sh - headless render matrix for the pleamar shell.
#
# For every scene under files/pleamar/shells/*/*.plm (part files, which are
# includes, are skipped) this compiles the scene and renders one PNG, keeping
# the renderer's log next to it. It never touches the developer's session:
# pleamar-wm's headless mode is used when available, otherwise a nested
# headless wlroots compositor (sway or cage) with grim. With no renderer the
# compile matrix still runs; --require-render makes the missing renderer fatal.
#
# Usage: smoke.sh [--scene NAME] [--seconds N] [--out DIR] [--require-render]
#                 [--min-bytes N] [--live] [--keep-tmp]
# Environment: PLEAMAR_BIN (default: pleamar), PLEAMAR_WM_BIN (default:
# pleamar-wm), PLEAMAR_HEADLESS_INPUT (passed through to pleamar-wm).
#
# Exit: 0 success (or no renderer without --require-render), 1 a scene check or
# render failed, 2 usage or missing-tool error.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOL_NAME="smoke"

# ---- defaults ---------------------------------------------------------------

SECONDS_TO_RUN=8
SCENE_FILTER=""
OUT_DIR="$PROJECT_DIR/tests/shots"
REQUIRE_RENDER=0
LIVE=0
KEEP_TMP=0
MIN_PNG_BYTES=1024
SOFT=0

PLEAMAR_BIN="${PLEAMAR_BIN:-pleamar}"
PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"
SOFT_ICD="${PLEAMAR_SOFT_ICD:-/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json}"

TEMPROOT=""
STARTED_PIDS=()
SCENES=()

PLEAMAR=""
PLEAMAR_WM=""
GRIM=""
RENDERER=""
RENDERER_BIN=""
AT_SECONDS_N=0

# ---- output helpers ---------------------------------------------------------

say() { printf 'smoke: %s\n' "$*"; }
warn() { printf 'smoke: warning: %s\n' "$*" >&2; }
fail() {
  printf 'smoke: error: %s\n' "$*" >&2
  exit 1
}
die() {
  printf 'smoke: error: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat << 'EOF'
smoke.sh - headless render matrix for the pleamar shell

Renders one PNG per scene without using the live session: pleamar-wm headless
when available, otherwise a nested headless wlroots compositor (sway/cage)
with grim. Part files (`part ...`, includes) are skipped. Every scene is also
compiled with `pleamar --check` first, so the matrix is useful even with no
renderer available.

Usage:
  smoke.sh [options]

Options:
  --scene NAME      render only this scene (directory name under shells/)
  --seconds N       headless session length in seconds (default: 8)
  --out DIR         artifact base dir (default: files/pleamar/tests/shots;
                    output lands in DIR/<YYYY-MM-DD>/<scene>.png + .log)
  --require-render  fail (exit 2) when no renderer is available; without it
                    the compile matrix runs and rendering is skipped
  --min-bytes N     minimum PNG size treated as non-empty (default: 1024)
  --live            keep the ambient XDG dirs instead of a /tmp sandbox
                    (rendering stays headless; no surface opens in your session)
  --keep-tmp        keep the per-run temp dir for debugging
  --soft            software Vulkan: export VK_ICD_FILENAMES=<lavapipe>
                    (default /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json)
                    unless VK_ICD_FILENAMES is already set; not the default
  -h, --help        this text

Environment:
  PLEAMAR_BIN       pleamar binary (default: pleamar from PATH)
  PLEAMAR_WM_BIN    pleamar-wm binary (default: pleamar-wm from PATH)
  PLEAMAR_HEADLESS_INPUT   synthetic input script, passed through to pleamar-wm
  PLEAMAR_SOFT_ICD  ICD used by --soft
  VK_ICD_FILENAMES  honoured when already set; --soft never overrides it

Exit status:
  0  every scene compiled, and rendered when a renderer was available
  1  a scene failed to compile or render
  2  bad usage, or pleamar is not available
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
    warn "using the ambient environment (--live); rendering stays headless"
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

collect_scenes() {
  local file=""
  local name=""
  SCENES=()
  for file in "$PROJECT_DIR"/shells/*/*.plm; do
    if [ ! -f "$file" ]; then
      continue
    fi
    if is_part_file "$file"; then
      say "skipping part file: ${file#"$PROJECT_DIR"/}"
      continue
    fi
    name="$(basename -- "$file" .plm)"
    if [ -n "$SCENE_FILTER" ] && [ "$name" != "$SCENE_FILTER" ]; then
      continue
    fi
    SCENES+=("$name:$file")
  done
}

list_sockets() {
  local f=""
  for f in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
    if [ -S "$f" ]; then
      basename -- "$f"
    fi
  done
}

wait_for_new_socket() {
  local before=$1
  local after="$TEMPROOT/sockets.after"
  local wd=""
  local i=0
  while [ "$i" -lt 200 ]; do
    list_sockets > "$after" 2> /dev/null || true
    wd="$(grep -vxF -f "$before" "$after" 2> /dev/null | head -n 1 || true)"
    if [ -n "$wd" ]; then
      printf '%s\n' "$wd"
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_scene_socket() {
  local name=$1
  local limit=$2
  local i=0
  while [ "$i" -lt $((limit * 4)) ]; do
    if "$PLEAMAR" --say "$name" describe > /dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
    i=$((i + 1))
  done
  return 1
}

verify_png() {
  local png=$1
  local min=$2
  local size=""
  local magic=""
  if [ ! -f "$png" ]; then
    printf 'no PNG written'
    return 1
  fi
  size="$(wc -c < "$png" | tr -d ' ')"
  magic="$(LC_ALL=C od -An -tx1 -N 8 -- "$png" 2> /dev/null | tr -d ' \n' || true)"
  if [ "$size" -lt "$min" ]; then
    printf 'PNG too small (%sB < %sB)' "$size" "$min"
    return 1
  fi
  if [ "$magic" != "89504e470d0a1a0a" ]; then
    printf 'not a PNG (bad magic)'
    return 1
  fi
  printf '%sB' "$size"
  return 0
}

# ---- renderers --------------------------------------------------------------

detect_renderer() {
  PLEAMAR_WM="$(resolve_bin "$PLEAMAR_WM_BIN" || true)"
  GRIM="$(resolve_bin grim || true)"
  RENDERER=""
  RENDERER_BIN=""
  if [ -n "$PLEAMAR_WM" ]; then
    RENDERER="pleamar-wm"
    RENDERER_BIN="$PLEAMAR_WM"
    return 0
  fi
  if [ -n "$GRIM" ]; then
    local candidate=""
    local path=""
    for candidate in sway cage; do
      path="$(resolve_bin "$candidate" || true)"
      if [ -n "$path" ]; then
        RENDERER="$candidate"
        RENDERER_BIN="$path"
        return 0
      fi
    done
  fi
  return 1
}

render_with_wm() {
  local name=$1
  local file=$2
  local png=$3
  local log=$4
  local sec=$5
  local at=$6
  local autostart="$TEMPROOT/autostart"
  local rc=0
  printf '%s --scene %s --no-hud\n' "$PLEAMAR" "$file" > "$autostart"
  say "rendering $name with pleamar-wm headless (${sec}s, shot at ${at}s)"
  PLEAMAR_WM_AUTOSTART="$autostart" \
    PLEAMAR_HEADLESS_AT="$at" \
    PLEAMAR_HEADLESS_PNG="$png" \
    timeout -k 5 "$((sec + 40))" "$PLEAMAR_WM" headless --seconds "$sec" \
    > "$log" 2>&1 || rc=$?
  return "$rc"
}

render_with_wlroots() {
  local name=$1
  local file=$2
  local png=$3
  local log=$4
  local sec=$5
  local at=$6
  local before="$TEMPROOT/sockets.before"
  local wd=""
  local comp_pid=0
  local plm_pid=0
  local rc=0
  list_sockets > "$before" 2> /dev/null || true
  say "rendering $name with headless $RENDERER (${sec}s, shot after ${at}s)"
  if [ "$RENDERER" = "cage" ]; then
    WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 \
      setsid timeout -k 5 "$((sec + 40))" "$RENDERER_BIN" -- \
      "$PLEAMAR" --scene "$file" --no-hud --seconds "$sec" >> "$log" 2>&1 &
    comp_pid=$!
    STARTED_PIDS+=("$comp_pid")
  else
    WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 \
      setsid "$RENDERER_BIN" -c /dev/null >> "$log" 2>&1 &
    comp_pid=$!
    STARTED_PIDS+=("$comp_pid")
  fi
  if ! wd="$(wait_for_new_socket "$before")"; then
    printf 'smoke: %s did not create a Wayland socket; see %s\n' "$RENDERER" "$log" >&2
    return 1
  fi
  if [ "$RENDERER" != "cage" ]; then
    WAYLAND_DISPLAY="$wd" "$PLEAMAR" --scene "$file" --no-hud --seconds "$sec" \
      >> "$log" 2>&1 &
    plm_pid=$!
  fi
  if ! wait_for_scene_socket "$name" "$at"; then
    printf 'smoke: scene %s did not answer describe within %ss\n' "$name" "$at" >> "$log"
  fi
  sleep 1
  WAYLAND_DISPLAY="$wd" timeout 15 "$GRIM" "$png" >> "$log" 2>&1 || true
  if [ "$RENDERER" = "cage" ]; then
    wait "$comp_pid" || rc=$?
  else
    wait "$plm_pid" || rc=$?
    terminate "$comp_pid"
  fi
  return "$rc"
}

# ---- main -------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)
      SCENE_FILTER="${2:?--scene needs a scene name}"
      shift 2
      ;;
    --seconds)
      SECONDS_TO_RUN="${2:?--seconds needs a number}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:?--out needs a directory}"
      shift 2
      ;;
    --min-bytes)
      MIN_PNG_BYTES="${2:?--min-bytes needs a number}"
      shift 2
      ;;
    --require-render)
      REQUIRE_RENDER=1
      shift
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
    *)
      die "unknown argument: $1 (try --help)"
      ;;
  esac
done

require_uint "$SECONDS_TO_RUN" "--seconds"
require_uint "$MIN_PNG_BYTES" "--min-bytes"
if [ "$SECONDS_TO_RUN" -lt 2 ]; then
  die "--seconds must be at least 2 for a shot to fit in the session"
fi
AT_SECONDS_N=$((SECONDS_TO_RUN - 2))
if [ "$AT_SECONDS_N" -gt 4 ]; then
  AT_SECONDS_N=4
fi
if [ "$AT_SECONDS_N" -lt 1 ]; then
  AT_SECONDS_N=1
fi

PLEAMAR="$(resolve_bin "$PLEAMAR_BIN" || true)"
if [ -z "$PLEAMAR" ]; then
  die "pleamar not found (PLEAMAR_BIN='$PLEAMAR_BIN'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar"
fi

setup_env
apply_soft
collect_scenes

if [ "${#SCENES[@]}" -eq 0 ]; then
  if [ -n "$SCENE_FILTER" ]; then
    die "no scene named '$SCENE_FILTER' under $PROJECT_DIR/shells (expected shells/<scene>/<scene>.plm)"
  fi
  die "no scenes found under $PROJECT_DIR/shells/*/*.plm; nothing to smoke"
fi

if ! detect_renderer; then
  if [ "$REQUIRE_RENDER" -eq 1 ]; then
    die "no renderer available: tried pleamar-wm (PLEAMAR_WM_BIN='$PLEAMAR_WM_BIN') and headless 'sway'/'cage' with 'grim'; install pleamar-wm (or a nested compositor plus grim), or drop --require-render to run the compile matrix only"
  fi
  warn "no renderer available: tried pleamar-wm (PLEAMAR_WM_BIN='$PLEAMAR_WM_BIN') and headless 'sway'/'cage' with 'grim'; rendering is skipped (pass --require-render to make this fatal)"
fi

SHOT_DIR="$OUT_DIR/$(date +%Y-%m-%d)"
if [ -n "$RENDERER" ]; then
  mkdir -p -- "$SHOT_DIR"
fi

NAMES=()
CHECK_STATES=()
RENDER_STATES=()
PNG_SIZES=()
NOTES=()
FAILED=0
RENDER_OK=0

for entry in "${SCENES[@]}"; do
  name="${entry%%:*}"
  file="${entry#*:}"
  check_state="skip"
  render_state="skip"
  png_size="-"
  note=""
  check_out=""
  NAMES+=("$name")
  if check_out="$("$PLEAMAR" --check "$file" 2>&1)"; then
    check_state="ok"
    note="$(printf '%s' "$check_out" | head -n 1)"
  else
    check_state="FAIL"
    note="$(printf '%s' "$check_out" | head -n 1)"
    FAILED=1
  fi
  if [ -n "$RENDERER" ] && [ "$check_state" = "ok" ]; then
    png="$SHOT_DIR/$name.png"
    log="$SHOT_DIR/$name.log"
    rc=0
    # Never let a stale artifact from an earlier run satisfy the assertion.
    rm -f -- "$png"
    : > "$log"
    if [ "$RENDERER" = "pleamar-wm" ]; then
      render_with_wm "$name" "$file" "$png" "$log" "$SECONDS_TO_RUN" "$AT_SECONDS_N" || rc=$?
    else
      render_with_wlroots "$name" "$file" "$png" "$log" "$SECONDS_TO_RUN" "$AT_SECONDS_N" || rc=$?
    fi
    if png_note="$(verify_png "$png" "$MIN_PNG_BYTES")"; then
      png_size="$png_note"
      if [ "$rc" -ne 0 ]; then
        render_state="FAIL(exit $rc)"
        FAILED=1
      else
        render_state="ok"
        RENDER_OK=$((RENDER_OK + 1))
      fi
    else
      render_state="FAIL"
      note="$(printf '%s (exit %s)' "$png_note" "$rc")"
      FAILED=1
    fi
  elif [ "$check_state" = "ok" ]; then
    render_state="no-renderer"
  else
    render_state="skip(check)"
  fi
  CHECK_STATES+=("$check_state")
  RENDER_STATES+=("$render_state")
  PNG_SIZES+=("$png_size")
  NOTES+=("${note:0:72}")
done

WIDTH=6
for name in "${NAMES[@]}"; do
  if [ "${#name}" -gt "$WIDTH" ]; then
    WIDTH="${#name}"
  fi
done

printf '\n'
printf '%-*s  %-6s  %-13s  %-10s  %s\n' "$WIDTH" "SCENE" "CHECK" "RENDER" "PNG" "NOTE"
i=0
while [ "$i" -lt "${#NAMES[@]}" ]; do
  printf '%-*s  %-6s  %-13s  %-10s  %s\n' "$WIDTH" "${NAMES[$i]}" \
    "${CHECK_STATES[$i]}" "${RENDER_STATES[$i]}" "${PNG_SIZES[$i]}" "${NOTES[$i]}"
  i=$((i + 1))
done
printf '\n'

if [ -n "$RENDERER" ]; then
  say "renderer: $RENDERER ($RENDERER_BIN); artifacts in $SHOT_DIR"
else
  say "renderer: none"
fi

if [ "$REQUIRE_RENDER" -eq 1 ] && [ -z "$RENDERER" ]; then
  fail_msg="--require-render was given but no renderer is available: tried pleamar-wm (PLEAMAR_WM_BIN='$PLEAMAR_WM_BIN') and headless 'sway'/'cage' with 'grim'"
  printf 'smoke: error: %s\n' "$fail_msg" >&2
  exit 2
fi

if [ "$FAILED" -ne 0 ]; then
  say "FAILED: ${#NAMES[@]} scene(s) checked, ${RENDER_OK} rendered ok"
  exit 1
fi

say "ok: ${#NAMES[@]} scene(s) checked, ${RENDER_OK} rendered"
exit 0
