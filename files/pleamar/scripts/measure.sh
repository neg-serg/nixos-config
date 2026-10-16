#!/usr/bin/env bash
# measure.sh - run one scene for N seconds and collect a budget table.
#
# Starts one scene without touching the live session (pleamar-wm headless when
# available; --live runs it in the current session instead), samples the
# scene process with `ps` and /proc (instantaneous CPU from utime+stime
# deltas, RSS, threads, PSS), optionally samples the cgroup of a systemd unit
# given with --unit, and runs `pleamar --report` for the same window. The
# samples land in tests/evidence/<date>-<scene>.tsv, the report in
# tests/evidence/<date>-<scene>.md.
#
# Usage: measure.sh [--scene NAME] [--seconds N] [--interval N] [--unit NAME]
#                   [--out DIR] [--live] [--keep-tmp] [SCENE]
# Environment: PLEAMAR_BIN (default: pleamar), PLEAMAR_WM_BIN (default:
# pleamar-wm).
#
# Exit: 0 measured, 1 the scene died or the report failed, 2 usage or
# missing-tool error.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOOL_NAME="measure"

# ---- defaults ---------------------------------------------------------------

SECONDS_TO_RUN=20
INTERVAL=1
UNIT=""
LIVE=0
KEEP_TMP=0
SOFT=0
OUT_DIR="$PROJECT_DIR/tests/evidence"
SCENE_ARG=""

PLEAMAR_BIN="${PLEAMAR_BIN:-pleamar}"
PLEAMAR_WM_BIN="${PLEAMAR_WM_BIN:-pleamar-wm}"
SOFT_ICD="${PLEAMAR_SOFT_ICD:-/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json}"

TEMPROOT=""
STARTED_PIDS=()

PLEAMAR=""
PLEAMAR_WM=""
RUNNER_PID=""
SCENE_NAME=""
SCENE_FILE=""
SCENE_PID=""
SCENE_LOG=""
CG_PATH=""
REPORT_PID=""
PREV_CPU=""
PREV_TIME=""
PREV_CG_CPU=""
HZ=""

# ---- output helpers ---------------------------------------------------------

say() { printf 'measure: %s\n' "$*"; }
warn() { printf 'measure: warning: %s\n' "$*" >&2; }
fail() {
  printf 'measure: error: %s\n' "$*" >&2
  exit 1
}
die() {
  printf 'measure: error: %s\n' "$*" >&2
  exit 2
}

