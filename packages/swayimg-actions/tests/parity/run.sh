#!/usr/bin/env bash
# One-off migration harness: run the zsh helper and the Rust port in identical
# sandboxes and compare observable behaviour.
#
#   tests/parity/run.sh <path-to-swayimg-actions-binary> [shell-script]
#
# For every scenario the harness builds the same fixture tree (controlled ctime
# order), the same fake tools on PATH and the same real UnixListener socket,
# then compares:
#   - stdout, stderr (after normalizing the shell's "<file>:<line>: command not
#     found:" prefix and the PID in temp-file names), exit code;
#   - the fake tools' recorded argv, byte for byte;
#   - the IPC payload bytes received on the socket;
#   - a full snapshot of the sandbox (tree, symlink targets, file hashes),
#     which covers moved/copied files, last, range_mark and wallpaper.list.
#
# It needs zsh, socat, python3 and the usual coreutils on the host; nothing
# touches the real HOME, ~/tmp, ~/trash, ~/.local/share or IPC sockets. This is
# deliberately not a cargo test: it references the shell script that the
# integration step deletes. Run it while the script still exists.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-}
if [ -z "$BIN" ]; then
  echo "usage: $0 <swayimg-actions-binary> [shell-script]" >&2
  exit 2
fi
SH=${2:-$HERE/../../../../packages/local-bin/bin/swayimg-actions.sh}
ZSH=$(command -v zsh || true)
if [ -z "$ZSH" ]; then
  echo "zsh not found" >&2
  exit 2
fi
if [ ! -f "$SH" ]; then
  echo "shell script not found: $SH" >&2
  exit 2
fi
if [ ! -x "$BIN" ]; then
  echo "binary not executable: $BIN" >&2
  exit 2
fi

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/swayimg-actions-parity.XXXXXX")
CORE=$ROOT/core
GLOBAL_FAKE=$ROOT/global-fake
SCENARIO_FAKE=$ROOT/scenario-fake
SANDBOX=$ROOT/sandbox
STATE=$ROOT/state
RUNTIME=$ROOT/run
OUT=$ROOT/out
SCENARIOS_LOG=$ROOT/scenarios.log
mkdir -p "$CORE" "$GLOBAL_FAKE" "$OUT"
: > "$SCENARIOS_LOG"

cleanup() {
  if [ -n "${LISTENER_PID:-}" ]; then
    kill "$LISTENER_PID" 2> /dev/null || true
    wait "$LISTENER_PID" 2> /dev/null || true
  fi
  if [ "${KEEP:-0}" = 1 ]; then
    echo "kept: $ROOT" >&2
  else
    rm -rf "$ROOT"
  fi
}
trap cleanup EXIT

die() {
  echo "parity: $*" >&2
  exit 2
}

# ---- host tools for the sandbox PATH -------------------------------------
for tool in awk cat cp cut dirname env find grep id jq mkdir mktemp mv \
  python3 realpath rm sed sleep socat sort tee; do
  source=$(command -v "$tool" || true)
  [ -n "$source" ] || die "missing host tool: $tool"
  ln -s "$source" "$CORE/$tool"
done

# ---- fake tools ----------------------------------------------------------
write_fake() {
  name=$1
  body=$2
  {
    echo '#!/bin/sh'
    cat << 'LOGGER'
log() {
  name=$1
  shift
  printf '%s' "$name" >> "$FAKE_STATE/tools.log"
  for arg in "$@"; do printf '\037%s' "$arg" >> "$FAKE_STATE/tools.log"; done
  printf '\n' >> "$FAKE_STATE/tools.log"
}
LOGGER
    printf '%s\n' "$body"
  } > "$GLOBAL_FAKE/$name"
  chmod 755 "$GLOBAL_FAKE/$name"
}

write_fake mogrify 'log mogrify "$@"
exit "${MOGRIFY_EXIT:-0}"'

write_fake convert 'log convert "$@"
last=
for arg in "$@"; do last=$arg; done
if [ -n "$last" ]; then printf rendered > "$last"; fi
exit "${CONVERT_EXIT:-0}"'

write_fake swww 'log swww "$@"
if [ "$1" = query ]; then exit "${SWWW_QUERY_EXIT:-0}"; fi
exit 0'

write_fake swaymsg 'log swaymsg "$@"
cat "$FAKE_STATE/swaymsg.json"
exit "${SWAYMSG_EXIT:-0}"'

