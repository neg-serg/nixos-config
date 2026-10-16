#!/usr/bin/env bash
# kbd.sh - keyboard-layout worker: Hyprland keyboard status and switching.
#
# A scene spawns this worker while its layout view exists. It prints one
# status line, then keeps it current from Hyprland's event socket
# (activelayout / keyboard-layout / submap, one burst per layout switch is
# coalesced into one status line) and answers `switch` commands on stdin with
# `hyprctl switchxkblayout`. Without a socket, or without socat to open it,
# the worker degrades to polling hyprctl every --interval seconds instead of
# failing. See README.md for the line protocol.
#
# Usage: kbd.sh [--once] [--socket PATH] [--interval SECONDS]
#               [switch [next|prev|DEVICE [next|prev]]] [--help]
#
# Output: {"ok": {...}} on start and on every layout/submap change, and after
# each switch; {"err": "..."} when hyprctl is missing or cannot answer.
# Exit: 0 when finished; 2 on a usage error.

set -euo pipefail

usage() {
  cat << 'EOF'
kbd.sh - current keyboard layout(s), device and submap as JSON

Usage:
  kbd.sh [options] [command]

Commands:
  status                     print the status and keep it current (default)
  switch [next|prev]         switch the current keyboard's layout
  switch DEVICE [next|prev]  switch a named keyboard (default: next)

Options:
  --once               print one status line and exit
  --socket PATH        Hyprland .socket2.sock (default: from
                       $HYPRLAND_INSTANCE_SIGNATURE)
  --interval SECONDS   polling period when no event socket is usable (default: 2)
  -h, --help           this text

stdin: `switch`, `switch next`, `switch prev`, `switch DEVICE [next|prev]`,
one per line, when the scene spawns the worker with an open stdin.

Output keys: device, main, index, keymap, code, layouts, submap,
keyboards[{name,main}].

Exit status: 0 finished; 2 usage error.
EOF
}

die() {
  printf 'kbd: error: %s\n' "$*" >&2
  exit 2
}

HYPRCTL="${PLEAMAR_HYPRCTL:-hyprctl}"
SOCAT="${PLEAMAR_SOCAT:-socat}"
SOCKET_OVERRIDE=""
ONCE=0
INTERVAL=2
COMMAND="status"
SWITCH_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --once)
      ONCE=1
      shift
      ;;
    --socket)
      [ $# -ge 2 ] || die "--socket needs a value"
      SOCKET_OVERRIDE=$2
      shift 2
      ;;
    --interval)
      [ $# -ge 2 ] || die "--interval needs a value"
      INTERVAL=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    status | switch)
      COMMAND=$1
      shift
      while [ $# -gt 0 ]; do
        SWITCH_ARGS+=("$1")
        shift
      done
      ;;
    *)
      die "unknown argument '$1' (see --help)"
      ;;
  esac
done

case "$INTERVAL" in
  '' | *[!0-9]*) die "--interval must be a positive integer (got '$INTERVAL')" ;;
esac
[ "$INTERVAL" -ge 1 ] || die "--interval must be at least 1"

if ! command -v jq > /dev/null 2>&1; then
  printf '{"err":"jq not installed"}\n'
  exit 0
fi
if ! command -v "$HYPRCTL" > /dev/null 2>&1; then
  printf '{"err":"hyprctl not found"}\n'
  exit 0
fi

emit_err() {
  jq -cn --arg e "$1" '{err:$e}' || exit 0
}

emit_ok() {
  printf '{"ok":%s}\n' "$1" || exit 0
}

STATUS_JSON=""
LAST_STATUS=""
ERR_MSG=""

