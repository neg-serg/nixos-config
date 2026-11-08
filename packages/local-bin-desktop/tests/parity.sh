#!/usr/bin/env bash
# Parity harness: run the shipped shell scripts and the Rust ports side by side
# against the same fake external tools, then compare every observable: exit
# code, stdout, stderr, the fake tools' argv log, clipboard/notification
# payloads, IPC arguments and the files both sides write.
#
#   tests/parity.sh [--bin-dir DIR] [--tool NAME] [--list] [--verbose]
#
# Env:
#   LOCAL_BIN_DESKTOP_BIN   directory with the released binaries (default:
#                           ${CARGO_TARGET_DIR:-target}/debug)
#   PARITY_SYSTEM_BIN       directory with the real coreutils/jq/rg (default:
#                           /run/current-system/sw/bin)
#
# The fakes are /bin/sh scripts first on PATH; HOME, TMPDIR, XDG_RUNTIME_DIR and
# every fake's state file live in a temporary tree. The original scripts run
# unmodified from packages/local-bin/bin. Pure-text filters the ports moved
# in-process (sed, awk, jq, stat, sort, find, base64) are the real host tools for
# the shell side and native code for the Rust side; they are not compared as tool
# calls, only through their effect.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
ORIGINALS=${PARITY_ORIGINALS:-$REPO/packages/local-bin/bin}
# When the shell originals have already been deleted (the usual end state), the
# harness restores the copies it needs from git into the temporary tree.
ORIGINAL_RUN=$ORIGINALS
SYSTEM_BIN=${PARITY_SYSTEM_BIN:-/run/current-system/sw/bin}
BIN_DIR=${LOCAL_BIN_DESKTOP_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug}

TOOL_FILTER=
VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)
      BIN_DIR=$2
      shift 2
      ;;
    --tool)
      TOOL_FILTER=$2
      shift 2
      ;;
    --list)
      printf '%s\n' pic-notify screenrec clip screenshot-toast pic-info \
        pic-dirs-list wl-restore unlock kitty-font-zoom cursor-stretch pngoptim \
        hypr-resize-proportional
      exit 0
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    *)
      printf 'parity: unknown argument %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/local-bin-desktop-parity.XXXXXX")
cleanup() {
  cleanup_case_processes
  rm -rf -- "$WORK"
}
trap cleanup EXIT

FAKE_BIN=$WORK/bin
HOME_DIR=$WORK/home
TMP_DIR=$WORK/tmp
RUN_DIR=$WORK/run
CASE_DIR=$WORK/case
TEST_USER="parity$$"
PIDFILE=/tmp/wf-recorder-$TEST_USER.pid
FAKE_LOG=$WORK/fake.log
FAKE_CLIP_FILE=$WORK/clip.bin
FAKE_NOTIFY_FILE=$WORK/notify.bin
FAKE_DISPATCH_FILE=$WORK/dispatch.bin
FAKE_EVAL_FILE=$WORK/eval.txt
FAKE_EXPECT_STDIN=$WORK/expect.stdin
FAKE_VICINAE_STDIN=$WORK/vicinae.stdin
FAKE_WL_LOG=$WORK/wl.log
FAKE_YTDLP_STATE=$WORK/ytdlp.state
FAKE_WFREC_PIDFILE=$WORK/wfrec.pid
FAKE_INOTIFY_LINES=$WORK/inotify.txt
FAKE_WL_COUNTER=$WORK/wl.counter
FAKE_BC_LOG=$WORK/bc.log
FAKE_MKTEMP_OUT=$TMP_DIR/capture.png

export HOME_DIR TMP_DIR RUN_DIR CASE_DIR TEST_USER PIDFILE FAKE_BIN
export FAKE_LOG FAKE_CLIP_FILE FAKE_NOTIFY_FILE FAKE_DISPATCH_FILE
export FAKE_EVAL_FILE FAKE_EXPECT_STDIN FAKE_VICINAE_STDIN FAKE_WL_LOG
export FAKE_YTDLP_STATE FAKE_WFREC_PIDFILE FAKE_INOTIFY_LINES FAKE_WL_COUNTER
export FAKE_MKTEMP_OUT FAKE_BC_LOG SYSTEM_BIN

BASE_ENV=(
  "PATH=$FAKE_BIN:$SYSTEM_BIN"
  "HOME=$HOME_DIR"
  "TMPDIR=$TMP_DIR"
  "XDG_RUNTIME_DIR=$RUN_DIR"
  "USER=$TEST_USER"
  "LANG=C.UTF-8"
  "LC_ALL=C.UTF-8"
  "FAKE_LOG=$FAKE_LOG"
  "FAKE_CLIP_FILE=$FAKE_CLIP_FILE"
  "FAKE_NOTIFY_FILE=$FAKE_NOTIFY_FILE"
  "FAKE_DISPATCH_FILE=$FAKE_DISPATCH_FILE"
  "FAKE_EVAL_FILE=$FAKE_EVAL_FILE"
  "FAKE_EXPECT_STDIN=$FAKE_EXPECT_STDIN"
  "FAKE_VICINAE_STDIN=$FAKE_VICINAE_STDIN"
  "FAKE_WL_LOG=$FAKE_WL_LOG"
  "FAKE_YTDLP_STATE=$FAKE_YTDLP_STATE"
  "FAKE_WFREC_PIDFILE=$FAKE_WFREC_PIDFILE"
  "FAKE_INOTIFY_LINES=$FAKE_INOTIFY_LINES"
  "FAKE_WL_COUNTER=$FAKE_WL_COUNTER"
  "FAKE_MKTEMP_OUT=$FAKE_MKTEMP_OUT"
  "FAKE_BC_LOG=$FAKE_BC_LOG"
  "FAKE_SLEEP_BIN=$SYSTEM_BIN/sleep"
  "FAKE_ACTIVEWINDOW={\"pid\":4242,\"size\":[800,600],\"floating\":true,\"x\":10,\"y\":20,\"width\":2560,\"height\":1440,\"scale\":1}"
  "FAKE_MONITORS=[{\"name\":\"DP-1\",\"focused\":true,\"x\":0,\"y\":0,\"width\":2560,\"height\":1440,\"scale\":1}]"
  "FAKE_GETOPTION={\"bool\":true}"
)
CASE_ENV=()
TOOL=

CHECKS=0
FAILED=0
NORMALIZED=0