usage() {
  cat << 'EOF'
measure.sh - run one scene for N seconds and collect a budget table

Starts one scene without touching the live session (pleamar-wm headless when
available; --live runs it in the current session instead) and collects:
  - per-second `ps`/proc samples of the scene process (RSS, CPU, threads, PSS)
  - cgroup memory/CPU when --unit names the systemd unit running it
  - `pleamar --report` output for the same window

Usage:
  measure.sh [options] [SCENE]

  SCENE may be a scene name (shells/<name>/<name>.plm) or a path to a .plm
  file. With no SCENE and exactly one scene in the tree, that one is used.

Options:
  --scene NAME      same as the positional SCENE
  --seconds N       how long to measure (default: 20)
  --interval N      seconds between samples (default: 1)
  --unit NAME       measure an already-running systemd unit (user or system):
                    its MainPID is sampled and its cgroup read; the scene is
                    not started and is not stopped. Reaches the unit's session,
                    so it uses the ambient environment.
  --out DIR         artifact base dir (default: files/pleamar/tests/evidence;
                    output lands in DIR/<YYYY-MM-DD>-<scene>.tsv/.md/.log)
  --live            use the ambient environment and start the scene in the
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
  0  the table and the report were written
  1  the scene died during measurement or `pleamar --report` failed
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
  if [ -n "$REPORT_PID" ]; then
    terminate "$REPORT_PID"
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

wait_for_socket() {
  local name=$1
  local limit=$2
  local i=0
  while [ "$i" -lt $((limit * 4)) ]; do
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

show_log_tail() {
  printf 'measure: last lines of %s:\n' "$SCENE_LOG" >&2
  tail -n 15 -- "$SCENE_LOG" >&2 2> /dev/null || true
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

resolve_scene_pid() {
  local name=$1
  local out=""
  local pid=""
  local child=""
  out="$("$PLEAMAR" --say "$name" hello 2> /dev/null || true)"
  pid="$(printf '%s\n' "$out" | sed -n 's/.*pid \([0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [ -n "$pid" ]; then
    printf '%s\n' "$pid"
    return 0
  fi
  if [ -n "$RUNNER_PID" ]; then
    while IFS= read -r child; do
      if [ -z "$child" ]; then
        continue
      fi
      if tr '\0' ' ' < "/proc/$child/cmdline" 2> /dev/null | grep -q -- '--scene'; then
        printf '%s\n' "$child"
        return 0
      fi
    done < <(pgrep -P "$RUNNER_PID" 2> /dev/null || true)
  fi
  return 1
}

unit_pid_and_cgroup() {
  local unit=$1
  local pid=""
  local cg=""
  pid="$(systemctl --user show -p MainPID --value "$unit" 2> /dev/null || true)"
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then
    pid="$(systemctl show -p MainPID --value "$unit" 2> /dev/null || true)"
  fi
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then
    return 1
  fi
  cg="$(systemctl --user show -p ControlGroup --value "$unit" 2> /dev/null || true)"
  if [ -z "$cg" ]; then
    cg="$(systemctl show -p ControlGroup --value "$unit" 2> /dev/null || true)"
  fi
  SCENE_PID="$pid"
  CG_PATH=""
  if [ -n "$cg" ]; then
    CG_PATH="/sys/fs/cgroup$cg"
    if [ ! -d "$CG_PATH" ]; then
      warn "cgroup directory $CG_PATH does not exist; cgroup columns will be empty"
      CG_PATH=""
    fi
  else
    warn "no cgroup found for unit '$unit'; cgroup columns will be empty"
  fi
  return 0
}

sample_row() {
  local pid=$1
  local t=$2
  local ps_line=""
  local rss="-"
  local pcpu="-"
  local nlwp="-"
  local pss="-"
  local cpu_now=""
  local cpu_pct="-"
  local now=""
  local cg_mem="-"
  local cg_peak="-"
  local cg_cpu=""
  local cg_pct="-"
  ps_line="$(ps -o rss= -o pcpu= -o nlwp= -p "$pid" 2> /dev/null | head -n 1 || true)"
  if [ -n "$ps_line" ]; then
    rss="$(printf '%s\n' "$ps_line" | awk '{print $1}')"
    pcpu="$(printf '%s\n' "$ps_line" | awk '{print $2}')"
    nlwp="$(printf '%s\n' "$ps_line" | awk '{print $3}')"
  fi
  cpu_now="$(awk '{print $14 + $15}' "/proc/$pid/stat" 2> /dev/null || true)"
  now="$(date +%s.%N)"
  if [ -n "$cpu_now" ] && [ -n "$PREV_CPU" ]; then
    cpu_pct="$(awk -v c1="$cpu_now" -v c0="$PREV_CPU" -v hz="$HZ" \
      -v t1="$now" -v t0="$PREV_TIME" \
      'BEGIN { d = t1 - t0; if (d > 0) printf "%.2f", (c1 - c0) / hz / d * 100; else printf "-" }')"
  fi
  pss="$(awk '/^Pss:/ { s += $2 } END { print s + 0 }' "/proc/$pid/smaps_rollup" 2> /dev/null || true)"
  if [ -z "$pss" ]; then
    pss="-"
  fi
  if [ -n "$CG_PATH" ]; then
    cg_mem="$(cat "$CG_PATH/memory.current" 2> /dev/null || true)"
    cg_peak="$(cat "$CG_PATH/memory.peak" 2> /dev/null || true)"
    cg_cpu="$(awk '/^usage_usec/ { print $2 }' "$CG_PATH/cpu.stat" 2> /dev/null || true)"
    if [ -z "$cg_mem" ]; then
      cg_mem="-"
    fi
    if [ -z "$cg_peak" ]; then
      cg_peak="-"
    fi
    if [ -n "$cg_cpu" ] && [ -n "$PREV_CG_CPU" ]; then
      cg_pct="$(awk -v c1="$cg_cpu" -v c0="$PREV_CG_CPU" \
        -v t1="$now" -v t0="$PREV_TIME" \
        'BEGIN { d = t1 - t0; if (d > 0) printf "%.2f", (c1 - c0) / 10000 / d; else printf "-" }')"
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$t" "$pid" "$rss" "$pcpu" "$cpu_pct" "$nlwp" "$pss" \
    "$cg_mem" "$cg_peak" "$cg_cpu" "$cg_pct"
  PREV_CPU="$cpu_now"
  PREV_TIME="$now"
  if [ -n "$cg_cpu" ]; then
    PREV_CG_CPU="$cg_cpu"
  fi
}

print_table() {
  local tsv=$1
  if command -v column > /dev/null 2>&1; then
    column -t -s "$(printf '\t')" "$tsv"
  else
    cat -- "$tsv"
  fi
}

# ---- main -------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)
      if [ -n "$SCENE_ARG" ]; then
        die "more than one scene given"
      fi
      SCENE_ARG="${2:?--scene needs a scene name}"
      shift 2
      ;;
    --seconds)
      SECONDS_TO_RUN="${2:?--seconds needs a number}"
      shift 2
      ;;
    --interval)
      INTERVAL="${2:?--interval needs a number}"
      shift 2
      ;;
    --unit)
      UNIT="${2:?--unit needs a unit name}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:?--out needs a directory}"
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