write_fake vicinae 'log vicinae "$@"
cat > "$FAKE_STATE/vicinae.stdin"
cat "$FAKE_STATE/vicinae.out"
exit "${VICINAE_EXIT:-0}"'

write_fake zoxide 'log zoxide "$@"
if [ "$1" = query ]; then cat "$FAKE_STATE/zoxide.list"; fi
exit 0'

write_fake wl-copy 'log wl-copy "$@"
cat > "$FAKE_STATE/wl-copy.stdin"
exit "${WLCOPY_EXIT:-0}"'

write_fake ug 'exec grep "$@"'

PIC_NOTIFY_SCRIPT='#!/bin/sh
log() {
  name=$1
  shift
  printf "%s" "$name" >> "$FAKE_STATE/tools.log"
  for arg in "$@"; do printf "\037%s" "$arg" >> "$FAKE_STATE/tools.log"; done
  printf "\n" >> "$FAKE_STATE/tools.log"
}
log pic-notify "$@"
exit "${PICNOTIFY_EXIT:-0}"'

ALL_FAKES=(mogrify convert swww swaymsg vicinae zoxide wl-copy ug)

# ---- scenario configuration ---------------------------------------------
ARGS=()
EXTRA=()
HIDDEN=()
NOTIFY=0
USE_IPC=0
IPC_MODE="env"
FIXTURE=fixture_one
VICINAE_OUT=
SWAYMSG_JSON='[{"active":true,"current_mode":{"width":1920,"height":1080}},{"active":true,"current_mode":{"width":2560,"height":1440}},{"active":false,"current_mode":{"width":3840,"height":2160}}]'

PICS=$SANDBOX/home/Pictures
# A literal tilde for the picker output: SC2088 would prefer $HOME, but the
# whole point is testing the script's sed-driven tilde rewrite.
TILDE='~'
CUR=$SANDBOX/home/pic/cur.jpg
RANGE=$SANDBOX/home/Pictures