mkfake() {
  local name=$1
  shift
  {
    echo '#!/bin/sh'
    echo "if [ -n \"\${FAKE_LOG:-}\" ]; then"
    echo "  printf '%s\\036' '$name' \"\$@\" >> \"\$FAKE_LOG\"; printf '\\036' >> \"\$FAKE_LOG\""
    echo 'fi'
    cat
  } > "$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
}

setup_fakes() {
  mkdir -p "$FAKE_BIN"
  : > "$FAKE_LOG"

  mkfake sleep << 'EOF'
if [ "${FAKE_SLEEP_REAL:-0}" = 1 ]; then
  exec "${FAKE_SLEEP_BIN:-sleep}" "$@"
fi
exit 0
EOF
  mkfake timeout << 'EOF'
shift
exec "$@"
EOF
  mkfake date << 'EOF'
printf '%s\n' "${FAKE_DATE_OUT:?}"
EOF
  mkfake identify << 'EOF'
printf '%s' "${FAKE_IDENTIFY_OUT-1920 1080 8 srgba 4.0}"
exit "${FAKE_IDENTIFY_EXIT-0}"
EOF
  mkfake wl-copy << 'EOF'
cat >> "${FAKE_CLIP_FILE:?}"
printf '\036' >> "${FAKE_CLIP_FILE:?}"
EOF
  mkfake wl-paste << 'EOF'
printf '%s' "${FAKE_WLPASTE-}"
exit "${FAKE_WLPASTE_EXIT-0}"
EOF
  mkfake notify-send << 'EOF'
printf '%s\036' "$@" >> "${FAKE_NOTIFY_FILE:?}"
printf '\036' >> "${FAKE_NOTIFY_FILE:?}"
exit "${FAKE_NOTIFY_EXIT-0}"
EOF
  mkfake pleamar << 'EOF'
exit "${FAKE_PLEAMAR_EXIT-1}"
EOF
  mkfake quickshell << 'EOF'
exit "${FAKE_QUICKSHELL_EXIT-1}"
EOF
  mkfake hyprctl << 'EOF'
case "$1" in
  activewindow)
    printf '%s' "${FAKE_ACTIVEWINDOW-}"
    exit "${FAKE_HYPRCTL_AW_EXIT-0}" ;;
  monitors)
    printf '%s' "${FAKE_MONITORS-}"
    exit "${FAKE_HYPRCTL_MON_EXIT-0}" ;;
  -j)
    case "$2" in
      getoption) printf '%s' "${FAKE_GETOPTION-}" ;;
      monitors) printf '%s' "${FAKE_MONITORS-}" ;;
    esac ;;
  eval)
    printf '%s' "$2" > "${FAKE_EVAL_FILE:-/dev/null}"
    exit "${FAKE_HYPRCTL_EVAL_EXIT-0}" ;;
  dispatch)
    printf '%s\036' "$@" >> "${FAKE_DISPATCH_FILE:?}"
    printf '\036' >> "${FAKE_DISPATCH_FILE:?}"
    exit "${FAKE_HYPRCTL_DISPATCH_EXIT-0}" ;;
esac
exit 0
EOF
  mkfake kitten << 'EOF'
case "$*" in
  *set-user-vars) printf '%s' "${FAKE_KITTEN_VARS-}" ;;
esac
exit 0
EOF
  mkfake oxipng << 'EOF'
exit "${FAKE_OXIPNG_EXIT-0}"
EOF
  mkfake magick << 'EOF'
printf '%s' "${FAKE_MAGICK_OUT-}"
exit "${FAKE_MAGICK_EXIT-0}"
EOF
  mkfake curl << 'EOF'
printf '%s' "${FAKE_CURL_OUT-}"
exit "${FAKE_CURL_EXIT-0}"
EOF
  mkfake grim << 'EOF'
: > "$3"
exit "${FAKE_GRIM_EXIT-0}"
EOF
  mkfake mktemp << 'EOF'
printf '%s' "${FAKE_MKTEMP_OUT:?}"
EOF
  mkfake systemctl << 'EOF'
exit "${FAKE_SYSTEMCTL_EXIT-0}"
EOF
  mkfake wl << 'EOF'
printf '%s\036' "$@" >> "${FAKE_WL_LOG:?}"
printf '\036' >> "${FAKE_WL_LOG:?}"
case "$1" in
  query)
    if [ -f "${FAKE_WL_COUNTER:-}" ]; then
      remaining=$(cat "$FAKE_WL_COUNTER")
      if [ "$remaining" -gt 0 ]; then
        echo $((remaining - 1)) > "$FAKE_WL_COUNTER"
        exit 1
      fi
    fi
    exit "${FAKE_WL_QUERY_EXIT-0}" ;;
  restore) exit "${FAKE_WL_RESTORE_EXIT-0}" ;;
esac
exit "$?"
EOF
  mkfake inotifywait << 'EOF'
cat "${FAKE_INOTIFY_LINES:-/dev/null}"
exit 0
EOF
  mkfake zoxide << 'EOF'
exit 0
EOF
  mkfake ssh-agent << 'EOF'
printf '%s\n' "SSH_AUTH_SOCK=${FAKE_SSH_SOCK:?}; export SSH_AUTH_SOCK;"
printf '%s\n' "SSH_AGENT_PID=${FAKE_SSH_PID:?}; export SSH_AGENT_PID;"
printf '%s\n' "echo Agent pid ${FAKE_SSH_PID};"
EOF
  mkfake pass << 'EOF'
case "$2" in
  ssh-key) printf '%s\n' "${FAKE_PASS_KEY-}"
    exit "${FAKE_PASS_KEY_EXIT-0}" ;;
  wrk/ssh-key) printf '%s\n' "${FAKE_PASS_WRK_KEY-}"
    exit "${FAKE_PASS_WRK_EXIT-1}" ;;
esac
exit 1
EOF
  mkfake expect << 'EOF'
cat > "${FAKE_EXPECT_STDIN:?}"
printf 'expect-ran\n'
exit "${FAKE_EXPECT_EXIT-0}"
EOF
  mkfake bc << 'EOF'
expression=$(cat)
if [ -n "${FAKE_BC_LOG:-}" ]; then
  printf '%s\037' "$expression" >> "$FAKE_BC_LOG"
