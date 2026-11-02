#!/usr/bin/env bash
# Parity harness: run the shipped kbd.sh and the Rust port side by side against
# the same fake hyprctl / fake socat and compare what the pleamar protocol
# promises: the handshake, acks and errors byte for byte, the schema and stable
# values of every sample, the switch argv, CLI errors and --help.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: KBDLAYOUT_BIN / KBD_SH override the paths. Exit 0 only when every check
# passes; each section prints the evidence it compared. This is a host harness
# (it needs the shipped shell worker plus jq and socat); the package check runs
# the hermetic cargo tests instead.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
BIN=${KBDLAYOUT_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-kbdlayout}
SHELL=${KBD_SH:-$(cd -- "$ROOT/../.." && pwd)/files/pleamar/scripts/helpers/kbd.sh}

while [ $# -gt 0 ]; do
  case "$1" in
    --bin)
      BIN=$2
      shift 2
      ;;
    --shell)
      SHELL=$2
      shift 2
      ;;
    *)
      echo "parity: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

[ -x "$BIN" ] || {
  echo "parity: binary not executable: $BIN" >&2
  exit 2
}
[ -r "$SHELL" ] || {
  echo "parity: shell worker not readable: $SHELL" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-kbdlayout-parity.XXXXXX")
LISTENER_PID=""
cleanup() {
  if [ -n "$LISTENER_PID" ]; then
    kill "$LISTENER_PID" 2> /dev/null || true
    wait "$LISTENER_PID" 2> /dev/null || true
  fi
  pkill -P $$ 2> /dev/null || true
  rm -rf -- "$WORK"
}
trap cleanup EXIT

FAKE=$WORK/fake
mkdir -p "$FAKE" "$WORK/runtime"
export XDG_RUNTIME_DIR=$WORK/runtime
export HYPRLAND_INSTANCE_SIGNATURE=pleamar-kbdlayout-parity
export PLEAMAR_HYPRCTL=$FAKE/hyprctl
export PLEAMAR_SOCAT=$FAKE/socat

cat > "$FAKE/hyprctl" << 'SCRIPT'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  -j)
    case "${2:-}" in
      devices)
        if [ -n "${FAKE_CALLS:-}" ]; then
          n=0
          [ -f "$FAKE_CALLS" ] && n=$(cat "$FAKE_CALLS")
          n=$((n + 1))
          printf '%s' "$n" > "$FAKE_CALLS"
          if [ "$n" -le 1 ]; then
            cat "$FAKE_DEVICES_FIRST"
          else
            cat "$FAKE_DEVICES_SECOND"
          fi
        else
          cat "$FAKE_DEVICES"
        fi
        ;;
      *) exit 2 ;;
    esac
    ;;
  submap) cat "$FAKE_SUBMAP" ;;
  switchxkblayout)
    printf '%s %s\n' "${2:-}" "${3:-}" >> "$FAKE_SWITCH_LOG"
    if [ -n "${FAKE_SWITCH_ERROR:-}" ]; then
      if [ "${FAKE_SWITCH_ERROR}" = stdout ]; then
        printf 'first line\nsecond line\n'
      else
        printf 'first line\nsecond line\n' >&2
      fi
      exit 9
    fi
    ;;
  *) exit 2 ;;
esac
SCRIPT

cat > "$FAKE/socat" << 'SCRIPT'
#!/usr/bin/env bash
set -u
case "${FAKE_SOCAT_MODE:-silent}" in
  silent) sleep 5 ;;
  events)
    sleep "${FAKE_SOCAT_DELAY:-0.25}"
    printf 'activelayout>>Russian\n'
    sleep 5
    ;;
  closed) exit 0 ;;
esac
SCRIPT
chmod +x "$FAKE/hyprctl" "$FAKE/socat"

FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  FAILED=1
}
section() { printf '\n== %s ==\n' "$1"; }

