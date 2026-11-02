#!/usr/bin/env bash
# Parity harness: run the shipped sysmon.sh and the Rust port side by side and
# compare what the pleamar protocol promises.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: SYSMON_BIN / SYSMON_SH override the paths. Exit 0 only when every check
# passes; every section prints the evidence it compared.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
BIN=${SYSMON_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-sysmon}
SHELL=${SYSMON_SH:-$(cd -- "$ROOT/../.." && pwd)/files/pleamar/scripts/helpers/sysmon.sh}

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

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-sysmon-parity.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
GPU=$WORK/gpu
TEMP=$WORK/temp
printf '37\n' > "$GPU"
printf '45000\n' > "$TEMP"
mkdir -p "$WORK/state-rust" "$WORK/state-shell"

FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  FAILED=1
}
section() { printf '\n== %s ==\n' "$1"; }

section "handshake and one sample"
TMPDIR=$WORK/state-rust "$BIN" --once --interval-ms 200 \
  --gpu-path "$GPU" --temp-path "$TEMP" > "$WORK/rust-once.jsonl"
TMPDIR=$WORK/state-shell bash "$SHELL" --once --interval-ms 200 \
  --gpu-path "$GPU" --temp-path "$TEMP" > "$WORK/shell-once.jsonl"

if diff -u <(head -n1 "$WORK/shell-once.jsonl") <(head -n1 "$WORK/rust-once.jsonl"); then
  pass "handshake line is identical"
else
  fail "handshake line differs"
fi

