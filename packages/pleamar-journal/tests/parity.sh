#!/usr/bin/env bash
# Parity harness: run the shipped journal.sh and the Rust port side by side
# against the same fake journalctl/systemctl and compare every observable:
# exit code, stdout bytes, stderr bytes and the argv each command received.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: PLEAMAR_JOURNAL_BIN / PLEAMAR_JOURNAL_SH override the paths.
#
# Needs bash, jq and coreutils for the shell worker. Nothing here reads the
# host journal, writes outside the temporary directory or uses the network.
#
# One check is a deliberate deviation, reported as such: the shell needs jq
# and wc on PATH, the port counts and renders in-process. The no-jq section
# proves the shell exits 1 while the port still produces the snapshot.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
BIN=${PLEAMAR_JOURNAL_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-journal}
SHELL=${PLEAMAR_JOURNAL_SH:-$REPO/files/pleamar/scripts/helpers/journal.sh}

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
  echo "parity: run cargo build first, or pass --bin PATH" >&2
  exit 2
}
[ -r "$SHELL" ] || {
  echo "parity: shell worker not readable: $SHELL" >&2
  exit 2
}
command -v jq > /dev/null || {
  echo "parity: jq is required by the shell worker and by this harness" >&2
  exit 2
}

REAL_BASH=$(command -v bash)
REAL_ENV=$(command -v env)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-journal-parity.XXXXXX")
cleanup() { rm -rf -- "$WORK"; }
trap cleanup EXIT

FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  FAILED=1
}
section() { printf '\n== %s ==\n' "$1"; }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/journalctl" << 'FAKE'
#!/bin/sh
printf '%s\n' "journalctl $*" >> "$FAKE_ARGV_LOG"
if [ "${FAKE_SIGNAL_PARENT:-0}" = "1" ]; then
  kill -TERM "$PPID"
  sleep 1
  : > "$FAKE_SURVIVED"
  exit 0
fi
case " $* " in
  *" -p err "*)
    printf '%s' "${FAKE_ERR_OUT:-}"
    exit "${FAKE_ERR_CODE:-0}"
    ;;
  *" -p warning "*)
    printf '%s' "${FAKE_WARN_OUT:-}"
    exit "${FAKE_WARN_CODE:-0}"
    ;;
  *)
    printf '%s' "${FAKE_LOG_OUT:-}"
    exit "${FAKE_LOG_CODE:-0}"
    ;;
esac
FAKE
cat > "$WORK/bin/systemctl" << 'FAKE'
#!/bin/sh
printf '%s\n' "systemctl $*" >> "$FAKE_ARGV_LOG"
printf '%s' "${FAKE_SVC_OUT:-}"
exit "${FAKE_SVC_CODE:-0}"
FAKE
chmod +x "$WORK/bin/journalctl" "$WORK/bin/systemctl"

# PATHs without jq (for the deviation check) and without journalctl (for the
# start error), each keeping what the shell worker itself needs.
NO_JQ="$WORK/no-jq"
NO_JOURNALCTL="$WORK/no-journalctl"
mkdir -p "$NO_JQ" "$NO_JOURNALCTL"
for tool in bash env sed wc; do
  ln -s "$(command -v "$tool")" "$NO_JQ/$tool"
done
ln -s "$WORK/bin/journalctl" "$NO_JQ/journalctl"
ln -s "$WORK/bin/systemctl" "$NO_JQ/systemctl"
for tool in bash env jq sed wc; do
  ln -s "$(command -v "$tool")" "$NO_JOURNALCTL/$tool"
done

# PATH entries that exercise `command -v`: a directory with the worker's name
# (not found) and a regular file without the execute bit (found, then the
# pipeline fails when it is started).
PATH_JOURNALCTL_DIR="$WORK/path-journalctl-dir"
PATH_JOURNALCTL_NOEXEC="$WORK/path-journalctl-noexec"
for directory in "$PATH_JOURNALCTL_DIR" "$PATH_JOURNALCTL_NOEXEC"; do
  mkdir -p "$directory"
  for tool in bash env jq sed wc; do
    ln -s "$(command -v "$tool")" "$directory/$tool"
  done
  ln -s "$WORK/bin/systemctl" "$directory/systemctl"
done
mkdir -p "$PATH_JOURNALCTL_DIR/journalctl"
printf '#!/bin/sh\nexit 0\n' > "$PATH_JOURNALCTL_NOEXEC/journalctl"
chmod 644 "$PATH_JOURNALCTL_NOEXEC/journalctl"