fi
if [ "${FAKE_BC_FLOAT:-0}" = 1 ]; then
  case "$expression" in
    "1.0 + +10 / 100.0") printf '%s\n' "1.100000"; exit 0 ;;
  esac
fi
case "$expression" in
  "1.0 + +10 / 100.0") printf '%s\n' "1.1" ;;
  "1.0 + -10 / 100.0") printf '%s\n' "0.9" ;;
  "1.0 + 20 / 100.0") printf '%s\n' "1.2" ;;
  "1.0 + -99 / 100.0") printf '%s\n' "0.1" ;;
  "800 * 1.1 / 1") printf '%s\n' "880" ;;
  "600 * 1.1 / 1") printf '%s\n' "660" ;;
  "800 * 1.2 / 1") printf '%s\n' "960" ;;
  "800 * 0.9 / 1") printf '%s\n' "720" ;;
  "600 * 0.9 / 1") printf '%s\n' "540" ;;
  "800 * 0.1 / 1") printf '%s\n' "80" ;;
  "600 * 0.1 / 1") printf '%s\n' "60" ;;
  "800 * 1.100000 / 1") printf '%s\n' "880.000000" ;;
  "600 * 1.100000 / 1") printf '%s\n' "660.000000" ;;
  *) printf '1\n' ;;
esac
exit "${FAKE_BC_EXIT-0}"
EOF
  mkfake wf-recorder << 'EOF'
if [ "${1-}" = "-L" ]; then
  printf '%s' "${FAKE_WFREC_LIST-}"
  exit 0
fi
if [ -n "${FAKE_WFREC_PIDFILE:-}" ]; then
  printf '%s' $$ > "$FAKE_WFREC_PIDFILE"
fi
if [ "${FAKE_WFREC_DIE:-0}" = 1 ]; then
  exit 1
fi
kill -STOP $$
EOF
  mkfake slurp << 'EOF'
printf '%s\n' "${FAKE_SLURP_OUT-}"
exit "${FAKE_SLURP_EXIT-0}"
EOF
  mkfake vicinae << 'EOF'
cat > "${FAKE_VICINAE_STDIN:-/dev/null}"
printf '%s' "${FAKE_VICINAE_OUT-}"
exit "${FAKE_VICINAE_EXIT-0}"
EOF
  mkfake cliphist << 'EOF'
case "$1" in
  list) printf '%s' "${FAKE_CLIPHIST_LIST-}" ;;
  decode) printf '%s' "${FAKE_CLIPHIST_DECODE-}" ;;
esac
exit 0
EOF
  mkfake wtype << 'EOF'
exit 0
EOF
  mkfake yt-dlp << 'EOF'
printf '%s' "$PWD" > "${FAKE_YTDLP_STATE:?}"
exit 0
EOF
  mkfake negwm << 'EOF'
exit 0
EOF
  mkfake clipcat-menu << 'EOF'
exit 0
EOF
  mkfake pic-notify << 'EOF'
exit 0
EOF
  mkfake pic-info << 'EOF'
exit 0
EOF
}

# PATH with every fake and every system tool the scripts need except TOOL, for
# the missing-dependency cases. Appending SYSTEM_BIN would defeat the purpose
# (inotifywait, oxipng and notify-send all live there too).
path_without() {
  local tool=$1 shim=$WORK/no-$1
  rm -rf "$shim"
  mkdir -p "$shim"
  local entry name real
  for entry in "$FAKE_BIN"/*; do
    name=${entry##*/}
    [ "$name" = "$tool" ] || ln -s "$entry" "$shim/$name"
  done
  for name in sh bash env dirname cat find sed awk sort head tail cut tr od \
    grep rg xargs jq base64 install stat mkdir mv touch rm ln readlink; do
    [ "$name" = "$tool" ] && continue
    [ -e "$shim/$name" ] && continue
    real=$SYSTEM_BIN/$name
    [ -x "$real" ] && ln -s "$real" "$shim/$name"
  done
  printf '%s' "$shim"
}

set_env() {
  CASE_ENV=("$@")
}

cleanup_case_processes() {
  if [ -f "$FAKE_WFREC_PIDFILE" ]; then
    local pid
    pid=$(cat "$FAKE_WFREC_PIDFILE" 2> /dev/null || true)
    [ -n "${pid:-}" ] && kill -9 "$pid" 2> /dev/null
    rm -f "$FAKE_WFREC_PIDFILE"
  fi
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE" 2> /dev/null || true)
    [ -n "${pid:-}" ] && kill -9 "$pid" 2> /dev/null
    rm -f "$PIDFILE"
  fi
}

reset_world() {
  cleanup_case_processes
  rm -rf "$HOME_DIR" "$TMP_DIR" "$RUN_DIR" "$CASE_DIR"
  mkdir -p "$HOME_DIR" "$TMP_DIR" "$RUN_DIR" "$CASE_DIR"
  : > "$FAKE_LOG"
  : > "$FAKE_CLIP_FILE"
  : > "$FAKE_NOTIFY_FILE"
  : > "$FAKE_DISPATCH_FILE"
  : > "$FAKE_WL_LOG"
  : > "$FAKE_INOTIFY_LINES"
  : > "$FAKE_BC_LOG"
  : > "$FAKE_EXPECT_STDIN"
  : > "$FAKE_VICINAE_STDIN"
  : > "$FAKE_YTDLP_STATE"
  rm -f "$FAKE_EVAL_FILE" "$FAKE_WFREC_PIDFILE" "$PIDFILE" "$FAKE_WL_COUNTER"
  rm -f "$WORK/capture.png"
}

dump_file() {
  local path=$1
  [ -f "$path" ] || return 0
  printf -- '-- %s\n' "${path#"$WORK"/}"
  cat "$path"
  printf '\n'
}

dump_pid_content() {
  local path=$1
  [ -f "$path" ] || return 0
  local content
  content=$(cat "$path" 2> /dev/null || true)
  if printf '%s' "$content" | grep -qxE '[0-9]+'; then
    printf '<pid>\n'
  else
    printf '%s\n' "$content"
  fi
}

dump_tree() {
  local root=$1
  [ -d "$root" ] || return 0
  local entry
  while IFS= read -r entry; do
    printf -- '-- %s\n' "${entry#"$WORK"/}"
    if [ -f "$entry" ]; then
      case "$entry" in
        "$FAKE_WFREC_PIDFILE" | "$PIDFILE") dump_pid_content "$entry" ;;
        *)
          cat "$entry"
          printf '\n'
          ;;
      esac
    else
      printf '<dir>\n'
    fi
  done < <(find "$root" -mindepth 1 -print 2> /dev/null | sort)
}