configure() {
  ARGS=()
  EXTRA=()
  HIDDEN=()
  NOTIFY=0
  USE_IPC=0
  IPC_MODE="env"
  FIXTURE=fixture_one
  VICINAE_OUT=
  SWAYMSG_JSON='[{"active":true,"current_mode":{"width":1920,"height":1080}},{"active":true,"current_mode":{"width":2560,"height":1440}},{"active":false,"current_mode":{"width":3840,"height":2160}}]'

  case "$1" in
    help-long) ARGS=(--help) ;;
    help-short) ARGS=(-h) ;;
    unknown-empty) ARGS=() ;;
    unknown-action) ARGS=(bogus) ;;
    unknown-escape) ARGS=('bad\nname') ;;
    repeat) ARGS=(repeat "$CUR") ;;
    rotate-left) ARGS=(rotate-left "$CUR") ;;
    rotate-right) ARGS=(rotate-right "$CUR") ;;
    rotate-180) ARGS=(rotate-180 "$CUR") ;;
    rotate-ccw) ARGS=(rotate-ccw "$CUR") ;;
    rotate-missing-mogrify)
      ARGS=(rotate-left "$CUR")
      HIDDEN=(mogrify)
      ;;
    copyname)
      ARGS=(copyname "$CUR")
      NOTIFY=1
      ;;
    copyname-no-notify) ARGS=(copyname "$CUR") ;;
    copyname-missing-wl-copy)
      ARGS=(copyname "$CUR")
      NOTIFY=1
      HIDDEN=(wl-copy)
      ;;
    mv-explicit)
      ARGS=(mv "$CUR" "$SANDBOX/trash/1st-level/pic")
      USE_IPC=1
      ;;
    mv-picker)
      ARGS=(mv "$CUR")
      USE_IPC=1
      VICINAE_OUT="$TILDE/Pictures/dest"
      FIXTURE=fixture_picker
      ;;
    mv-picker-cancel)
      ARGS=(mv "$CUR")
      USE_IPC=1
      VICINAE_OUT=
      FIXTURE=fixture_picker
      ;;
    cp-explicit) ARGS=(cp "$CUR" "$SANDBOX/home/explicit-dest") ;;
    cp-picker)
      ARGS=(cp "$CUR")
      VICINAE_OUT="$TILDE/Pictures/dest"
      FIXTURE=fixture_picker
      ;;
    cp-picker-cancel)
      ARGS=(cp "$CUR")
      VICINAE_OUT=
      FIXTURE=fixture_picker
      ;;
    wall-mono) ARGS=(wall-mono "$CUR") ;;
    wall-fill) ARGS=(wall-fill "$CUR") ;;
    wall-full) ARGS=(wall-full "$CUR") ;;
    wall-tile) ARGS=(wall-tile "$CUR") ;;
    wall-center) ARGS=(wall-center "$CUR") ;;
    wall-cover) ARGS=(wall-cover "$CUR") ;;
    wall-init)
      ARGS=(wall-fill "$CUR")
      EXTRA=("SWWW_QUERY_EXIT=1")
      ;;
    wall-override-flags)
      ARGS=(wall-fill "$CUR")
      EXTRA=(
        "SWWW_IMAGE_OVERRIDE=$SANDBOX/override.img"
        "SWWW_FLAGS=--transition-type fade --flag"
      )
      ;;
    wall-convert-missing)
      ARGS=(wall-fill "$CUR")
      HIDDEN=(convert)
      ;;
    wall-convert-fail)
      ARGS=(wall-fill "$CUR")
      EXTRA=("CONVERT_EXIT=3")
      ;;
    wall-swww-missing)
      ARGS=(wall-fill "$CUR")
      HIDDEN=(swww)
      ;;
    wall-swaymsg-missing)
      ARGS=(wall-center "$CUR")
      HIDDEN=(swaymsg)
      ;;
    wall-no-active-output)
      ARGS=(wall-center "$CUR")
      SWAYMSG_JSON='[{"active":false,"current_mode":{"width":3840,"height":2160}},{"active":true,"current_mode":null}]'
      ;;
    wall-echo-escapes)
      ARGS=(wall-mono "$SANDBOX/home/Pictures/esc\\nname\\cstop.jpg")
      FIXTURE=fixture_echo
      ;;
    range-mark-ok)
      ARGS=(range-mark "$RANGE/three.jpg")
      FIXTURE=fixture_range
      ;;
    range-mark-symlink)
      ARGS=(range-mark "$RANGE/link.jpg")
      FIXTURE=fixture_range
      ;;
    range-mark-missing)
      ARGS=(range-mark "$RANGE/nope.jpg")
      FIXTURE=fixture_range
      ;;
    range-mark-broken-symlink)
      ARGS=(range-mark "$RANGE/broken.jpg")
      FIXTURE=fixture_range_with_broken
      ;;
    range-clear)
      ARGS=(range-clear)
      FIXTURE=fixture_range_with_mark
      ;;
    range-trash-no-mark)
      ARGS=(range-trash "$RANGE/five.jpg")
      FIXTURE=fixture_range
      USE_IPC=1
      ;;
    range-trash-empty-mark)
      ARGS=(range-trash "$RANGE/five.jpg")
      FIXTURE=fixture_range_empty_mark
      USE_IPC=1
      ;;
    range-trash-stale)
      ARGS=(range-trash "$RANGE/five.jpg")
      FIXTURE=fixture_range_stale
      USE_IPC=1
      ;;
    range-trash-anchor-other-dir)
      ARGS=(range-trash "$RANGE/five.jpg")
      FIXTURE=fixture_range_other_mark
      ;;
    range-cp-no-mark)
      ARGS=(range-cp "$RANGE/five.jpg")
      FIXTURE=fixture_range
      VICINAE_OUT="$TILDE/Pictures/dest"
      ;;
    range-cp-cancel)
      ARGS=(range-cp "$RANGE/five.jpg")
      FIXTURE=fixture_range
      VICINAE_OUT=
      ;;
    range-cp-stale)
      ARGS=(range-cp "$RANGE/five.jpg")
      FIXTURE=fixture_range_stale
      VICINAE_OUT="$TILDE/Pictures/dest"
      ;;
    range-cp-anchor-other-dir)
      ARGS=(range-cp "$RANGE/five.jpg")
      FIXTURE=fixture_range_other_mark
      VICINAE_OUT="$TILDE/Pictures/dest"
      ;;
    range-mv-no-mark)
      ARGS=(range-mv "$RANGE/five.jpg")
      FIXTURE=fixture_range
      VICINAE_OUT="$TILDE/Pictures/dest"
      USE_IPC=1
      ;;
    range-mv-stale)
      ARGS=(range-mv "$RANGE/five.jpg")
      FIXTURE=fixture_range_stale
      VICINAE_OUT="$TILDE/Pictures/dest"
      USE_IPC=1
      ;;
    range-mv-anchor-other-dir)
      ARGS=(range-mv "$RANGE/five.jpg")
      FIXTURE=fixture_range_other_mark
      VICINAE_OUT="$TILDE/Pictures/dest"
      ;;
    missing-vicinae)
      ARGS=(mv "$CUR")
      FIXTURE=fixture_picker
      HIDDEN=(vicinae)
      USE_IPC=1
      ;;
    missing-zoxide)
      ARGS=(cp "$CUR")
      FIXTURE=fixture_picker
      HIDDEN=(zoxide)
      VICINAE_OUT="$TILDE/Pictures/dest"
      ;;
    ipc-discover-new)
      ARGS=(mv "$CUR" "$SANDBOX/trash/1st-level/pic")
      USE_IPC=1
      IPC_MODE=discover-new
      ;;
    ipc-discover-newest-non-socket)
      ARGS=(mv "$CUR" "$SANDBOX/trash/1st-level/pic")
      USE_IPC=1
      IPC_MODE=discover-nonsocket
      ;;
    *) die "unknown scenario: $1" ;;
  esac
}