# Query hyprctl for the selected keyboard; sets STATUS_JSON on 0, ERR_MSG on 1.
build_status() {
  local devices_json submap_out submap
  if ! devices_json=$("$HYPRCTL" -j devices 2> /dev/null); then
    ERR_MSG="hyprctl -j devices failed (is Hyprland running?)"
    return 1
  fi
  if ! jq -e . > /dev/null 2>&1 <<< "$devices_json"; then
    ERR_MSG="hyprctl -j devices did not return JSON"
    return 1
  fi
  submap=""
  if submap_out=$("$HYPRCTL" submap 2> /dev/null); then
    submap=$(printf '%s' "$submap_out" | tr -d '\r\n')
    case "$submap" in
      default | reset) submap="" ;;
    esac
  fi
  STATUS_JSON=$(printf '%s' "$devices_json" | jq -c --arg submap "$submap" '
    (.keyboards // []) as $k
    | ([ $k[] | select(.main == true) ]
       + [ $k[] | select((((.name // "") | ascii_downcase | test("virtual")) | not)
                         and ((.layout // "") != "")) ]
       + $k | .[0] // {}) as $sel
    | ([ ($sel.layout // "") | split(",") | .[] | select(length > 0) ]) as $layouts
    | {
        device: ($sel.name // ""),
        main: ($sel.main // false),
        index: ($sel.active_layout_index // 0),
        keymap: ($sel.active_keymap // ""),
        code: ($layouts[($sel.active_layout_index // 0)] // ""),
        layouts: $layouts,
        submap: $submap,
        keyboards: [ $k[] | {name: (.name // ""), main: (.main // false)} ]
      }')
  return 0
}

# Emit a status line, skipping an unchanged one (event bursts repeat state).
maybe_emit_status() {
  if ! build_status; then
    emit_err "$ERR_MSG"
    return 1
  fi
  if [ "$STATUS_JSON" = "$LAST_STATUS" ]; then
    return 0
  fi
  LAST_STATUS=$STATUS_JSON
  emit_ok "$STATUS_JSON"
  return 0
}

# Emit unconditionally (start, after a switch).
emit_status() {
  if ! build_status; then
    emit_err "$ERR_MSG"
    return 1
  fi
  LAST_STATUS=$STATUS_JSON
  emit_ok "$STATUS_JSON"
  return 0
}

do_switch() {
  local device=$1 direction=$2 out
  if ! out=$("$HYPRCTL" switchxkblayout "$device" "$direction" 2>&1); then
    emit_err "hyprctl switchxkblayout $device $direction failed: ${out##*$'\n'}"
    return 1
  fi
  emit_status
  return 0
}

handle_command() {
  local cmd=$1 dev dir
  case "$cmd" in
    "" | "switch" | "switch next")
      do_switch "current" "next"
      ;;
    "switch prev")
      do_switch "current" "prev"
      ;;
    "switch "*)
      read -r dev dir <<< "${cmd#switch }"
      case "$dir" in
        "" | next) dir="next" ;;
        prev) ;;
        *)
          emit_err "switch: unknown direction '$dir' (next|prev)"
          return 1
          ;;
      esac
      do_switch "$dev" "$dir"
      ;;
    *)
      emit_err "unknown command: $cmd"
      return 1
      ;;
  esac
  return 0
}

resolve_socket() {
  local runtime candidate
  if [ -n "$SOCKET_OVERRIDE" ]; then
    if [ -S "$SOCKET_OVERRIDE" ]; then
      printf '%s' "$SOCKET_OVERRIDE"
      return 0
    fi
    return 1
  fi
  runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    candidate="$runtime/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    if [ -S "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
    candidate="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    if [ -S "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
    return 1
  fi
  for candidate in "$runtime"/hypr/*/.socket2.sock /tmp/hypr/*/.socket2.sock; do
    if [ -S "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

STDIN_OPEN=1
poll_stdin() {
  local cmd rc=0
  [ "$STDIN_OPEN" -eq 1 ] || return 0
  IFS= read -r -t 0.05 cmd || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ -n "$cmd" ]; then
      handle_command "$cmd" || true
    fi
    return 0
  fi
  if [ "$rc" -le 128 ]; then
    # End of stdin: the scene closed the command pipe, keep watching events.
    STDIN_OPEN=0
  fi
  return 0
}

handle_event() {
  local name=${1%%>>*}
  case "$name" in
    activelayout | activelayoutv2 | keyboard-layout | keyboard_layout | keyboard | submap | submapv2)
      return 0
      ;;
  esac
  return 1
}

SOCKFEED_PID=""
cleanup() {
  if [ -n "${SOCKFEED_PID:-}" ]; then
    kill "${SOCKFEED_PID:-}" 2> /dev/null || true
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

watch_socket() {
  local sock=$1 line rc matched=0
  if ! command -v "$SOCAT" > /dev/null 2>&1; then
    emit_err "socat not found; polling hyprctl every ${INTERVAL}s instead"
    poll_loop
    return 0
  fi
  coproc SOCKFEED "$SOCAT" -u "UNIX-CONNECT:$sock" -
  while :; do
    line=""
    if IFS= read -r -t 0.2 -u "${SOCKFEED[0]}" line; then
      matched=0
      if handle_event "$line"; then matched=1; fi
      # One layout switch makes Hyprland emit one event per keyboard; read the
      # burst and query hyprctl once.
      while IFS= read -r -t 0.05 -u "${SOCKFEED[0]}" line; do
        if handle_event "$line"; then matched=1; fi
      done
      if [ "$matched" -eq 1 ]; then
        maybe_emit_status || true
      fi
    else
      rc=$?
      if [ "$rc" -le 128 ]; then
        break
      fi
    fi
    poll_stdin
  done
  kill "${SOCKFEED_PID:-}" 2> /dev/null || true
  wait "${SOCKFEED_PID:-}" 2> /dev/null || true
  SOCKFEED_PID=""
  emit_err "hyprland event socket closed"
  return 0
}

poll_loop() {
  while :; do
    sleep "$INTERVAL"
    poll_stdin
    if ! build_status; then
      emit_err "$ERR_MSG"
      continue
    fi
    if [ "$STATUS_JSON" = "$LAST_STATUS" ]; then
      continue
    fi
    LAST_STATUS=$STATUS_JSON
    emit_ok "$STATUS_JSON"
  done
}

if [ "$COMMAND" = "switch" ]; then
  cmd="switch"
  for arg in "${SWITCH_ARGS[@]}"; do
    cmd+=" $arg"
  done
  handle_command "$cmd" || true
  exit 0
fi

initial_ok=1
emit_status || initial_ok=0
if [ "$ONCE" -eq 1 ]; then
  exit 0
fi
if sock=$(resolve_socket); then
  watch_socket "$sock"
elif [ "$initial_ok" -eq 1 ]; then
  emit_err "hyprland event socket not available; polling every ${INTERVAL}s"
  poll_loop
else
  exit 0
fi