reset_fakes() {
  FAKE_LOG_OUT=""
  FAKE_LOG_CODE=0
  FAKE_ERR_OUT=""
  FAKE_ERR_CODE=0
  FAKE_WARN_OUT=""
  FAKE_WARN_CODE=0
  FAKE_SVC_OUT=""
  FAKE_SVC_CODE=0
  CASE_TZ=UTC
  CASE_PATH="$WORK/bin:$PATH"
}

# run_one KIND PREFIX PATH [ARGS...]: a fresh argv log, fakes, pinned TZ.
run_one() {
  local kind=$1 prefix=$2 path=$3
  shift 3
  local -a environment=(
    "FAKE_LOG_OUT=${FAKE_LOG_OUT:-}"
    "FAKE_LOG_CODE=${FAKE_LOG_CODE:-0}"
    "FAKE_ERR_OUT=${FAKE_ERR_OUT:-}"
    "FAKE_ERR_CODE=${FAKE_ERR_CODE:-0}"
    "FAKE_WARN_OUT=${FAKE_WARN_OUT:-}"
    "FAKE_WARN_CODE=${FAKE_WARN_CODE:-0}"
    "FAKE_SVC_OUT=${FAKE_SVC_OUT:-}"
    "FAKE_SVC_CODE=${FAKE_SVC_CODE:-0}"
    "FAKE_ARGV_LOG=$prefix.argv"
    "TZ=${CASE_TZ:-UTC}"
    "PATH=$path"
  )
  : > "$prefix.argv"
  local code=0
  if [ "$kind" = shell ]; then
    "$REAL_ENV" "${environment[@]}" "$REAL_BASH" "$SHELL" "$@" \
      < /dev/null > "$prefix.out" 2> "$prefix.err" || code=$?
  else
    "$REAL_ENV" "${environment[@]}" "$BIN" "$@" \
      < /dev/null > "$prefix.out" 2> "$prefix.err" || code=$?
  fi
  printf '%s\n' "$code" > "$prefix.code"
}

# pair_case LABEL [ARGS...]: shell and port must agree on everything.
pair_case() {
  local label=$1
  shift
  run_one shell "$WORK/shell" "$CASE_PATH" "$@"
  run_one rust "$WORK/rust" "$CASE_PATH" "$@"

  local shell_code rust_code ok=1
  shell_code=$(cat "$WORK/shell.code")
  rust_code=$(cat "$WORK/rust.code")

  if [ "$shell_code" -ne "$rust_code" ]; then
    fail "$label: exit codes differ (shell $shell_code, rust $rust_code)"
    ok=0
  fi
  if ! diff -u "$WORK/shell.out" "$WORK/rust.out" > "$WORK/stdout.diff"; then
    fail "$label: stdout differs"
    sed 's/^/  /' "$WORK/stdout.diff" >&2
    ok=0
  fi
  if ! diff -u "$WORK/shell.err" "$WORK/rust.err" > "$WORK/stderr.diff"; then
    fail "$label: stderr differs"
    sed 's/^/  /' "$WORK/stderr.diff" >&2
    ok=0
  fi
  if ! diff -u "$WORK/shell.argv" "$WORK/rust.argv" > "$WORK/argv.diff"; then
    fail "$label: journalctl/systemctl argv differs"
    sed 's/^/  /' "$WORK/argv.diff" >&2
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    pass "$label (exit $shell_code, $(wc -c < "$WORK/shell.out") bytes stdout, argv identical)"
  fi
}

section "the exact fixture the sibling crates' tests use"
reset_fakes
pair_case "empty journal"

WARN_EDGE=$(
  cat << 'JSONL'
{"__REALTIME_TIMESTAMP":"1730000000123456","_SYSTEMD_UNIT":"x.service","MESSAGE":"hello"}
{"__REALTIME_TIMESTAMP":"0","SYSLOG_IDENTIFIER":"ident","MESSAGE":["line one","line two"]}
{"MESSAGE":"héllo\tnaïve\nsecond"}
{"__REALTIME_TIMESTAMP":"bogus","MESSAGE":42}
{"__REALTIME_TIMESTAMP":"1700000000000000","SYSLOG_IDENTIFIER":false,"MESSAGE":{"b":1,"a":2}}
{"_SYSTEMD_UNIT":5,"MESSAGE":true}
{"MESSAGE":["a",1,null,true,1.50,"b"]}
JSONL
)
FAKE_LOG_OUT=$'one\ntwo\n'
FAKE_ERR_OUT=$'bad\n'
FAKE_SVC_OUT=$'a.service loaded active running A\nb.service loaded active running B\n'
FAKE_WARN_OUT=$WARN_EDGE
pair_case "counts, services and every entry conversion"
reset_fakes