# ---- fixtures ------------------------------------------------------------
fixture_one() {
  printf img > "$CUR"
}

fixture_picker() {
  mkdir -p "$PICS/dest"
  printf img > "$CUR"
}

fixture_echo() {
  printf img > "$PICS/esc\\nname\\cstop.jpg"
}

fixture_range() {
  mkdir -p "$PICS/sub" "$PICS/dest"
  printf img > "$CUR"
  for name in one two three four five; do
    printf '%s' "$name" > "$PICS/$name.jpg"
    sleep 0.012
  done
  printf skip > "$PICS/note.txt"
  sleep 0.012
  printf sub > "$PICS/sub/six.png"
  sleep 0.012
  ln -s "$PICS/two.jpg" "$PICS/link.jpg"
}

write_mark() {
  mkdir -p "$SANDBOX/xdg/swayimg"
  printf '%s\n' "$1" > "$SANDBOX/xdg/swayimg/range_mark"
}

fixture_range_with_mark() {
  fixture_range
  write_mark "$PICS/three.jpg"
}

fixture_range_empty_mark() {
  fixture_range
  write_mark ""
}

fixture_range_stale() {
  fixture_range
  write_mark "$PICS/deleted.jpg"
}

fixture_range_other_mark() {
  fixture_range
  mkdir -p "$SANDBOX/home/other"
  printf other > "$SANDBOX/home/other/two.jpg"
  write_mark "$SANDBOX/home/other/two.jpg"
}

fixture_range_with_broken() {
  fixture_range
  ln -s "$PICS/does-not-exist.jpg" "$PICS/broken.jpg"
}

# ---- sandbox preparation -------------------------------------------------
reset_sandbox() {
  rm -rf "$SANDBOX" "$RUNTIME"
  mkdir -p "$SANDBOX/home/pic" "$SANDBOX/home/Pictures" "$SANDBOX/xdg/wl" \
    "$SANDBOX/tmp" "$RUNTIME"
  "$FIXTURE"
  if [ "$NOTIFY" = 1 ]; then
    mkdir -p "$SANDBOX/home/.local/bin"
    printf '%s\n' "$PIC_NOTIFY_SCRIPT" > "$SANDBOX/home/.local/bin/pic-notify"
    chmod 755 "$SANDBOX/home/.local/bin/pic-notify"
  fi
}

reset_state() {
  rm -rf "$STATE"
  mkdir -p "$STATE"
  printf '%s\n' "$SWAYMSG_JSON" > "$STATE/swaymsg.json"
  printf '%s\n' "$VICINAE_OUT" > "$STATE/vicinae.out"
  {
    printf '%s\n' "$SANDBOX/home/Pictures"
    printf '%s\n' "$SANDBOX/home/pic"
    printf '%s\n' "$SANDBOX/home/.hidden/x"
    printf '%s\n' "/mnt/one/foo"
    printf '%s\n' "/mnt/one/.bar"
    printf '%s\n' "/usr/share/dot"
  } > "$STATE/zoxide.list"
  : > "$STATE/tools.log"
  : > "$STATE/vicinae.stdin"
  : > "$STATE/wl-copy.stdin"
  : > "$STATE/ipc.bytes"
}

prepare_fake_dir() {
  rm -rf "$SCENARIO_FAKE"
  mkdir -p "$SCENARIO_FAKE"
  for fake in "${ALL_FAKES[@]}"; do
    skip=0
    for hidden in "${HIDDEN[@]:-}"; do
      [ "$fake" = "$hidden" ] && skip=1
    done
    [ "$skip" = 1 ] || ln -s "$GLOBAL_FAKE/$fake" "$SCENARIO_FAKE/$fake"
  done
}