require_uint "$SECONDS_TO_RUN" "--seconds"
require_uint "$INTERVAL" "--interval"

PLEAMAR="$(resolve_bin "$PLEAMAR_BIN" || true)"
if [ -z "$PLEAMAR" ]; then
  die "pleamar not found (PLEAMAR_BIN='$PLEAMAR_BIN'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar"
fi
PLEAMAR_WM="$(resolve_bin "$PLEAMAR_WM_BIN" || true)"
HZ="$(getconf CLK_TCK 2> /dev/null || printf '100')"
apply_soft

if ! resolve_scene "$SCENE_ARG"; then
  die "cannot resolve the scene (pass a name like 'proof' or a .plm path)"
fi

if [ -n "$UNIT" ]; then
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    die "--unit needs XDG_RUNTIME_DIR (the unit's session) to reach pleamar --say"
  fi
  warn "measuring unit '$UNIT' in the ambient session; the scene is not started or stopped"
  if ! unit_pid_and_cgroup "$UNIT"; then
    die "unit '$UNIT' is not running (no MainPID)"
  fi
else
  setup_env
  if ! start_runner "$SCENE_FILE" "$((SECONDS_TO_RUN + 30))"; then
    die "no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='$PLEAMAR_WM_BIN'); pass --live to start the scene in the current session, or --unit to measure a running unit"
  fi
  wait_rc=0
  wait_for_socket "$SCENE_NAME" "$((SECONDS_TO_RUN + 15))" || wait_rc=$?
  if [ "$wait_rc" -eq 2 ]; then
    show_log_tail
    die "the runner exited before scene '$SCENE_NAME' answered (see log above; --keep-tmp keeps the sandbox)"
  fi
  if [ "$wait_rc" -ne 0 ]; then
    show_log_tail
    die "scene '$SCENE_NAME' did not answer within $((SECONDS_TO_RUN + 15))s (see log above; --keep-tmp keeps the sandbox)"
  fi
  SCENE_PID="$(resolve_scene_pid "$SCENE_NAME" || true)"
  if [ -z "$SCENE_PID" ]; then
    stop_scene
    die "could not resolve the pid of scene '$SCENE_NAME' (tried $(hello) and the runner's children)"
  fi
fi

mkdir -p -- "$OUT_DIR"
STAMP="$(date +%Y-%m-%d)"
TSV="$OUT_DIR/$STAMP-$SCENE_NAME.tsv"
MD="$OUT_DIR/$STAMP-$SCENE_NAME.md"
LOG="$OUT_DIR/$STAMP-$SCENE_NAME.log"
: > "$LOG"

printf 't_s\tpid\trss_kb\tps_cpu_pct\tcpu_pct\tthreads\tpss_kb\tcg_mem_bytes\tcg_mem_peak_bytes\tcg_cpu_usec\tcg_cpu_pct\n' > "$TSV"

say "measuring scene '$SCENE_NAME' (pid $SCENE_PID) for ${SECONDS_TO_RUN}s, every ${INTERVAL}s"
"$PLEAMAR" --report "$SCENE_NAME" --seconds "$SECONDS_TO_RUN" --out "$MD" >> "$LOG" 2>&1 &
REPORT_PID=$!

i=0
SCENE_DIED=0
while [ "$i" -le "$SECONDS_TO_RUN" ]; do
  if ! kill -0 "$SCENE_PID" 2> /dev/null; then
    SCENE_DIED=1
    break
  fi
  sample_row "$SCENE_PID" "$((i * INTERVAL))" >> "$TSV"
  i=$((i + 1))
  if [ "$i" -le "$SECONDS_TO_RUN" ]; then
    sleep "$INTERVAL"
  fi
done

report_rc=0
wait "$REPORT_PID" || report_rc=$?
REPORT_PID=""

if [ -z "$UNIT" ]; then
  stop_scene
fi

say "tsv: $TSV"
say "md:  $MD"
say "log: $LOG"
printf '\n'
print_table "$TSV"
printf '\n'
if [ -f "$MD" ]; then
  say "report: $(head -n 1 -- "$MD")"
fi

SAMPLES=$(($(wc -l < "$TSV") - 1))

if [ "$SCENE_DIED" -ne 0 ]; then
  fail "scene process $SCENE_PID exited during measurement (${SAMPLES} samples written to $TSV)"
fi
if [ "$report_rc" -ne 0 ]; then
  fail "pleamar --report failed (exit $report_rc; see $LOG)"
fi
say "ok: ${SAMPLES} samples in $TSV"
exit 0