dump_state() {
  local side=$1
  {
    printf '## exit\n'
    cat "$WORK/$side.exit"
    printf '## stdout\n'
    cat "$WORK/$side.out"
    printf '## stderr\n'
    cat "$WORK/$side.err"
    printf '## clip\n'
    tr '\036' '\n' < "$FAKE_CLIP_FILE"
    printf '## notify\n'
    tr '\036' '\n' < "$FAKE_NOTIFY_FILE"
    printf '## dispatch\n'
    tr '\036' '\n' < "$FAKE_DISPATCH_FILE"
    printf '## wl\n'
    tr '\036' '\n' < "$FAKE_WL_LOG"
    printf '## bc\n'
    tr '\037' '\n' < "$FAKE_BC_LOG"
    printf '## eval\n'
    dump_file "$FAKE_EVAL_FILE"
    printf '## expect\n'
    dump_file "$FAKE_EXPECT_STDIN"
    printf '## vicinae-in\n'
    dump_file "$FAKE_VICINAE_STDIN"
    printf '## ytdlp-cwd\n'
    dump_file "$FAKE_YTDLP_STATE"
    printf '## wfrec-pid\n'
    dump_pid_content "$FAKE_WFREC_PIDFILE"
    printf '## pidfile\n'
    dump_pid_content "$PIDFILE"
    printf '## home\n'
    dump_tree "$HOME_DIR"
    printf '## run\n'
    dump_tree "$RUN_DIR"
    printf '## tmp\n'
    dump_tree "$TMP_DIR"
    printf '## case\n'
    dump_tree "$CASE_DIR"
  } > "$WORK/$side.state"
  tr '\036' '\n' < "$FAKE_LOG" > "$WORK/$side.log"
}

normalize() {
  sed -E \
    -e "s|$ORIGINAL_RUN/$TOOL|PROG|g" \
    -e "s|$BIN_DIR/$TOOL|PROG|g" \
    -e "s|$FAKE_BIN|FAKEBIN|g" \
    -e "s|$WORK|WORK|g" \
    -e "s|$PIDFILE|PIDFILE|g"
}

run_side() {
  local side=$1 program=$2 setup=$3
  shift 3
  reset_world
  if [ -n "$setup" ]; then
    "$setup" "$side"
  fi
  (
    cd "$CASE_DIR" || exit 1
    env -i "${BASE_ENV[@]}" "${CASE_ENV[@]}" "$program" "$@"
  ) > "$WORK/$side.out" 2> "$WORK/$side.err"
  printf '%s\n' "$?" > "$WORK/$side.exit"
  dump_state "$side"
  cleanup_case_processes
}

compare() {
  local label=$1 setup=$2
  shift 2
  if [ -n "${CASE_FILTER:-}" ] && [[ $label != *"$CASE_FILTER"* ]]; then
    return 0
  fi
  if [ "${1-}" = "--" ]; then
    shift
  fi
  CHECKS=$((CHECKS + 1))
  run_side o "$ORIGINAL_RUN/$TOOL" "$setup" "$@"
  run_side r "$BIN_DIR/$TOOL" "$setup" "$@"
  local ok=1 detail="" normalized=0

  local state_diff
  if ! state_diff=$(diff -u <(normalize < "$WORK/o.state") <(normalize < "$WORK/r.state")); then
    ok=0
    detail+="  state:$'\n'$state_diff"$'\n'
  fi

  local log_diff
  if ! log_diff=$(diff -u <(normalize < "$WORK/o.log") <(normalize < "$WORK/r.log")); then
    # Pipeline members started together (cliphist | vicinae, hyprctl | jq)
    # race for the log; their argv multiset is the behaviour that matters.
    if diff -q <(normalize < "$WORK/o.log" | sort) <(normalize < "$WORK/r.log" | sort) > /dev/null; then
      normalized=1
    else
      ok=0
      detail+="  log:$'\n'$log_diff"$'\n'
      detail+=$(diff -u <(normalize < "$WORK/o.log" | sort) <(normalize < "$WORK/r.log" | sort))$'\n'
    fi
  fi

  if [ "$ok" = 1 ]; then
    if [ "$normalized" = 1 ]; then
      printf 'PASS  %s (tool-call order normalised)\n' "$label"
      NORMALIZED=$((NORMALIZED + 1))
    else
      printf 'PASS  %s\n' "$label"
    fi
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL  %s\n' "$label"
    printf '%s\n' "$detail" >&2
    if [ "$VERBOSE" = 1 ]; then
      printf '%s\n' "$detail"
    fi
  fi
}

resolve_originals() {
  ORIGINAL_RUN=$ORIGINALS
  [ -x "$ORIGINALS/$TOOL" ] && return 0
  ORIGINAL_RUN=$WORK/originals
  mkdir -p "$ORIGINAL_RUN"
  local relative=packages/local-bin/bin
  local source=HEAD
  if ! git -C "$REPO" cat-file -e "$source:$relative/$TOOL" 2> /dev/null; then
    # The deletion is already committed: take the version before the commit
    # that removed the file.
    local removal
    removal=$(git -C "$REPO" log --all --diff-filter=D --format=%H -1 -- "$relative/$TOOL")
    [ -n "$removal" ] || {
      printf 'parity: %s is gone and not recoverable from git\n' "$TOOL" >&2
      exit 2
    }
    source="$removal^"
  fi
  git -C "$REPO" show "$source:$relative/_localbin.sh" > "$ORIGINAL_RUN/_localbin.sh" 2> /dev/null || true
  git -C "$REPO" show "$source:$relative/$TOOL" > "$ORIGINAL_RUN/$TOOL" 2> /dev/null || {
    printf 'parity: cannot restore %s from %s\n' "$TOOL" "$source" >&2
    exit 2
  }
  chmod +x "$ORIGINAL_RUN/$TOOL"
}

require_binaries() {
  if [ ! -x "$BIN_DIR/$TOOL" ]; then
    printf 'parity: missing %s/%s (build the crate first)\n' "$BIN_DIR" "$TOOL" >&2
    exit 2
  fi
  resolve_originals
}

begin_tool() {
  TOOL=$1
  CASE_ENV=()
  require_binaries
}