bind_socket_only() {
  "$CORE/python3" -c '
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.close()
' "$1"
}

start_listener() {
  LISTEN_SOCK=$1
  rm -f "$LISTEN_SOCK" "$STATE/ipc.bytes"
  "$CORE/python3" "$HERE/listener.py" "$LISTEN_SOCK" "$STATE/ipc.bytes" 0.2 &
  LISTENER_PID=$!
  for _ in $(seq 1 200); do
    [ -S "$LISTEN_SOCK" ] && return 0
    sleep 0.01
  done
  die "listener did not create $LISTEN_SOCK"
}

prepare_ipc() {
  LISTENER_PID=
  LISTEN_SOCK=
  [ "$USE_IPC" = 1 ] || return 0
  case "$IPC_MODE" in
    env)
      start_listener "$STATE/ipc.sock"
      ;;
    discover-new)
      bind_socket_only "$RUNTIME/swayimg-old.sock"
      touch -d '2020-01-01 00:00:00' "$RUNTIME/swayimg-old.sock"
      start_listener "$RUNTIME/swayimg-new.sock"
      ;;
    discover-nonsocket)
      start_listener "$RUNTIME/swayimg-old.sock"
      # Newer name match that is not a socket: the shell checks only matches[1]
      # and gives up, it does not fall through to the older socket.
      touch "$RUNTIME/swayimg-zzz.sock"
      ;;
    *) die "bad IPC mode: $IPC_MODE" ;;
  esac
}

# ---- one phase (shell or binary) -----------------------------------------
collect_artifacts() {
  tag=$1
  cp "$RAW_STDOUT" "$OUT/$tag.stdout"
  cp "$RAW_STDERR" "$OUT/$tag.stderr"
  echo "$RAW_EXIT" > "$OUT/$tag.exit"
  cp "$STATE/tools.log" "$OUT/$tag.tools"
  cp "$STATE/ipc.bytes" "$OUT/$tag.ipc"
  cp "$STATE/vicinae.stdin" "$OUT/$tag.vicinae.stdin" 2> /dev/null || :
  cp "$STATE/wl-copy.stdin" "$OUT/$tag.wl-copy.stdin" 2> /dev/null || :
  (
    cd "$SANDBOX" || exit 1
    find . -mindepth 1 -printf '%y %p -> %l\n' | LC_ALL=C sort
  ) > "$OUT/$tag.tree"
  (
    cd "$SANDBOX" || exit 1
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
  ) > "$OUT/$tag.hashes"
}

run_phase() {
  tag=$1
  shift
  reset_sandbox
  reset_state
  prepare_ipc

  RUN_ENV=(
    "PATH=$SCENARIO_FAKE:$CORE"
    "HOME=$SANDBOX/home"
    "XDG_DATA_HOME=$SANDBOX/xdg"
    "XDG_PICTURES_DIR=$PICS"
    "XDG_RUNTIME_DIR=$RUNTIME"
    "TMPDIR=$SANDBOX/tmp"
    "LC_ALL=C"
    "LANG=C"
    # NixOS' /etc/zshenv otherwise sources set-environment and replaces PATH,
    # HOME-derived XDG_* and LANG for the zsh run (the Rust run never reads it).
    "__NIXOS_SET_ENVIRONMENT_DONE=1"
    "FAKE_STATE=$STATE"
  )
  RUN_EXTRA=("${EXTRA[@]}")
  if [ "$USE_IPC" = 1 ] && [ "$IPC_MODE" = env ]; then
    RUN_EXTRA+=("SWAYIMG_IPC=$LISTEN_SOCK")
  fi

  RAW_STDOUT=$ROOT/$tag.raw.stdout
  RAW_STDERR=$ROOT/$tag.raw.stderr
  if [ "$tag" = sh ]; then
    env -i "${RUN_ENV[@]}" "${RUN_EXTRA[@]}" "$ZSH" "$SH" "${ARGS[@]}" \
      > "$RAW_STDOUT" 2> "$RAW_STDERR"
  else
    env -i "${RUN_ENV[@]}" "${RUN_EXTRA[@]}" "$BIN" "${ARGS[@]}" \
      > "$RAW_STDOUT" 2> "$RAW_STDERR"
  fi
  RAW_EXIT=$?

  if [ -n "${LISTENER_PID:-}" ]; then
    wait "$LISTENER_PID" 2> /dev/null || true
    LISTENER_PID=
  fi
  collect_artifacts "$tag"
}

