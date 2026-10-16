#!/usr/bin/env bash
# kbd.sh - keyboard-layout worker (pleamar helper; protocol: INTERFACES.md §7).
# Installed as pleamar-kbdlayout; the handshake worker name is "kbdlayout".
#
# A scene spawns this worker while its layout view exists, subscribes to the
# `layout` topic and kills it on close. The status comes from
# `hyprctl -j devices` (main keyboard, layouts, keymap, per-keyboard list) and
# `hyprctl submap`; Hyprland's .socket2.sock pushes activelayout / submap
# events, which are coalesced into one fresh sample. Without a socket, or
# without socat to open it, the worker degrades to polling hyprctl on the
# topic cadence instead of failing. `switch` asks hyprctl switchxkblayout.
#
# Protocol (README.md has the full text):
#   handshake  {"ok":true,"worker":"kbdlayout","version":1,"topics":["layout"]}
#   commands   {"cmd":"subscribe","topic":"layout","interval_ms":5000}
#              {"cmd":"sample"} {"cmd":"set","interval_ms":5000}
#              {"cmd":"switch","device":"current","direction":"next"}
#              {"cmd":"unsubscribe","topic":"layout"} {"cmd":"stop"}
#              The plain line `switch [next|prev|DEVICE [next|prev]]` is also
#              accepted (the Quickshell capsule's wire command).
#   sample     {"ok":true,"worker":"kbdlayout","topic":"layout","t":<ms>,
#              "data":{device,main,index,keymap,code,layouts,submap,
#                      keyboards[{name,main}]}}
#   error      {"ok":false,"worker":"kbdlayout","err":"…","t":<ms>}
#
# `layout` is auto-subscribed at --interval-ms (5000 by default) as a
# heartbeat; socket events emit a sample as soon as the status changes.
# `--once` prints the handshake plus one sample and exits. A closed stdin
# finishes the worker.
#
# Usage: kbd.sh [--once] [--socket PATH] [--interval-ms N]
#               [switch [next|prev|DEVICE [next|prev]]] [--help]
#
# Exit: 0 when stdin closes or on stop; 1 when the worker cannot start.

set -euo pipefail

usage() {
  cat << 'EOF'
kbd.sh - keyboard-layout worker (JSON lines, INTERFACES.md §7)

Usage:
  kbd.sh [options] [command]

Commands:
  (none)                     run as the worker: handshake, subscribe, samples
  switch [next|prev]         switch the current keyboard's layout once
  switch DEVICE [next|prev]  switch a named keyboard once (default: next)

Options:
  --once               print the handshake and one sample, then exit
  --socket PATH        Hyprland .socket2.sock (default: from
                       $HYPRLAND_INSTANCE_SIGNATURE)
  --interval-ms N      heartbeat cadence of the `layout` topic, 100..60000
                       (default: 5000)
  -h, --help           this text

Topic: layout. Commands (JSON): subscribe, unsubscribe, set, sample, switch,
stop; the plain line `switch …` is accepted too.

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
EOF
}

WORKER=kbdlayout

die() {
  printf 'kbd: error: %s\n' "$*" >&2
  exit 2
}

HYPRCTL="${PLEAMAR_HYPRCTL:-hyprctl}"
SOCAT="${PLEAMAR_SOCAT:-socat}"
SOCKET_OVERRIDE=""
ONCE=0
INTERVAL_MS=5000
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
    --interval-ms)
      [ $# -ge 2 ] || die "--interval-ms needs a value"
      INTERVAL_MS=$2
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

case "$INTERVAL_MS" in
  '' | *[!0-9]*) die "--interval-ms must be an integer (got '$INTERVAL_MS')" ;;
esac
[ "$INTERVAL_MS" -ge 100 ] && [ "$INTERVAL_MS" -le 60000 ] || die "--interval-ms must be 100..60000"

# A worker that cannot start says so in the protocol shape and exits non-zero.
start_error() {
  printf '{"ok":false,"worker":"%s","err":"%s"}\n' "$WORKER" "$1"
  exit 1
}

if ! command -v jq > /dev/null 2>&1; then
  start_error "jq not installed"
fi
if ! command -v "$HYPRCTL" > /dev/null 2>&1; then
  start_error "hyprctl not found"
fi

NOW_MS=0
now_ms() {
  local t=$EPOCHREALTIME
  printf -v NOW_MS '%s' "$((10#${t%.*} * 1000 + 10#${t#*.} / 1000))"
}