tool_enabled() {
  [ -z "$TOOL_FILTER" ] || [ "$TOOL_FILTER" = "$1" ]
}

setup_fakes

# ── pic-notify ────────────────────────────────────────────────────────────────
pn_image() {
  printf 'PNGDATA' > "$CASE_DIR/shot.png"
  touch -d '@1767000000' "$CASE_DIR/shot.png"
}

pn_bmp_setup() {
  printf 'BMPDATA' > "$CASE_DIR/shot.bmp"
  touch -d '@1767000000' "$CASE_DIR/shot.bmp"
}

pn_image_timestamped() {
  printf 'PNGDATA' > "$CASE_DIR/shot-20260102-03.04.05.png"
  touch -d '@1767000000' "$CASE_DIR/shot-20260102-03.04.05.png"
}

if tool_enabled pic-notify; then
  begin_tool pic-notify
  set_env "FAKE_DATE_OUT=2026-01-02 03:04:05"
  compare "pic-notify: no argument prints the header and exits 1" ""
  compare "pic-notify: -h keeps exit 1" "" -- -h
  compare "pic-notify: --help keeps exit 1" "" -- --help

  set_env "FAKE_IDENTIFY_OUT=1920 1080 8 srgba 4.0" "FAKE_DATE_OUT=2026-01-02 03:04:05"
  compare "pic-notify: identify metadata, clipboard, both JSON events" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=640 480 8 RGB" "FAKE_PLEAMAR_EXIT=0"
  compare "pic-notify: answering IPC suppresses notify-send" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=640 480 16 graya 2.0" "FAKE_PLEAMAR_EXIT=1" "FAKE_QUICKSHELL_EXIT=1"
  compare "pic-notify: notify-send fallback body" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=1 1 8 1" "FAKE_PLEAMAR_EXIT=0"
  compare "pic-notify: channel count 1 is Gray" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=10 20 8 gray" "FAKE_PLEAMAR_EXIT=0"
  compare "pic-notify: channel name fallback (Gray)" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=" "FAKE_PLEAMAR_EXIT=0"
  compare "pic-notify: no identify still writes the event" pn_image -- "$CASE_DIR/shot.png"

  set_env "FAKE_IDENTIFY_OUT=1920 1080 8 srgba 4.0" "FAKE_PLEAMAR_EXIT=0"
  compare "pic-notify: timestamp from the file name" pn_image_timestamped -- "$CASE_DIR/shot-20260102-03.04.05.png"

  compare "pic-notify: .bmp is copied as .png" pn_bmp_setup -- "$CASE_DIR/shot.bmp"

  set_env "FAKE_IDENTIFY_OUT=1920 1080 8 srgba 4.0" "FAKE_PLEAMAR_EXIT=0" \
    "XDG_CACHE_HOME=$CASE_DIR/cache"
  compare "pic-notify: XDG_CACHE_HOME overrides the pleamar dir" pn_image \
    -- "$CASE_DIR/shot.png"
fi

# ── screenrec ─────────────────────────────────────────────────────────────────
rec_area_setup() {
  mkdir -p "$HOME_DIR/vid"
}
rec_stop_setup() {
  "$FAKE_BIN/wf-recorder" &
  local pid=$!
  disown
  printf '%s\n' "$pid" > "$PIDFILE"
  sleep 0.1
}
rec_stale_setup() {
  printf '%s\n' 999999 > "$PIDFILE"
}

if tool_enabled screenrec; then
  begin_tool screenrec
  set_env "FAKE_DATE_OUT=20260102-03.04.05" "FAKE_WFREC_LIST="
  compare "screenrec: start in screen mode" rec_area_setup
  set_env "FAKE_DATE_OUT=20260102-03.04.05" \
    "FAKE_SLURP_OUT=100 200 300 400" "FAKE_WFREC_LIST="
  compare "screenrec: area start inside the output" rec_area_setup -- area
  set_env "FAKE_DATE_OUT=20260102-03.04.05" \
    "FAKE_SLURP_OUT=100 200 300 400" \
    "FAKE_MONITORS=[{\"name\":\"DP-1\",\"focused\":true,\"x\":500,\"y\":500,\"width\":2560,\"height\":1440,\"scale\":1}]" \
    "FAKE_WFREC_LIST="
  compare "screenrec: area outside the output drops -o" rec_area_setup -- area
  set_env "FAKE_DATE_OUT=20260102-03.04.05" "FAKE_SLURP_EXIT=1"
  compare "screenrec: cancelled slurp exits 0" rec_area_setup -- area
  set_env "FAKE_DATE_OUT=20260102-03.04.05" "FAKE_WFREC_LIST=" "FAKE_SLEEP_REAL=1"
  compare "screenrec: recorder that dies right away" rec_area_setup
  set_env "FAKE_DATE_OUT=20260102-03.04.05"
  compare "screenrec: stop a running recorder" rec_stop_setup
  set_env "FAKE_DATE_OUT=20260102-03.04.05" "FAKE_WFREC_LIST="
  compare "screenrec: stale pidfile is dropped" rec_stale_setup -- area
  set_env "FAKE_DATE_OUT=20260102-03.04.05" "FAKE_WFREC_LIST=Name: DP-1
	Output DP-1" "FAKE_HYPRCTL_MON_EXIT=1"
  compare "screenrec: single output from wf-recorder -L" rec_area_setup
fi

# ── clip ──────────────────────────────────────────────────────────────────────
clip_videos_setup() {
  mkdir -p "$CASE_DIR/vid/new"
}
clip_novideos_setup() {
  :
}

if tool_enabled clip; then
  begin_tool clip
  compare "clip: help" "" -- help
  compare "clip: -h" "" -- -h
  set_env "FAKE_CLIPHIST_LIST=12: hello world" "FAKE_CLIPHIST_DECODE=hello world" \
    "FAKE_VICINAE_OUT=12: hello world"
  compare "clip: menu decodes the picked row" ""
  set_env "FAKE_VICINAE_OUT="
  compare "clip: cancelled menu exits 0" ""
  set_env "FAKE_WLPASTE=hello