# Recursive key/type schema, sorted, exactly what a consumer relies on.
jq -s -S 'def schema:
  if type == "object" then
    {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
  elif type == "array" then
    {type:"array", items:(map(schema))}
  else type end;
  .[1].data | schema' "$WORK/shell-once.jsonl" > "$WORK/shell-schema.json"
jq -s -S 'def schema:
  if type == "object" then
    {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
  elif type == "array" then
    {type:"array", items:(map(schema))}
  else type end;
  .[1].data | schema' "$WORK/rust-once.jsonl" > "$WORK/rust-schema.json"

if diff -u "$WORK/shell-schema.json" "$WORK/rust-schema.json"; then
  pass "sample schema (keys and value types, recursively) is identical"
else
  fail "sample schema differs"
fi

printf '  shell: %s\n' "$(sed -n '2p' "$WORK/shell-once.jsonl")"
printf '  rust:  %s\n' "$(sed -n '2p' "$WORK/rust-once.jsonl")"

# Stable values must agree; volatile ones only have to stay in range.
if jq -n -e --slurpfile s "$WORK/shell-once.jsonl" --slurpfile r "$WORK/rust-once.jsonl" '
  ($r[1].data) as $x | ($s[1].data) as $y |
  def near(a; b; tolerance): ((a - b) | if . < 0 then -. else . end) <= tolerance;
  ($x.gpu == $y.gpu) and
  ($x.temp == $y.temp) and
  ($x.swap.available == $y.swap.available) and
  (near($x.mem.total_gib; $y.mem.total_gib; 0.02)) and
  (near($x.swap.total_gib; $y.swap.total_gib; 0.02)) and
  (near($x.mem.used_gib; $y.mem.used_gib; 2.0)) and
  (near($x.mem.percent; $y.mem.percent; 5.0)) and
  (near($x.swap.used_gib; $y.swap.used_gib; 0.5)) and
  ($x.cpu.percent >= 0 and $x.cpu.percent <= 100) and
  ($x.disk.read_kibps >= 0 and $x.disk.write_kibps >= 0) and
  ($x.disk.percent >= 0 and $x.disk.percent <= 100) and
  ($x.ts >= ($y.ts - 2) and $x.ts <= ($y.ts + 2))
' > /dev/null; then
  pass "stable values agree (gpu/temp exact, mem/swap totals within 0.02 GiB, mem percent within 5)"
else
  fail "stable sample values differ"
fi

# Byte formatting: after removing the wall clock and the volatile numbers,
# the awk-style separators must be identical.
jq -s -c '.[1].data | del(.ts, .cpu, .disk, .mem.used_gib, .mem.percent, .swap.used_gib, .swap.percent)' \
  "$WORK/shell-once.jsonl" > "$WORK/shell-stable.json"
jq -s -c '.[1].data | del(.ts, .cpu, .disk, .mem.used_gib, .mem.percent, .swap.used_gib, .swap.percent)' \
  "$WORK/rust-once.jsonl" > "$WORK/rust-stable.json"
if diff -u "$WORK/shell-stable.json" "$WORK/rust-stable.json"; then
  pass "stable part of the full sample is byte-identical"
else
  fail "stable part of the full sample differs"
fi

# Separators and key order: with every number replaced the two lines must be
# byte-identical, which is what "the shell's printf spacing" means.
tail -n1 "$WORK/shell-once.jsonl" | sed -E 's/[0-9]+(\.[0-9]+)?/<n>/g' > "$WORK/shell-shape.txt"
tail -n1 "$WORK/rust-once.jsonl" | sed -E 's/[0-9]+(\.[0-9]+)?/<n>/g' > "$WORK/rust-shape.txt"
if diff -u "$WORK/shell-shape.txt" "$WORK/rust-shape.txt"; then
  pass "full sample layout (key order, spaces around commas) is byte-identical"
else
  fail "full sample layout differs"
fi

section "gpu/temp unavailable errors"
TMPDIR=$WORK/state-rust "$BIN" --once --interval-ms 200 --no-gpu --no-temp \
  > "$WORK/rust-none.jsonl"
TMPDIR=$WORK/state-shell bash "$SHELL" --once --interval-ms 200 --no-gpu --no-temp \
  > "$WORK/shell-none.jsonl"
if diff -u \
  <(jq -s -c '.[1].data | {gpu, temp}' "$WORK/shell-none.jsonl") \
  <(jq -s -c '.[1].data | {gpu, temp}' "$WORK/rust-none.jsonl"); then
  pass "--no-gpu/--no-temp error objects are identical"
else
  fail "--no-gpu/--no-temp error objects differ"
fi

section "command dialogue"
cat > "$WORK/dialogue.txt" << 'DIALOGUE'
{"cmd":"subscribe","topic":"cpu","interval_ms":1000}
{"cmd":"set","interval_ms":200}
{"cmd":"unsubscribe","topic":"cpu"}
{"cmd":"subscribe","topic":"nope"}
{"cmd":"subscribe","topic":"cpu","interval_ms":50}
{"cmd":"subscribe","topic":"cpu","interval_ms":"x"}
{"cmd":"subscribe","topic":"cpu","interval_ms":100.0}
{"cmd":"set"}
{"cmd":"set","interval_ms":"x"}
{"cmd":"unsubscribe","topic":"nope"}
{"cmd":"bogus"}
not json
{}
{"cmd":"subscribe"}
   
{"cmd":"sample"}
{"cmd":"stop"}
DIALOGUE
TMPDIR=$WORK/state-rust "$BIN" --interval-ms 60000 --gpu-path "$GPU" --temp-path "$TEMP" \
  < "$WORK/dialogue.txt" > "$WORK/rust-dialogue.txt"
RUST_CODE=$?
TMPDIR=$WORK/state-shell bash "$SHELL" --interval-ms 60000 --gpu-path "$GPU" --temp-path "$TEMP" \
  < "$WORK/dialogue.txt" > "$WORK/shell-dialogue.txt"
SHELL_CODE=$?

if [ "$RUST_CODE" -eq "$SHELL_CODE" ]; then
  pass "exit codes agree ($RUST_CODE)"
else
  fail "exit codes differ (rust $RUST_CODE, shell $SHELL_CODE)"
fi

# Acks and errors exactly, in order; sample lines are compared separately.
grep -v '"topic"' "$WORK/rust-dialogue.txt" > "$WORK/rust-control.txt"
grep -v '"topic"' "$WORK/shell-dialogue.txt" > "$WORK/shell-control.txt"
if diff -u "$WORK/shell-control.txt" "$WORK/rust-control.txt"; then
  pass "handshake, acks and error lines are byte-identical"
else
  fail "ack/error lines differ"
fi

RUST_SAMPLES=$(grep -c '"topic"' "$WORK/rust-dialogue.txt" || true)
SHELL_SAMPLES=$(grep -c '"topic"' "$WORK/shell-dialogue.txt" || true)
if [ "$RUST_SAMPLES" -eq "$SHELL_SAMPLES" ]; then
  pass "sample line count agrees ($RUST_SAMPLES)"
else
  fail "sample line counts differ (rust $RUST_SAMPLES, shell $SHELL_SAMPLES)"
fi

# A subtopic line carries only that topic's object. Schema and the stable
# gpu/temp values are comparable; cpu/disk rates move between two live runs.
jq -s -S 'def schema:
  if type == "object" then
    {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
  elif type == "array" then
    {type:"array", items:(map(schema))}
  else type end;
  [ .[] | select(.topic != null) | {topic, schema:(.data|schema)} ] | sort_by(.topic)' \
  "$WORK/rust-dialogue.txt" > "$WORK/rust-topics.json"
jq -s -S 'def schema:
  if type == "object" then
    {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
  elif type == "array" then
    {type:"array", items:(map(schema))}
  else type end;
  [ .[] | select(.topic != null) | {topic, schema:(.data|schema)} ] | sort_by(.topic)' \
  "$WORK/shell-dialogue.txt" > "$WORK/shell-topics.json"
if diff -u "$WORK/shell-topics.json" "$WORK/rust-topics.json"; then
  pass "subtopic sample schemas are identical"
else
  fail "subtopic sample schemas differ"
fi

jq -c 'select(.topic == "gpu" or .topic == "temp") | {topic, data}' \
  "$WORK/rust-dialogue.txt" > "$WORK/rust-stable-topics.txt"
jq -c 'select(.topic == "gpu" or .topic == "temp") | {topic, data}' \
  "$WORK/shell-dialogue.txt" > "$WORK/shell-stable-topics.txt"
if diff -u "$WORK/shell-stable-topics.txt" "$WORK/rust-stable-topics.txt"; then
  pass "gpu/temp subtopic objects are byte-identical"
else
  fail "gpu/temp subtopic objects differ"
fi

if [ -z "$(find "$WORK/state-rust" -mindepth 1 -print -quit)" ] \
  && [ -z "$(find "$WORK/state-shell" -mindepth 1 -print -quit)" ]; then
  pass "no state files left behind after stop"
else
  fail "state files left behind after stop"
fi

section "stdin closed and stop lifecycle"
TMPDIR=$WORK/state-rust "$BIN" --interval-ms 60000 < /dev/null > /dev/null
[ $? -eq 0 ] && pass "closed stdin exits 0" || fail "closed stdin exit code"
TMPDIR=$WORK/state-shell bash "$SHELL" --interval-ms 60000 < /dev/null > /dev/null
[ $? -eq 0 ] && pass "shell closed stdin exits 0" || fail "shell closed stdin exit code"
if [ -z "$(find "$WORK/state-rust" -mindepth 1 -print -quit)" ] \
  && [ -z "$(find "$WORK/state-shell" -mindepth 1 -print -quit)" ]; then
  pass "no state files left behind after closed stdin"
else
  fail "state files left behind"
fi

section "SIGTERM lifecycle"
for kind in rust shell; do
  mkdir -p "$WORK/sig-$kind"
  FIFO=$WORK/fifo-$kind
  mkfifo "$FIFO"
  if [ "$kind" = rust ]; then
    TMPDIR=$WORK/sig-rust "$BIN" --interval-ms 60000 --gpu-path "$GPU" --temp-path "$TEMP" \
      < "$FIFO" > "$WORK/sig-$kind.out" &
  else
    TMPDIR=$WORK/sig-shell bash "$SHELL" --interval-ms 60000 --gpu-path "$GPU" --temp-path "$TEMP" \
      < "$FIFO" > "$WORK/sig-$kind.out" &
  fi
  PID=$!
  exec 9> "$FIFO"
  sleep 0.3
  STATE_COUNT=$(find "$WORK/sig-$kind" -name 'pleamar-sysmon.*' | wc -l)
  STATE_MODE=$(find "$WORK/sig-$kind" -name 'pleamar-sysmon.*' -exec stat -c '%a' {} \; | head -n1)
  kill -TERM "$PID"
  set +e
  wait "$PID"
  CODE=$?
  set -e
  exec 9>&-
  rm -f "$FIFO"
  if [ "$CODE" -eq 0 ]; then
    pass "$kind SIGTERM exits 0"
  else
    fail "$kind SIGTERM exit code $CODE"
  fi
  if [ "$STATE_COUNT" -eq 1 ] && [ "$STATE_MODE" = 600 ]; then
    pass "$kind state file exists while running, mode 0600"
  else
    fail "$kind state file count/mode ($STATE_COUNT/$STATE_MODE)"
  fi
  if [ -z "$(find "$WORK/sig-$kind" -mindepth 1 -print -quit)" ]; then
    pass "$kind state file removed on SIGTERM"
  else
    fail "$kind state file left after SIGTERM"
  fi
done

section "option errors"
check_option() {
  local label=$1
  shift
  set +e
  "$BIN" "$@" > "$WORK/rust-opt.out" 2> "$WORK/rust-opt.err"
  local rust_code=$?
  bash "$SHELL" "$@" > "$WORK/shell-opt.out" 2> "$WORK/shell-opt.err"
  local shell_code=$?
  set -e
  if [ "$rust_code" -eq "$shell_code" ] && diff -u "$WORK/shell-opt.err" "$WORK/rust-opt.err"; then
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
check_option "io-max zero" --io-max-kibps 0
check_option "io-max not a number" --io-max-kibps x
check_option "io-max missing value" --io-max-kibps
check_option "gpu path missing value" --gpu-path
check_option "temp path missing value" --temp-path
check_option "unknown option" --bogus
check_option "unknown option after --once" --once --bogus

section "--help text"
set +e
"$BIN" --help > "$WORK/rust-help.out" 2> "$WORK/rust-help.err"
RUST_HELP=$?
bash "$SHELL" --help > "$WORK/shell-help.out" 2> "$WORK/shell-help.err"
SHELL_HELP=$?
set -e
if [ "$RUST_HELP" -eq "$SHELL_HELP" ] && diff -u "$WORK/shell-help.out" "$WORK/rust-help.out"; then
  pass "--help stdout and exit code are identical"
else
  fail "--help differs"
fi

section "result"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PARITY CHECKS PASSED"
else
  echo "PARITY CHECKS FAILED" >&2
  exit 1
fi