FAKE_LOG_OUT=$'no trailing newline'
FAKE_ERR_OUT=$'a\n\n'
pair_case "wc -l counts newline bytes, not lines"
reset_fakes

FAKE_LOG_OUT=$'x\n'
FAKE_LOG_CODE=1
FAKE_ERR_OUT=$'y\n'
FAKE_ERR_CODE=1
FAKE_SVC_OUT=$'z\n'
FAKE_SVC_CODE=1
pair_case "a failed count command is 0 and the snapshot survives"
reset_fakes

section "the entries pipeline (jq's failure path)"
FAKE_WARN_OUT='{"MESSAGE":"x"}'
FAKE_WARN_CODE=1
pair_case "journalctl fails after a parsable stream: no snapshot, exit 2"
reset_fakes

FAKE_WARN_OUT=$'not json\n'
pair_case "unparsable stream, journalctl success: entries []"
FAKE_WARN_CODE=1
pair_case "unparsable stream, journalctl failure: entries []"
reset_fakes

FAKE_WARN_OUT=""
FAKE_WARN_CODE=1
pair_case "empty stream with a failed command: no snapshot, exit 2"
reset_fakes

FAKE_WARN_OUT=$'1\n'
pair_case "non-object stream element makes the jq filter fail: entries []"
FAKE_WARN_OUT='"text"'
pair_case "a string stream element also fails the filter: entries []"
FAKE_WARN_OUT='{"__REALTIME_TIMESTAMP":"1e300"}'
pair_case "an out-of-range strflocaltime: entries []"
FAKE_WARN_OUT='{"MESSAGE":[["a"],{"b":1}]}'
pair_case "a nested join element fails the filter: entries []"
reset_fakes

section "option handling"
pair_case "defaults"
pair_case "custom --since and --entries" --since -1h --entries 3
pair_case "an empty --since value is forwarded verbatim" --since "" --entries 0
pair_case "unknown argument" --bogus
pair_case "unknown positional" not-an-option
pair_case "missing --since value" --since
pair_case "missing --entries value" --entries
pair_case "--help" --help
pair_case "--help before an unknown argument" --help --bogus
pair_case "unknown argument before --help" --bogus --help

section "timezone"
CASE_TZ=UTC-5
FAKE_WARN_OUT='{"__REALTIME_TIMESTAMP":"1730000000123456","MESSAGE":"x"}'
pair_case "strflocaltime follows TZ (UTC-5 is UTC+5)"
reset_fakes

section "stdin"
printf '%s\n' '{"cmd":"subscribe","topic":"journal","interval_ms":100}' \
  '{"cmd":"sample"}' '{"cmd":"stop"}' > "$WORK/dialogue.txt"
for kind in shell rust; do
  code=0
  if [ "$kind" = shell ]; then
    "$REAL_ENV" "TZ=UTC" "PATH=$WORK/bin:$PATH" "FAKE_ARGV_LOG=$WORK/$kind.argv" \
      "$REAL_BASH" "$SHELL" < "$WORK/dialogue.txt" > "$WORK/$kind.out" 2> "$WORK/$kind.err" || code=$?
  else
    "$REAL_ENV" "TZ=UTC" "PATH=$WORK/bin:$PATH" "FAKE_ARGV_LOG=$WORK/$kind.argv" \
      "$BIN" < "$WORK/dialogue.txt" > "$WORK/$kind.out" 2> "$WORK/$kind.err" || code=$?
  fi
  printf '%s\n' "$code" > "$WORK/$kind.code"
done
if [ "$(cat "$WORK/shell.code")" = "$(cat "$WORK/rust.code")" ] \
  && diff -u "$WORK/shell.out" "$WORK/rust.out" > /dev/null \
  && diff -u "$WORK/shell.err" "$WORK/rust.err" > /dev/null; then
  pass "stdin command lines are ignored by both: one snapshot line, no handshake"
else
  fail "stdin command lines changed one of the workers"
fi
if [ "$(wc -l < "$WORK/rust.out")" -eq 1 ]; then
  pass "the port printed exactly one line (no handshake, no acks)"
else
  fail "the port printed more than the snapshot line"
fi

section "start errors"
# Both PATHs keep bash/env/sed/wc/jq but drop journalctl.
for kind in shell rust; do
  code=0
  if [ "$kind" = shell ]; then
    "$REAL_ENV" "PATH=$NO_JOURNALCTL" "$REAL_BASH" "$SHELL" \
      > "$WORK/missing-$kind.out" 2> "$WORK/missing-$kind.err" || code=$?
  else
    "$REAL_ENV" "PATH=$NO_JOURNALCTL" "$BIN" \
      > "$WORK/missing-$kind.out" 2> "$WORK/missing-$kind.err" || code=$?
  fi
  printf '%s\n' "$code" > "$WORK/missing-$kind.code"