world" "FAKE_VICINAE_OUT=sort"
  compare "clip pipe: default command sorts the selection" ""
  set_env "FAKE_WLPASTE=abc"
  compare "clip pipe: -c runs the command" "" -- pipe -c "tr a-z A-Z"
  set_env "FAKE_WLPASTE=abc"
  compare "clip pipe: -p pastes back" "" -- pipe -p -c cat
  set_env "FAKE_WLPASTE="
  compare "clip pipe: -p with empty clipboard aborts" "" -- pipe -p
  set_env "FAKE_WLPASTE=xyz" "FAKE_VICINAE_OUT=sort"
  compare "clip pipe: positional argument opens the menu" "" -- pipe ignored
  set_env "FAKE_CLIPHIST_LIST=3: https://www.youtube.com/watch?v=abc" \
    "FAKE_VICINAE_OUT=3: https://www.youtube.com/watch?v=abc" \
    "FAKE_CLIPHIST_DECODE=https://www.youtube.com/watch?v=abc"
  compare "clip youtube-dw-list: download the picked URL" clip_videos_setup -- youtube-dw-list
  set_env "FAKE_WLPASTE=https://vimeo.com/1"
  compare "clip youtube-dw: download the clipboard URL" clip_videos_setup -- youtube-dw
  set_env "XDG_VIDEOS_DIR=$CASE_DIR/nope"
  compare "clip youtube-dw: missing directory reports cd" clip_novideos_setup -- youtube-dw
  set_env "FAKE_WLPASTE=https://vimeo.com/1"
  compare "clip youtube-view: scratchpad and paste" "" -- youtube-view
  set_env "USE_CLIPCAT=true"
  compare "clip: USE_CLIPCAT routes to clipcat-menu" ""
fi

# ── screenshot-toast ─────────────────────────────────────────────────────────
toast_png_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'x' > "$CASE_DIR/shots/a.png"
  printf 'IEND\256B\140\202' >> "$CASE_DIR/shots/a.png"
  touch -d '@1767000000' "$CASE_DIR/shots/a.png"
}
toast_incomplete_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'PNGDATA' > "$CASE_DIR/shots/a.png"
  touch -d '@1767000000' "$CASE_DIR/shots/a.png"
}
toast_two_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'IEND\256B\140\202' > "$CASE_DIR/shots/old.png"
  printf 'IEND\256B\140\202' > "$CASE_DIR/shots/new.png"
  touch -d '@1766990000' "$CASE_DIR/shots/old.png"
  touch -d '@1767000005' "$CASE_DIR/shots/new.png"
}
toast_other_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'JPEGDATA' > "$CASE_DIR/shots/a.jpg"
  touch -d '@1767000000' "$CASE_DIR/shots/a.jpg"
}
toast_stamp_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'IEND\256B\140\202' > "$CASE_DIR/shots/a.png"
  touch -d '@1767000000' "$CASE_DIR/shots/a.png"
  local mtime size
  mtime=$(stat -c %Y "$CASE_DIR/shots/a.png")
  size=$(stat -c %s "$CASE_DIR/shots/a.png")
  printf '%s %s %s' "$CASE_DIR/shots/a.png" "$mtime" "$size" > "$RUN_DIR/screenshot-toast-last"
}

if tool_enabled screenshot-toast; then
  begin_tool screenshot-toast
  set_env "PIC_INFO_DIR=$CASE_DIR/shots" "FAKE_DATE_OUT=1767000010"
  compare "screenshot-toast: explicit file execs pic-info" toast_png_setup -- "$CASE_DIR/shots/a.png"
  compare "screenshot-toast: newest complete PNG is announced" toast_png_setup
  compare "screenshot-toast: two shots pick the newest" toast_two_setup
  compare "screenshot-toast: incomplete PNG waits 40 steps" toast_incomplete_setup
  compare "screenshot-toast: non-PNG settles on the size sample" toast_other_setup
  compare "screenshot-toast: already announced file is skipped" toast_stamp_setup
  set_env "PIC_INFO_DIR=$CASE_DIR/shots" "FAKE_DATE_OUT=1767001000"
  compare "screenshot-toast: stale shot is skipped" toast_png_setup
  compare "screenshot-toast: missing explicit file exits 0" "" -- "$CASE_DIR/shots/gone.png"
  set_env "PIC_INFO_DIR=$CASE_DIR/empty" "FAKE_DATE_OUT=1767000010"
  compare "screenshot-toast: empty directory exits 0" ""
fi

# ── pic-info ─────────────────────────────────────────────────────────────────
pi_shot_setup() {
  mkdir -p "$CASE_DIR/shots"
  printf 'a' > "$CASE_DIR/shots/a.png"
  printf 'b' > "$CASE_DIR/shots/b.png"
  touch -d '@1767000000' "$CASE_DIR/shots/a.png"
  touch -d '@1767000100' "$CASE_DIR/shots/b.png"
  printf 'c' > "$HOME_DIR/shot.png"
}
pi_empty_setup() {
  mkdir -p "$CASE_DIR/shots"
}

if tool_enabled pic-info; then
  begin_tool pic-info
  compare "pic-info: help" "" -- -h
  set_env "PATH=$(path_without pic-notify)"
  compare "pic-info: help without pic-notify fails first" ""
  set_env "PIC_INFO_DIR=$CASE_DIR/shots"
  compare "pic-info: no shots is an error" pi_empty_setup
  compare "pic-info: no arguments picks the newest shot" pi_shot_setup
  compare "pic-info: explicit missing file is skipped" pi_shot_setup -- "$CASE_DIR/shots/gone.png"
  # shellcheck disable=SC2088  # the literal ~ is the input being tested
  compare "pic-info: ~ expansion" pi_shot_setup -- "~/shot.png"
  set_env "PIC_INFO_DIR=$CASE_DIR/shots" "XDG_PICTURES_DIR=$CASE_DIR/pics"
  compare "pic-info: PIC_INFO_DIR wins over XDG_PICTURES_DIR" pi_shot_setup
  set_env "PIC_INFO_DIR=" "GRIM_DEFAULT_DIR=$CASE_DIR/shots"
  compare "pic-info: GRIM_DEFAULT_DIR fallback" pi_shot_setup
fi

# ── pic-ocr ──────────────────────────────────────────────────────────────────
ocr_image_setup() {
  printf 'imagebytes' > "$CASE_DIR/i.png"
}
ocr_slurp_setup() {
  rm -f "$WORK/capture.png"
}