# The wall clock is the one field that cannot agree between two runs.
normalize_file() { sed -E 's/"t":[0-9]+/"t":<n>/g' "$1"; }
normalize_stdin() { sed -E 's/"t":[0-9]+/"t":<n>/g'; }

compare_exact() { # label shell-file rust-file
  if diff -u "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

compare_normalized() { # label shell-file rust-file
  if diff -u <(normalize_file "$2") <(normalize_file "$3"); then
    pass "$1"
  else
    fail "$1"
  fi
}

run_both() { # arguments...
  set +e
  bash "$SHELL" "$@" < "$WORK/input" > "$WORK/shell.out" 2> "$WORK/shell.err"
  SHELL_CODE=$?
  "$BIN" "$@" < "$WORK/input" > "$WORK/rust.out" 2> "$WORK/rust.err"
  RUST_CODE=$?
  set -e
}

print_codes() {
  printf '  shell: exit %s\n' "$SHELL_CODE"
  printf '  rust:  exit %s\n' "$RUST_CODE"
}

section "--help"
set +e
bash "$SHELL" --help > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
"$BIN" --help > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ] && diff -u "$WORK/shell.out" "$WORK/rust.out"; then
  pass "--help stdout and exit code are identical (exit $RUST_CODE)"
else
  fail "--help differs"
fi
if [ ! -s "$WORK/shell.err" ] && [ ! -s "$WORK/rust.err" ]; then
  pass "--help writes nothing to stderr"
else
  fail "--help stderr differs"
fi

section "option errors"
check_option() { # label arguments...
  local label=$1
  shift
  set +e
  bash "$SHELL" "$@" < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
  local shell_code=$?
  "$BIN" "$@" < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
  local rust_code=$?
  set -e
  if [ "$shell_code" -eq "$rust_code" ] \
    && diff -u "$WORK/shell.err" "$WORK/rust.err" \
    && diff -u "$WORK/shell.out" "$WORK/rust.out"; then
    pass "option error: $label (exit $rust_code)"
  else
    fail "option error: $label (rust $rust_code, shell $shell_code)"
  fi
}
check_option "interval below minimum" --interval-ms 99
check_option "interval above maximum" --interval-ms 60001
check_option "interval not a number" --interval-ms x
check_option "interval negative" --interval-ms -5
check_option "interval missing value" --interval-ms
check_option "socket missing value" --socket
check_option "unknown option" --bogus
check_option "unknown option after --once" --once --bogus

# bash's own `test` prints an "integer expected" diagnostic before the
# shell's `die()` for a digits string past the 64-bit range. That notice is
# not part of the worker contract, so compare the exit code and the last line.
set +e
bash "$SHELL" --interval-ms 999999999999999999999 < /dev/null \
  > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
"$BIN" --interval-ms 999999999999999999999 < /dev/null \
  > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ] \
  && diff -u "$WORK/shell.out" "$WORK/rust.out" \
  && diff -u <(tail -n1 "$WORK/shell.err") "$WORK/rust.err"; then
  pass "interval overflow: exit code and final error line agree (exit $RUST_CODE)"
else
  fail "interval overflow differs (rust $RUST_CODE, shell $SHELL_CODE)"
fi

section "start error without hyprctl"
set +e
PLEAMAR_HYPRCTL=/nonexistent/hyprctl bash "$SHELL" --once < /dev/null \
  > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
PLEAMAR_HYPRCTL=/nonexistent/hyprctl "$BIN" --once < /dev/null \
  > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ] \
  && diff -u "$WORK/shell.out" "$WORK/rust.out" \
  && diff -u "$WORK/shell.err" "$WORK/rust.err"; then
  pass "start error line and exit code agree (exit $RUST_CODE)"
else
  fail "start error differs (rust $RUST_CODE, shell $SHELL_CODE)"
fi