done
if diff -u "$WORK/missing-shell.out" "$WORK/missing-rust.out" > /dev/null \
  && diff -u "$WORK/missing-shell.err" "$WORK/missing-rust.err" > /dev/null \
  && [ "$(cat "$WORK/missing-shell.code")" = "$(cat "$WORK/missing-rust.code")" ]; then
  pass "missing journalctl: both exit $(cat "$WORK/missing-rust.code") with the same stderr"
else
  fail "missing journalctl differs"
fi

section "PATH resolution matches command -v"
reset_fakes
CASE_PATH=$PATH_JOURNALCTL_DIR
pair_case "a directory named journalctl is not found"
CASE_PATH=$PATH_JOURNALCTL_NOEXEC
pair_case "a non-executable journalctl is found, then the pipeline fails"
reset_fakes

section "deliberate deviation: jq and wc are gone"
shell_code=0
"$REAL_ENV" "PATH=$NO_JQ" "$REAL_BASH" "$SHELL" \
  > "$WORK/nojq-shell.out" 2> "$WORK/nojq-shell.err" || shell_code=$?
rust_code=0
"$REAL_ENV" "PATH=$NO_JQ" "$BIN" \
  > "$WORK/nojq-rust.out" 2> "$WORK/nojq-rust.err" || rust_code=$?
if [ "$shell_code" -eq 1 ] \
  && [ "$(cat "$WORK/nojq-shell.err")" = "journal: jq not found" ] \
  && [ "$rust_code" -eq 0 ] \
  && [ "$(cat "$WORK/nojq-rust.out")" = '{"ok":true,"worker":"journal","version":1,"data":{"logs":0,"errors":0,"services":0,"entries":[]}}' ]; then
  pass "without jq: shell exits 1 ('journal: jq not found'), the port still snapshots"
else
  fail "no-jq deviation check (shell $shell_code, rust $rust_code)"
fi

section "SIGTERM during journalctl"
for kind in shell rust; do
  survived="$WORK/survived-$kind"
  rm -f "$survived"
  environment=(
    "FAKE_ARGV_LOG=$WORK/sig-$kind.argv"
    "FAKE_SIGNAL_PARENT=1"
    "FAKE_SURVIVED=$survived"
    "TZ=UTC"
    "PATH=$WORK/bin:$PATH"
  )
  : > "$WORK/sig-$kind.argv"
  if [ "$kind" = shell ]; then
    "$REAL_ENV" "${environment[@]}" "$REAL_BASH" "$SHELL" \
      > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  else
    "$REAL_ENV" "${environment[@]}" "$BIN" \
      > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  fi
  pid=$!
  set +e
  wait "$pid"
  printf '%s\n' "$?" > "$WORK/sig-$kind.code"
  set -e
  sleep 1.3
  if [ -e "$survived" ]; then
    printf 'present\n' > "$WORK/sig-$kind.marker"
  else
    printf 'absent\n' > "$WORK/sig-$kind.marker"
  fi
  printf '  %s: status %s, child marker %s\n' \
    "$kind" "$(cat "$WORK/sig-$kind.code")" "$(cat "$WORK/sig-$kind.marker")"
done
if [ "$(cat "$WORK/sig-shell.code")" = "$(cat "$WORK/sig-rust.code")" ]; then
  pass "SIGTERM: both workers report status $(cat "$WORK/sig-rust.code")"
else
  fail "SIGTERM status differs (shell $(cat "$WORK/sig-shell.code"), rust $(cat "$WORK/sig-rust.code"))"
fi
if [ "$(cat "$WORK/sig-shell.marker")" = "present" ] \
  && [ "$(cat "$WORK/sig-rust.marker")" = "absent" ]; then
  pass "SIGTERM: the shell leaks its journalctl child, the port reaps it (expected improvement)"
elif [ "$(cat "$WORK/sig-shell.marker")" = "absent" ] \
  && [ "$(cat "$WORK/sig-rust.marker")" = "absent" ]; then
  pass "SIGTERM: both reaped their child in this run"
else
  fail "SIGTERM child cleanup (shell $(cat "$WORK/sig-shell.marker"), rust $(cat "$WORK/sig-rust.marker"))"
fi

section "result"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PARITY CHECKS PASSED"
else
  echo "PARITY CHECKS FAILED" >&2
  exit 1
fi