# The pic-ocr shell original was deleted when the Rust port landed, so the copy
# restored from git is the pre-port tesseract implementation. Parity is closed
# for this tool (and tesseract itself is gone), so the cases only run when a
# real shell original is present, e.g. PARITY_ORIGINALS pointing at the last
# tree that still carried it.
if tool_enabled pic-ocr && [ -x "$ORIGINALS/pic-ocr" ]; then
  begin_tool pic-ocr
  compare "pic-ocr: help" "" -- -h
  compare "pic-ocr: unknown option" "" -- --bogus
  compare "pic-ocr: unknown engine" ocr_image_setup -- --engine=nope "$CASE_DIR/i.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"line one\\nline two\"}}]}"
  compare "pic-ocr: neural result to clipboard and toast" ocr_image_setup -- "$CASE_DIR/i.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" "FAKE_CURL_OUT="
  compare "pic-ocr: no text recognized exits 1" ocr_image_setup -- "$CASE_DIR/i.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"net text\"}}]}"
  compare "pic-ocr: neural engine builds the jq payload" ocr_image_setup -- --engine=nn "$CASE_DIR/i.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" "FAKE_CURL_OUT=not json"
  compare "pic-ocr: neural failure does not fall back" ocr_image_setup -- --engine=nn "$CASE_DIR/i.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"menu text\"}}]}"
  compare "pic-ocr: menu is an alias for nn" ocr_image_setup -- --menu "$CASE_DIR/i.png"
  set_env "FAKE_SLURP_OUT=10,10 20x20" "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"region text\"}}]}"
  compare "pic-ocr: slurp capture is removed afterwards" ocr_slurp_setup
  set_env "FAKE_SLURP_EXIT=1"
  compare "pic-ocr: cancelled slurp exits 1" ocr_slurp_setup
  set_env "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"text\"}}]}"
  compare "pic-ocr: missing file exits 1" "" -- "$CASE_DIR/gone.png"
  set_env "FAKE_MAGICK_OUT=jpgdata" \
    "FAKE_CURL_OUT={\"choices\":[{\"message\":{\"content\":\"$(printf 'a%.0s' $(seq 1 200))\"}}]}" \
    "FAKE_NOTIFY_EXIT=3"
  compare "pic-ocr: long preview is cut to 140 chars" ocr_image_setup -- "$CASE_DIR/i.png"
fi

# ── pic-dirs-list ────────────────────────────────────────────────────────────
pdl_tree_setup() {
  mkdir -p "$CASE_DIR/pic/a/b/c" "$CASE_DIR/pic/.git/x" "$CASE_DIR/pic/z"
  printf '%s\n' "$CASE_DIR/pic CREATE,ISDIR" > "$FAKE_INOTIFY_LINES"
}
pdl_plain_setup() {
  mkdir -p "$CASE_DIR/pic/a"
  printf '%s\n' "$CASE_DIR/pic CREATE" > "$FAKE_INOTIFY_LINES"
}

if tool_enabled pic-dirs-list; then
  begin_tool pic-dirs-list
  compare "pic-dirs-list: help" "" -- -h
  compare "pic-dirs-list: no XDG_PICTURES_DIR exits 0" ""
  set_env "XDG_PICTURES_DIR=$CASE_DIR/pic" "PATH=$(path_without inotifywait)"
  compare "pic-dirs-list: no inotifywait exits 0" pdl_tree_setup
  set_env "XDG_PICTURES_DIR=$CASE_DIR/pic/" "FAKE_INOTIFY_LINES=$FAKE_INOTIFY_LINES"
  compare "pic-dirs-list: initial index plus ISDIR reindex" pdl_tree_setup
  compare "pic-dirs-list: a non-ISDIR event does not reindex" pdl_plain_setup
fi

# ── wl-restore ───────────────────────────────────────────────────────────────
wl_state_setup() {
  mkdir -p "$HOME_DIR/.local/state/wl" "$HOME_DIR/pic/wl"
  printf 'wall' > "$HOME_DIR/wall.png"
  printf '%s' "{\"outputs\":{\"eDP-1\":{\"wallpaper_path\":\"$HOME_DIR/wall.png\"}}}" \
    > "$HOME_DIR/.local/state/wl/state.json"
}
wl_stale_setup() {
  mkdir -p "$HOME_DIR/.local/state/wl" "$HOME_DIR/pic/wl"
  printf '%s' "{\"outputs\":{\"eDP-1\":{\"wallpaper_path\":\"$HOME_DIR/gone.png\"}}}" \
    > "$HOME_DIR/.local/state/wl/state.json"
}
wl_empty_setup() {
  mkdir -p "$HOME_DIR/pic/wl"
}
if tool_enabled wl-restore; then
  begin_tool wl-restore
  compare "wl-restore: valid state restores" wl_state_setup
  compare "wl-restore: stale state falls back to a random pick" wl_stale_setup
  compare "wl-restore: no state falls back to a random pick" wl_empty_setup
  set_env "FAKE_WL_RESTORE_EXIT=1"
  compare "wl-restore: failing restore falls back to random" wl_state_setup
  set_env "FAKE_WL_COUNTER=$FAKE_WL_COUNTER"
  wl_retry_setup() {
    wl_state_setup "$@"
    printf '3' > "$FAKE_WL_COUNTER"
  }
  compare "wl-restore: waits for the daemon socket" wl_retry_setup
  # There is no "greeter cache sync" scenario any more: the copy into
  # /home/greeter went with that account on 2026-11-03, and the port no longer
  # reads the legacy `~/.cache/quickshell-wallpaper-path` — the stale-state
  # fallback walks wl's last-good, the producer cache and the old
  # `current_wallpaper_source` link instead.
fi

# ── unlock ───────────────────────────────────────────────────────────────────
if tool_enabled unlock; then
  begin_tool unlock
  set_env "FAKE_SSH_SOCK=/tmp/parity-agent.sock" "FAKE_SSH_PID=999" "FAKE_PASS_KEY=secret"
  compare "unlock: starts an agent and feeds expect" ""
  set_env "SSH_AUTH_SOCK=/tmp/existing.sock" "FAKE_PASS_KEY=secret"
  compare "unlock: existing agent is reused" ""
  set_env "SSH_AUTH_SOCK=/tmp/existing.sock" "FAKE_PASS_KEY=secret" \
    "FAKE_PASS_WRK_KEY=work" "FAKE_PASS_WRK_EXIT=0"
  compare "unlock: work key is fetched when present" ""
  set_env "SSH_AUTH_SOCK=/tmp/existing.sock" "FAKE_PASS_KEY=" "FAKE_PASS_KEY_EXIT=1"
  compare "unlock: failing pass still runs expect" ""
  set_env "SSH_AUTH_SOCK=/tmp/existing.sock" "FAKE_PASS_KEY=secret" "FAKE_EXPECT_EXIT=4"
  compare "unlock: expect exit status is propagated" ""