# ---- comparison ----------------------------------------------------------
normalize_command_not_found() {
  # The shell's own redirection/pipeline diagnostics are not part of the
  # helper's contract and have no Rust equivalent:
  #   <file>:<line>: command not found: <tool>   (location is shell bookkeeping)
  #   copy_name:printf:2: write error: broken pipe
  #   choose_dest:2: write error: inappropriate ioctl for device
  # The last two appear only when a downstream pipeline tool is missing.
  sed -E \
    -e 's/^.*: command not found: /command not found: /' \
    -e '/^(copy_name|choose_dest):(printf:)?[0-9]+: write error: .*$/d'
}

normalize_pids() {
  sed -E 's/(swayimg|wall_swww)\.[0-9]+/\1.PID/g'
}

normalize() {
  artifact=$1
  tag=$2
  case "$artifact" in
    stderr) normalize_command_not_found < "$OUT/$tag.stderr" | normalize_pids ;;
    stdout | tools | tree | hashes | vicinae.stdin | wl-copy.stdin)
      normalize_pids < "$OUT/$tag.$artifact"
      ;;
    exit | ipc) cat "$OUT/$tag.$artifact" ;;
    *) cat "$OUT/$tag.$artifact" ;;
  esac
}

COMPARED=(stdout stderr exit tools ipc vicinae.stdin wl-copy.stdin tree hashes)

compare_phase() {
  scenario=$1
  failed=0
  for artifact in "${COMPARED[@]}"; do
    normalize "$artifact" sh > "$OUT/sh.norm.$artifact"
    normalize "$artifact" bin > "$OUT/bin.norm.$artifact"
    if ! diff -q "$OUT/sh.norm.$artifact" "$OUT/bin.norm.$artifact" > /dev/null; then
      failed=1
      echo "FAIL $scenario [$artifact]" >> "$SCENARIOS_LOG"
      if [ "${VERBOSE:-0}" = 1 ]; then
        diff -u "$OUT/sh.norm.$artifact" "$OUT/bin.norm.$artifact" | head -40 >&2
      fi
    fi
  done
  if [ "$failed" = 0 ]; then
    echo "ok   $scenario"
    return 0
  fi
  echo "FAIL $scenario"
  return 1
}

# ---- scenario list -------------------------------------------------------
SCENARIOS=(
  help-long
  help-short
  unknown-empty
  unknown-action
  unknown-escape
  repeat
  rotate-left
  rotate-right
  rotate-180
  rotate-ccw
  rotate-missing-mogrify
  copyname
  copyname-no-notify
  copyname-missing-wl-copy
  mv-explicit
  mv-picker
  mv-picker-cancel
  cp-explicit
  cp-picker
  cp-picker-cancel
  wall-mono
  wall-fill
  wall-full
  wall-tile
  wall-center
  wall-cover
  wall-init
  wall-override-flags
  wall-convert-missing
  wall-convert-fail
  wall-swww-missing
  wall-swaymsg-missing
  wall-no-active-output
  wall-echo-escapes
  range-mark-ok
  range-mark-symlink
  range-mark-missing
  range-mark-broken-symlink
  range-clear
  range-trash-no-mark
  range-trash-empty-mark
  range-trash-stale
  range-trash-anchor-other-dir
  range-cp-no-mark
  range-cp-cancel
  range-cp-stale
  range-cp-anchor-other-dir
  range-mv-no-mark
  range-mv-stale
  range-mv-anchor-other-dir
  missing-vicinae
  missing-zoxide
  ipc-discover-new
  ipc-discover-newest-non-socket
)

if [ -n "${ONLY:-}" ]; then
  read -r -a SCENARIOS <<< "$ONLY"
fi

failures=0
total=0
for scenario in "${SCENARIOS[@]}"; do
  total=$((total + 1))
  configure "$scenario"
  prepare_fake_dir
  rm -rf "$OUT"
  mkdir -p "$OUT"
  run_phase sh
  run_phase bin
  compare_phase "$scenario" || failures=$((failures + 1))
done

echo
echo "parity: $((total - failures))/$total scenarios match"
if [ "$failures" != 0 ]; then
  echo "failed scenarios:" >&2
  grep '^FAIL' "$SCENARIOS_LOG" >&2 || true
  echo "rerun with VERBOSE=1 to see diffs" >&2
  exit 1
fi