json_err() {
  jq -cn --arg e "$1" '{ok:false,err:$e}'
}

sample_error() {
  now_ms
  jq -cn --arg w "$WORKER" --arg e "$1" --argjson t "$NOW_MS" '{ok:false,worker:$w,err:$e,t:$t}'
}

ack() {
  printf '{"ok":true,"ack":"%s"}\n' "$1"
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

# Unconditional sample (start, cadence, after a switch).
emit_sample() {
  local now
  now_ms
  now=$NOW_MS
  if ! build_status; then
    sample_error "$ERR_MSG"
    return 0
  fi
  LAST_STATUS=$STATUS_JSON
  printf '{"ok":true,"worker":"%s","topic":"layout","t":%s,"data":%s}\n' "$WORKER" "$now" "$STATUS_JSON"
  return 0
}

# Sample only when the status changed (event bursts repeat state).
emit_changed_sample() {
  local now
  if ! build_status; then
    sample_error "$ERR_MSG"
    return 0
  fi
  if [ "$STATUS_JSON" = "$LAST_STATUS" ]; then
    return 0
  fi
  now_ms
  now=$NOW_MS
  LAST_STATUS=$STATUS_JSON
  printf '{"ok":true,"worker":"%s","topic":"layout","t":%s,"data":%s}\n' "$WORKER" "$now" "$STATUS_JSON"
  return 0
}

do_switch() {
  local device=$1 direction=$2 out
  if ! out=$("$HYPRCTL" switchxkblayout "$device" "$direction" 2>&1); then
    sample_error "hyprctl switchxkblayout $device $direction failed: ${out##*$'\n'}"
    return 1
  fi
  emit_sample
  return 0
}

# Shared by the JSON `switch` command and the plain `switch …` line.
do_switch_words() {
  local dev=$1 dir=$2
  case "$dir" in
    "" | next) dir="next" ;;
    prev) ;;
    *)
      json_err "switch: unknown direction '$dir' (next|prev)"
      return 1
      ;;
  esac
  do_switch "$dev" "$dir"
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

SOCK_FD=""
SOCK_PID=""
SOCK_FIFO=""

cleanup() {
  if [ -n "$SOCK_PID" ]; then
    kill "$SOCK_PID" 2> /dev/null || true
  fi
  if [ -n "$SOCK_FIFO" ]; then
    rm -f -- "$SOCK_FIFO"
  fi
  if [ -n "$SOCK_FD" ]; then
    exec 8<&- 2> /dev/null || true
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

# socat reads the socket and writes into a FIFO that the worker holds open
# read-write (fd 8). The reader never blocks on open and the worker stays in
# charge of the socat child: our exit takes it down with us.
start_socket() {
  local sock
  if [ -n "$SOCK_FD" ]; then
    return 0
  fi
  if ! sock=$(resolve_socket); then
    sample_error "hyprland event socket not available; polling hyprctl"
    return 0
  fi
  if ! command -v "$SOCAT" > /dev/null 2>&1; then
    sample_error "socat not found; polling hyprctl"
    return 0
  fi
  SOCK_FIFO="${TMPDIR:-/tmp}/pleamar-kbd.$$.fifo"
  if ! mkfifo "$SOCK_FIFO" 2> /dev/null; then
    SOCK_FIFO=""
    sample_error "cannot create the event pipe; polling hyprctl"
    return 0
  fi
  "$SOCAT" -u "UNIX-CONNECT:$sock" - > "$SOCK_FIFO" 2> /dev/null &
  SOCK_PID=$!
  exec 8<> "$SOCK_FIFO"
  rm -f -- "$SOCK_FIFO"
  SOCK_FIFO=""
  SOCK_FD=8
  return 0
}

# Reads whatever the socket queued; one sample per burst if the status moved.
drain_socket() {
  local line name matched=0
  [ -n "$SOCK_FD" ] || return 0
  if ! kill -0 "$SOCK_PID" 2> /dev/null; then
    # socat ended (Hyprland stopped): fall back to polling.
    exec 8<&- 2> /dev/null || true
    SOCK_FD=""
    SOCK_PID=""
    sample_error "hyprland event socket closed; polling hyprctl"
    return 0
  fi
  while IFS= read -r -t 0.01 -u "$SOCK_FD" line; do
    name=${line%%>>*}
    case "$name" in
      activelayout | activelayoutv2 | keyboard-layout | keyboard_layout | keyboard | submap | submapv2)
        matched=1
        ;;
    esac
  done
  if [ "$matched" -eq 1 ]; then
    emit_changed_sample
  fi
  return 0
}