fi

# ── kitty-font-zoom ──────────────────────────────────────────────────────────
kfz_sock_setup() {
  rm -f /tmp/kitty-4242
  python3 - << 'SOCK'
import socket
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind("/tmp/kitty-4242")
s.close()
SOCK
}

kfz_cleanup_sock() {
  rm -f /tmp/kitty-4242
}

if tool_enabled kitty-font-zoom; then
  begin_tool kitty-font-zoom
  compare "kitty-font-zoom: usage exits 2" ""
  set_env "FAKE_ACTIVEWINDOW="
  compare "kitty-font-zoom: empty activewindow exits 0" "" -- up
  set_env "FAKE_ACTIVEWINDOW={\"pid\":4242}"
  compare "kitty-font-zoom: missing socket exits 0" "" -- up
  set_env "FAKE_ACTIVEWINDOW={\"pid\":4242}"
  compare "kitty-font-zoom: up sends set-font-size +0.5" kfz_sock_setup -- up
  compare "kitty-font-zoom: down sends -0.5" kfz_sock_setup -- down
  compare "kitty-font-zoom: reset sends 0" kfz_sock_setup -- reset
  compare "kitty-font-zoom: off keeps the double prefix" kfz_sock_setup -- off
  compare "kitty-font-zoom: on keeps the double prefix" kfz_sock_setup -- on
  set_env "FAKE_ACTIVEWINDOW={\"pid\":4242}" "FAKE_KITTEN_VARS=font_zoom=off"
  compare "kitty-font-zoom: toggle from off turns it on" kfz_sock_setup -- toggle
  set_env "FAKE_ACTIVEWINDOW={\"pid\":4242}" "FAKE_KITTEN_VARS=font_zoom=on"
  compare "kitty-font-zoom: toggle from on turns it off" kfz_sock_setup -- toggle
  kfz_cleanup_sock
fi

# ── cursor-stretch ───────────────────────────────────────────────────────────
if tool_enabled cursor-stretch; then
  begin_tool cursor-stretch
  set_env "FAKE_GETOPTION={\"bool\":true}"
  compare "cursor-stretch: status reports the current value" "" -- status
  compare "cursor-stretch: on enables" "" -- on
  compare "cursor-stretch: off disables" "" -- off
  compare "cursor-stretch: toggle flips true to false" "" -- toggle
  set_env "FAKE_GETOPTION={\"bool\":false}"
  compare "cursor-stretch: toggle flips false to true" "" -- toggle
  compare "cursor-stretch: usage exits 2" "" -- bogus
  set_env "PATH=$(path_without notify-send)"
  compare "cursor-stretch: missing notify-send exits 1" "" -- on
  set_env "FAKE_HYPRCTL_EVAL_EXIT=3"
  compare "cursor-stretch: eval failure is fatal" "" -- on
fi

# ── pngoptim ─────────────────────────────────────────────────────────────────
png_setup() {
  printf 'PNG' > "$CASE_DIR/image.png"
}
png_text_setup() {
  printf 'TEXT' > "$CASE_DIR/image.txt"
}

if tool_enabled pngoptim; then
  begin_tool pngoptim
  compare "pngoptim: no argument prints usage" ""
  compare "pngoptim: -h prints usage on stderr" "" -- -h
  compare "pngoptim: help prints usage on stderr" "" -- help
  compare "pngoptim: '?' prints usage on stderr" "" -- "?"
  compare "pngoptim: missing file" "" -- "$CASE_DIR/gone.png"
  compare "pngoptim: not a PNG" png_text_setup -- "$CASE_DIR/image.txt"
  compare "pngoptim: oxipng argv" png_setup -- "$CASE_DIR/image.png"
  set_env "PATH=$(path_without oxipng)"
  compare "pngoptim: missing oxipng warns and exits 127" png_setup -- "$CASE_DIR/image.png"
  set_env "FAKE_OXIPNG_EXIT=2"
  compare "pngoptim: oxipng exit status is propagated" png_setup -- "$CASE_DIR/image.png"
fi

# ── hypr-resize-proportional ────────────────────────────────────────────────
if tool_enabled hypr-resize-proportional; then
  begin_tool hypr-resize-proportional
  compare "hrp: missing argument" ""
  compare "hrp: empty argument" "" -- ""
  compare "hrp: tiled window is skipped" "" -- +10
  set_env "FAKE_ACTIVEWINDOW={\"floating\":true,\"size\":[800,600]}"
  compare "hrp: grow by ten percent" "" -- +10
  compare "hrp: shrink by ten percent" "" -- -10
  compare "hrp: minimum size clamp" "" -- -99
  set_env "FAKE_ACTIVEWINDOW={\"floating\":true,\"size\":[800,600]}" \
    "FAKE_MONITORS=[{\"width\":100,\"height\":90,\"scale\":1}]"
  compare "hrp: monitor clamp" "" -- +10
  set_env "FAKE_ACTIVEWINDOW={\"floating\":true,\"size\":[800,600]}" \
    "FAKE_MONITORS=[{\"width\":2560,\"height\":1440,\"scale\":2}]"
  compare "hrp: monitor size honours the scale" "" -- +10
  set_env "FAKE_ACTIVEWINDOW={\"floating\":true,\"size\":[800,600]}" "PATH=$(path_without bc)"
  compare "hrp: missing bc keeps the original dispatch" "" -- +10
  set_env "FAKE_ACTIVEWINDOW={\"floating\":true,\"size\":[800,600]}" "FAKE_BC_FLOAT=1"
  compare "hrp: fractional bc output hits bash arithmetic" "" -- +10
  set_env "FAKE_HYPRCTL_AW_EXIT=1"
  compare "hrp: hyprctl failure exits 1" "" -- +10
fi

cleanup_case_processes
printf '\nparity: %d checks, %d exact, %d order-normalised, %d failed\n' \
  "$CHECKS" "$((CHECKS - NORMALIZED - FAILED))" "$NORMALIZED" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