# Fake compositor fixtures.
DEVICES=$WORK/devices.json
FIRST_DEVICES=$WORK/devices-first.json
SECOND_DEVICES=$WORK/devices-second.json
SUBMAP=$WORK/submap.txt
export FAKE_DEVICES=$DEVICES
export FAKE_DEVICES_FIRST=$FIRST_DEVICES
export FAKE_DEVICES_SECOND=$SECOND_DEVICES
export FAKE_SUBMAP=$SUBMAP
export FAKE_SWITCH_LOG=$WORK/switch.log

cat > "$DEVICES" << 'JSON'
{"keyboards":[
 {"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"},
 {"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0,"active_keymap":"German"},
 {"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":0,"active_keymap":"French"}
]}
JSON
cat > "$FIRST_DEVICES" << 'JSON'
{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":0,"active_keymap":"English"}]}
JSON
cat > "$SECOND_DEVICES" << 'JSON'
{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"}]}
JSON
printf 'default\n' > "$SUBMAP"

section "detection: handshake and one sample"
: > "$WORK/input"
run_both --once
print_codes
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "exit codes agree"
else
  fail "exit codes differ"
fi
compare_normalized "--once handshake and sample are identical after t normalization" \
  "$WORK/shell.out" "$WORK/rust.out"
diff -u <(head -n1 "$WORK/shell.out") <(head -n1 "$WORK/rust.out") > /dev/null \
  && pass "handshake line is byte-identical" \
  || fail "handshake line differs"
printf '  shell: %s\n' "$(sed -n '2p' "$WORK/shell.out")"
printf '  rust:  %s\n' "$(sed -n '2p' "$WORK/rust.out")"

section "detection: selection rules and submap normalization"
check_detection() { # label devices submap
  local label=$1
  cat > "$DEVICES" <<< "$2"
  printf '%s\n' "$3" > "$SUBMAP"
  run_both --once
  if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
    pass "$label (exit $RUST_CODE)"
  else
    fail "$label exit codes (rust $RUST_CODE, shell $SHELL_CODE)"
  fi
  compare_normalized "$label sample data" "$WORK/shell.out" "$WORK/rust.out"
}

check_detection "main keyboard wins" \
  '{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"},{"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0}]}' \
  default
check_detection "virtual keyboard is not chosen" \
  '{"keyboards":[{"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0},{"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":1,"active_keymap":"German"}]}' \
  resize
check_detection "only virtual keyboards fall back to the first" \
  '{"keyboards":[{"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0}]}' \
  reset
check_detection "no keyboards is the empty default" \
  '{"keyboards":[]}' \
  default
check_detection "layout split drops empty parts" \
  '{"keyboards":[{"name":"k","main":true,"layout":",us,,ru,","active_layout_index":0}]}' \
  default

section "switch: argv and sample"
: > "$WORK/input"
set +e
FAKE_SWITCH_LOG=$WORK/shell-switch.log bash "$SHELL" switch kbd-main prev \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_LOG=$WORK/rust-switch.log "$BIN" switch kbd-main prev \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "switch exit codes agree (exit $RUST_CODE)"
else
  fail "switch exit codes differ"
fi
compare_normalized "switch acks and sample are identical" "$WORK/shell.out" "$WORK/rust.out"
compare_exact "switch argv is identical" "$WORK/shell-switch.log" "$WORK/rust-switch.log"
printf '  switch argv: %s\n' "$(cat "$WORK/rust-switch.log")"

set +e
FAKE_SWITCH_LOG=$WORK/shell-default.log bash "$SHELL" switch \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_LOG=$WORK/rust-default.log "$BIN" switch \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
compare_normalized "bare switch defaults to current next" "$WORK/shell.out" "$WORK/rust.out"
compare_exact "bare switch argv is identical" "$WORK/shell-default.log" "$WORK/rust-default.log"

set +e
FAKE_SWITCH_ERROR=1 FAKE_SWITCH_LOG=$WORK/shell-fail.log bash "$SHELL" switch current next \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_ERROR=1 FAKE_SWITCH_LOG=$WORK/rust-fail.log "$BIN" switch current next \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "failed switch exit codes agree (exit $RUST_CODE)"
else
  fail "failed switch exit codes differ"
fi
compare_normalized "failed switch error sample (stderr) is identical" "$WORK/shell.out" "$WORK/rust.out"

set +e
FAKE_SWITCH_ERROR=stdout FAKE_SWITCH_LOG=$WORK/shell-fail-stdout.log bash "$SHELL" switch current next \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_ERROR=stdout FAKE_SWITCH_LOG=$WORK/rust-fail-stdout.log "$BIN" switch current next \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "failed switch on stdout exit codes agree (exit $RUST_CODE)"
else
  fail "failed switch on stdout exit codes differ"
fi
compare_normalized "failed switch error sample (stdout) is identical" "$WORK/shell.out" "$WORK/rust.out"

# `--help` after `switch` is a device word, exactly as in the shell parser.
set +e
FAKE_SWITCH_LOG=$WORK/shell-switch-help.log bash "$SHELL" switch --help \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_LOG=$WORK/rust-switch-help.log "$BIN" switch --help \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "swallowed --help exit codes agree (exit $RUST_CODE)"
else
  fail "swallowed --help exit codes differ"
fi
compare_normalized "swallowed --help output is identical" "$WORK/shell.out" "$WORK/rust.out"
compare_exact "swallowed --help argv is identical" \
  "$WORK/shell-switch-help.log" "$WORK/rust-switch-help.log"

# `status` is the worker command and consumes what follows it.
printf '' > "$WORK/input"
run_both status
compare_normalized "status runs the worker" "$WORK/shell.out" "$WORK/rust.out"

set +e
FAKE_SWITCH_LOG=$WORK/shell-direction.log bash "$SHELL" switch kbd-main sideways \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
FAKE_SWITCH_LOG=$WORK/rust-direction.log "$BIN" switch kbd-main sideways \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "unknown direction exit codes agree (exit $RUST_CODE)"
else
  fail "unknown direction exit codes differ"
fi
compare_normalized "unknown direction error line is identical" "$WORK/shell.out" "$WORK/rust.out"

section "protocol dialogue"
cat > "$WORK/input" << 'DIALOGUE'
{"cmd":"subscribe","topic":"layout","interval_ms":60000}
{"cmd":"sample","topic":"layout"}
{"cmd":"unsubscribe","topic":"layout"}
{"cmd":"sample"}
{"cmd":"switch","device":"kbd-main","direction":"prev"}
{"cmd":"switch","direction":"sideways"}
{"cmd":"subscribe","topic":"nope"}
{"cmd":"subscribe","topic":"layout","interval_ms":100.0}
{"cmd":"subscribe","topic":"layout","interval_ms":"x"}
{"cmd":"set"}
{"cmd":"set","interval_ms":250}
{"cmd":"bogus"}
not json
{}
switch kbd-2 prev
nonsense here

{"cmd":"stop"}
DIALOGUE
run_both --interval-ms 60000 --socket "$WORK/missing.sock"
print_codes
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "dialogue exit codes agree (exit $RUST_CODE)"
else
  fail "dialogue exit codes differ"
fi
grep -v '"topic":"layout"' "$WORK/shell.out" > "$WORK/shell-control"
grep -v '"topic":"layout"' "$WORK/rust.out" > "$WORK/rust-control"
compare_normalized "handshake, acks and error lines are identical" \
  "$WORK/shell-control" "$WORK/rust-control"
grep -c '"topic":"layout"' "$WORK/shell.out" > "$WORK/shell-count" || true
grep -c '"topic":"layout"' "$WORK/rust.out" > "$WORK/rust-count" || true
if [ "$(cat "$WORK/shell-count")" -eq "$(cat "$WORK/rust-count")" ]; then
  pass "sample line count agrees ($(cat "$WORK/rust-count"))"
else
  fail "sample line counts differ (rust $(cat "$WORK/rust-count"), shell $(cat "$WORK/shell-count"))"
fi
grep '"topic":"layout"' "$WORK/shell.out" | normalize_stdin | sort -u > "$WORK/shell-samples"
grep '"topic":"layout"' "$WORK/rust.out" | normalize_stdin | sort -u > "$WORK/rust-samples"
compare_exact "every distinct sample line is identical" "$WORK/shell-samples" "$WORK/rust-samples"

# Socket helper: a real listening UNIX socket for the discovery/fallback paths.
start_listener() { # path
  socat UNIX-LISTEN:"$1",fork /dev/null > /dev/null 2>&1 &
  LISTENER_PID=$!
  for _ in $(seq 1 100); do
    [ -S "$1" ] && return 0
    sleep 0.01
  done
  echo "parity: listener did not appear" >&2
  exit 2
}
stop_listener() {
  if [ -n "$LISTENER_PID" ]; then
    kill "$LISTENER_PID" 2> /dev/null || true
    wait "$LISTENER_PID" 2> /dev/null || true
    LISTENER_PID=""
  fi
}
SOCKET=$WORK/hypr.sock
start_listener "$SOCKET"

section "event-stream fallbacks"
: > "$WORK/input"
set +e
bash "$SHELL" --interval-ms 60000 --socket "$WORK/missing.sock" < /dev/null \
  > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
"$BIN" --interval-ms 60000 --socket "$WORK/missing.sock" < /dev/null \
  > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
compare_normalized "missing socket falls back to polling" "$WORK/shell.out" "$WORK/rust.out"

set +e
PLEAMAR_SOCAT=/nonexistent/socat bash "$SHELL" --interval-ms 60000 --socket "$SOCKET" \
  < /dev/null > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
PLEAMAR_SOCAT=/nonexistent/socat "$BIN" --interval-ms 60000 --socket "$SOCKET" \
  < /dev/null > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "missing socat exit codes agree (exit $RUST_CODE)"
else
  fail "missing socat exit codes differ"
fi
compare_normalized "socat not found falls back to polling" "$WORK/shell.out" "$WORK/rust.out"

TMP_MISSING=$WORK/no-such-tmp
set +e
TMPDIR=$TMP_MISSING bash "$SHELL" --interval-ms 60000 --socket "$SOCKET" < /dev/null \
  > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
TMPDIR=$TMP_MISSING "$BIN" --interval-ms 60000 --socket "$SOCKET" < /dev/null \
  > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "event-pipe failure exit codes agree (exit $RUST_CODE)"
else
  fail "event-pipe failure exit codes differ"
fi
compare_normalized "unusable TMPDIR falls back to polling" "$WORK/shell.out" "$WORK/rust.out"

section "event stream: layout change and close"
hold_stdin() { # seconds
  rm -f "$WORK/in.fifo"
  mkfifo "$WORK/in.fifo"
  (
    exec 9> "$WORK/in.fifo"
    sleep "$1"
  ) &
  HOLDER_PID=$!
}

# A changed layout: the first hyprctl call reports English, later ones Russian;
# the fake socket pushes the event after 250 ms.
TMP_EVENT=$WORK/tmp-event
mkdir -p "$TMP_EVENT"
hold_stdin 0.9
set +e
FAKE_CALLS=$WORK/shell-calls FAKE_SOCAT_MODE=events TMPDIR=$TMP_EVENT \
  bash "$SHELL" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
set -e
wait "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"

TMP_EVENT_RUST=$WORK/tmp-event-rust
mkdir -p "$TMP_EVENT_RUST"
hold_stdin 0.9
set +e
FAKE_CALLS=$WORK/rust-calls FAKE_SOCAT_MODE=events TMPDIR=$TMP_EVENT_RUST \
  "$BIN" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
wait "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"

if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "event-stream exit codes agree (exit $RUST_CODE)"
else
  fail "event-stream exit codes differ"
fi
compare_normalized "event-driven changed sample is identical" "$WORK/shell.out" "$WORK/rust.out"
printf '  shell samples:\n'
grep '"topic":"layout"' "$WORK/shell.out" | sed -E 's/.*"data":(.*)/  \1/' || true
printf '  rust samples:\n'
grep '"topic":"layout"' "$WORK/rust.out" | sed -E 's/.*"data":(.*)/  \1/' || true
if [ "$(grep -c '"topic":"layout"' "$WORK/shell.out")" -eq 2 ] \
  && [ "$(grep -c '"topic":"layout"' "$WORK/rust.out")" -eq 2 ]; then
  pass "both emitted the initial sample and one changed sample"
else
  fail "event sample counts differ from the expected two"
fi
if [ -z "$(find "$TMP_EVENT" -name 'pleamar-kbd.*' -print -quit)" ] \
  && [ -z "$(find "$TMP_EVENT_RUST" -name 'pleamar-kbd.*' -print -quit)" ]; then
  pass "no FIFO left behind after the event stream ends"
else
  fail "FIFO left behind"
fi

# The socket closes under a live worker: one error sample, then polling.
TMP_CLOSED=$WORK/tmp-closed
mkdir -p "$TMP_CLOSED"
hold_stdin 0.7
set +e
FAKE_SOCAT_MODE=closed TMPDIR=$TMP_CLOSED \
  bash "$SHELL" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/shell.out" 2> "$WORK/shell.err"
SHELL_CODE=$?
set -e
wait "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"

TMP_CLOSED_RUST=$WORK/tmp-closed-rust
mkdir -p "$TMP_CLOSED_RUST"
hold_stdin 0.7
set +e
FAKE_SOCAT_MODE=closed TMPDIR=$TMP_CLOSED_RUST \
  "$BIN" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/rust.out" 2> "$WORK/rust.err"
RUST_CODE=$?
set -e
wait "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"

if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "closed socket exit codes agree (exit $RUST_CODE)"
else
  fail "closed socket exit codes differ"
fi
compare_normalized "socket-closed fallback is identical" "$WORK/shell.out" "$WORK/rust.out"

section "closed stdin"
printf '' > "$WORK/input"
run_both --interval-ms 60000
print_codes
if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "closed stdin exits agree ($RUST_CODE)"
else
  fail "closed stdin exits differ"
fi
compare_normalized "closed stdin output is identical" "$WORK/shell.out" "$WORK/rust.out"

section "SIGTERM"
hold_stdin 5
set +e
bash "$SHELL" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/shell.out" 2> "$WORK/shell.err" &
SHELL_PID=$!
sleep 0.4
kill -TERM "$SHELL_PID"
wait "$SHELL_PID"
SHELL_CODE=$?
set -e
kill "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"
wait "$HOLDER_PID" 2> /dev/null || true

hold_stdin 5
set +e
"$BIN" --interval-ms 60000 --socket "$SOCKET" \
  < "$WORK/in.fifo" > "$WORK/rust.out" 2> "$WORK/rust.err" &
RUST_PID=$!
sleep 0.4
kill -TERM "$RUST_PID"
wait "$RUST_PID"
RUST_CODE=$?
set -e
kill "$HOLDER_PID" 2> /dev/null || true
rm -f "$WORK/in.fifo"
wait "$HOLDER_PID" 2> /dev/null || true

if [ "$SHELL_CODE" -eq "$RUST_CODE" ] && [ "$RUST_CODE" -eq 0 ]; then
  pass "SIGTERM exits 0 for both"
else
  fail "SIGTERM exit codes (rust $RUST_CODE, shell $SHELL_CODE)"
fi
compare_normalized "SIGTERM output before exit is identical" "$WORK/shell.out" "$WORK/rust.out"

stop_listener

section "result"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PARITY CHECKS PASSED"
else
  echo "PARITY CHECKS FAILED" >&2
  exit 1
fi