KNOWN_TOPICS="layout"
topic_known() {
  case " $KNOWN_TOPICS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

declare -A SUB_INTERVAL=()
declare -A SUB_NEXT=()

handle_command() {
  local line=$1 parts cmd topic interval device direction
  if [[ "$line" != "{"* ]]; then
    # The Quickshell capsule's plain switch line (kept for compatibility).
    local cmd_word rest dev dir
    read -r cmd_word rest <<< "$line"
    if [ "$cmd_word" != "switch" ]; then
      json_err "unknown command: $line"
      return 0
    fi
    read -r dev dir <<< "$rest"
    [ -n "$dev" ] || dev="current"
    [ -n "$dir" ] || dir="next"
    ack switch
    do_switch_words "$dev" "$dir" || true
    return 0
  fi
  parts=$(printf '%s' "$line" | jq -r '[.cmd // "", .topic // "", ((.interval_ms // "") | tostring), (.device // ""), (.direction // "")] | join("|")' 2> /dev/null) || {
    json_err "bad command line"
    return 0
  }
  IFS='|' read -r cmd topic interval device direction <<< "$parts"
  case "$cmd" in
    subscribe)
      if ! topic_known "$topic"; then
        json_err "unknown topic: $topic"
        return 0
      fi
      if [ -z "$interval" ]; then
        interval=${SUB_INTERVAL[$topic]:-$INTERVAL_MS}
      fi
      case "$interval" in
        '' | *[!0-9]*)
          json_err "interval_ms must be an integer"
          return 0
          ;;
      esac
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 60000 ]; then
        json_err "interval_ms must be 100..60000"
        return 0
      fi
      SUB_INTERVAL[$topic]=$interval
      SUB_NEXT[$topic]=0
      ack subscribe
      ;;
    unsubscribe)
      if ! topic_known "$topic"; then
        json_err "unknown topic: $topic"
        return 0
      fi
      unset "SUB_INTERVAL[$topic]" "SUB_NEXT[$topic]" 2> /dev/null || true
      ack unsubscribe
      ;;
    set)
      if [ -z "$interval" ]; then
        json_err "set needs interval_ms"
        return 0
      fi
      case "$interval" in
        *[!0-9]*)
          json_err "interval_ms must be an integer"
          return 0
          ;;
      esac
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 60000 ]; then
        json_err "interval_ms must be 100..60000"
        return 0
      fi
      for topic in "${!SUB_INTERVAL[@]}"; do
        SUB_INTERVAL[$topic]=$interval
      done
      ack set
      ;;
    sample)
      SUB_NEXT[layout]=0
      ack sample
      emit_sample
      ;;
    switch)
      [ -n "$device" ] || device="current"
      [ -n "$direction" ] || direction="next"
      ack switch
      do_switch_words "$device" "$direction" || true
      ;;
    stop)
      ack stop
      exit 0
      ;;
    *)
      json_err "unknown cmd: $cmd"
      ;;
  esac
  return 0
}

emit_due_samples() {
  local topic now=$1
  for topic in "${!SUB_INTERVAL[@]}"; do
    if [ "${SUB_NEXT[$topic]}" -le "$now" ]; then
      SUB_NEXT[$topic]=$((now + SUB_INTERVAL[$topic]))
      emit_sample
    fi
  done
  return 0
}

printf '{"ok":true,"worker":"%s","version":1,"topics":["layout"]}\n' "$WORKER"

SUB_INTERVAL[layout]=$INTERVAL_MS
SUB_NEXT[layout]=0

if [ "$COMMAND" = "switch" ]; then
  cmd="switch"
  for arg in "${SWITCH_ARGS[@]}"; do
    cmd+=" $arg"
  done
  handle_command "$cmd" || true
  exit 0
fi

if [ "$ONCE" -eq 1 ]; then
  emit_sample
  exit 0
fi

start_socket

while :; do
  line=""
  if IFS= read -r -t 0.05 line; then
    if [ -n "$line" ]; then
      handle_command "$line" || true
    fi
  else
    rc=$?
    # End of stdin: the scene closed the command pipe; finish, never outlive it.
    if [ "$rc" -le 128 ]; then
      break
    fi
  fi
  drain_socket
  now_ms
  emit_due_samples "$NOW_MS"
done
exit 0
