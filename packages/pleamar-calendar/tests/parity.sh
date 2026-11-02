#!/usr/bin/env bash
# Parity harness: run the shipped calendar.sh and the Rust port side by side
# against the same fake khal and the same local HTTP mocks, and compare what
# the pleamar protocol, the data schema, the cache documents and the CLI
# promise.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: PLEAMAR_CALENDAR_BIN / PLEAMAR_CALENDAR_SH override the paths.
#
# Needs bash, jq and curl for the shell worker, python3 for the mocks. Exit 0
# only when every check passes; each section prints the evidence it compared.
# Nothing here talks to the internet.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
REPO=$(cd -- "$ROOT/../.." && pwd)
BIN=${PLEAMAR_CALENDAR_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-calendar}
SHELL=${PLEAMAR_CALENDAR_SH:-$REPO/files/pleamar/scripts/helpers/calendar.sh}

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
for tool in python3 jq curl bash; do
  command -v "$tool" > /dev/null || {
    echo "parity: $tool is required" >&2
    exit 2
  }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-calendar-parity.XXXXXX")
MOCK_PID=""
MOCK_BASE="http://127.0.0.1:1"

cleanup() {
  if [ -n "$MOCK_PID" ]; then
    kill "$MOCK_PID" 2> /dev/null || true
    wait "$MOCK_PID" 2> /dev/null || true
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT

FAILED=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1" >&2
  FAILED=1
}
section() { printf '\n== %s ==\n' "$1"; }

# The fake khal is a copy of fake_khal.sh with the exec bit.
mkdir -p "$WORK/bin"
cp "$HERE/fake_khal.sh" "$WORK/bin/khal"
chmod +x "$WORK/bin/khal"

# khal's normal answer: a header, a plain event, a title with pipes, an EU date
# the worker must normalise, and a line that is not an event.
DEFAULT_KHAL_TEXT=$'Today, 2026-11-05\n2026-11-05|09:00|Standup|Work\n2026-11-06| 18:30 |Concert|a|b|Personal\n05.11.2026|10:00|Coloured|Cal\nnot an event\n'
export FAKE_KHAL_TEXT="$DEFAULT_KHAL_TEXT"

start_mock() {
  stop_mock
  rm -f "$WORK/port"
  : > "$WORK/requests.jsonl"
  python3 "$HERE/mock_http.py" --port-file "$WORK/port" --log "$WORK/requests.jsonl" "$@" &
  MOCK_PID=$!
  for _ in $(seq 1 300); do
    [ -s "$WORK/port" ] && break
    sleep 0.02
  done
  [ -s "$WORK/port" ] || {
    echo "parity: the mock HTTP server did not start" >&2
    exit 2
  }
  MOCK_BASE="http://127.0.0.1:$(cat "$WORK/port")"
}

stop_mock() {
  if [ -n "$MOCK_PID" ]; then
    kill "$MOCK_PID" 2> /dev/null || true
    wait "$MOCK_PID" 2> /dev/null || true
    MOCK_PID=""
  fi
}

reset_kind() {
  local kind=$1
  rm -rf "$WORK/cache-$kind" "$WORK/tmp-$kind" "$WORK/home-$kind" \
    "$WORK/data-$kind" "$WORK/xdg-$kind"
  mkdir -p "$WORK/cache-$kind" "$WORK/tmp-$kind" "$WORK/home-$kind" \
    "$WORK/data-$kind" "$WORK/xdg-$kind"
  : > "$WORK/khal-$kind.log"
}

begin_pair() {
  reset_kind shell
  reset_kind rust
}

# run_kind KIND OUT [WORKER ARG...] — both workers get the same caches, XDG
# dirs, TMPDIR and fake khal; stderr goes next to the output file.
run_kind() {
  local kind=$1 out=$2
  shift 2
  local common=(--cache-dir "$WORK/cache-$kind"
    --holidays-base "$MOCK_BASE/api/v3"
    --workdays-base "$MOCK_BASE/api/getdata")
  local envargs=(
    "PATH=$WORK/bin:$PATH"
    "TMPDIR=$WORK/tmp-$kind"
    "HOME=$WORK/home-$kind"
    "XDG_DATA_HOME=$WORK/data-$kind"
    "XDG_CACHE_HOME=$WORK/xdg-$kind"
    "FAKE_KHAL_LOG=$WORK/khal-$kind.log"
  )
  if [ "$kind" = shell ]; then
    env "${envargs[@]}" bash "$SHELL" "${common[@]}" "$@" > "$out" 2> "$out.err"
  else
    env "${envargs[@]}" "$BIN" "${common[@]}" "$@" > "$out" 2> "$out.err"
  fi
}

last_byte() {
  tail -c 1 "$1" | od -An -tu1 | tr -d ' \n'
}

cache_names() {
  local kind=$1 path
  for path in "$WORK/cache-$kind"/*; do
    [ -e "$path" ] && basename -- "$path"
  done | sort
}

# compare_pair LABEL — the protocol line, its schema, the requests, khal argv,
# the caches and the exit code.
compare_pair() {
  local label=$1
  if [ "$SHELL_CODE" -ne "$RUST_CODE" ]; then
    fail "$label: exit codes differ (shell $SHELL_CODE, rust $RUST_CODE)"
  elif [ "$SHELL_CODE" -ne 0 ]; then
    fail "$label: --once must finish 0 (both exited $SHELL_CODE)"
  else
    pass "$label: both workers exit 0"
  fi

  if diff -u <(head -n1 "$WORK/shell.out") <(head -n1 "$WORK/rust.out") > /dev/null; then
    pass "$label: handshake is byte-identical"
  else
    fail "$label: handshake differs"
  fi

  printf '  shell: %s\n' "$(sed -n '2p' "$WORK/shell.out")"
  printf '  rust:  %s\n' "$(sed -n '2p' "$WORK/rust.out")"

  jq -s -c 'if .[1].ok == true then (.[1].data | del(.fetched_at, .age_s)) else (.[1] | del(.t)) end' \
    "$WORK/shell.out" > "$WORK/shell-normal.json"
  jq -s -c 'if .[1].ok == true then (.[1].data | del(.fetched_at, .age_s)) else (.[1] | del(.t)) end' \
    "$WORK/rust.out" > "$WORK/rust-normal.json"
  if diff -u "$WORK/shell-normal.json" "$WORK/rust-normal.json"; then
    pass "$label: payload (or error line) is byte-identical after removing the clock"
  else
    fail "$label: payload differs"
  fi

  jq -s -c '
    def schema:
      if type == "object" then
        {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
      elif type == "array" then {type:"array", items:(map(schema))}
      else type end;
    if .[1].ok == true then (.[1].data | schema) else null end' \
    "$WORK/shell.out" > "$WORK/shell-schema.json"
  jq -s -c '
    def schema:
      if type == "object" then
        {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
      elif type == "array" then {type:"array", items:(map(schema))}
      else type end;
    if .[1].ok == true then (.[1].data | schema) else null end' \
    "$WORK/rust.out" > "$WORK/rust-schema.json"
  if diff -u "$WORK/shell-schema.json" "$WORK/rust-schema.json" > /dev/null; then
    pass "$label: payload schema (keys and types, recursively) is identical"
  else
    fail "$label: payload schema differs"
  fi

  jq -c '{method, path, ua}' "$WORK/requests-shell.jsonl" > "$WORK/requests-shell.norm" 2> /dev/null || :
  jq -c '{method, path, ua}' "$WORK/requests-rust.jsonl" > "$WORK/requests-rust.norm" 2> /dev/null || :
  if diff -u "$WORK/requests-shell.norm" "$WORK/requests-rust.norm"; then
    pass "$label: request URLs (path and User-Agent) are identical"
  else
    fail "$label: requests differ"
  fi

  if diff -u "$WORK/khal-shell.log" "$WORK/khal-rust.log"; then
    pass "$label: khal argv sequence is identical"
  else
    fail "$label: khal invocations differ"
  fi

  if ! diff -u <(cache_names shell) <(cache_names rust); then
    fail "$label: the two workers wrote different cache file sets"
    return
  fi
  if [ -z "$(cache_names shell)" ]; then
    pass "$label: both workers wrote no cache"
  fi
  local name
  for name in $(cache_names shell); do
    case "$name" in
      calendar-*.json)
        if diff -u <(jq -c 'del(.fetched_at)' "$WORK/cache-shell/$name") \
          <(jq -c 'del(.fetched_at)' "$WORK/cache-rust/$name") > /dev/null; then
          pass "$label: $name shape is identical (order, literals, ${name#calendar-})"
        else
          fail "$label: $name differs"
        fi
        if [ "$(last_byte "$WORK/cache-shell/$name")" = 10 ] \
          && [ "$(last_byte "$WORK/cache-rust/$name")" = 10 ]; then
          pass "$label: $name ends with the jq newline"
        else
          fail "$label: $name trailing newline differs"
        fi
        ;;
      holidays-*.json | workdays-*.txt)
        if cmp -s "$WORK/cache-shell/$name" "$WORK/cache-rust/$name"; then
          pass "$label: $name is byte-identical"
        else
          fail "$label: $name bytes differ"
        fi
        ;;
      *)
        fail "$label: unexpected cache file $name"
        ;;
    esac
    if [ "$(stat -c '%a' "$WORK/cache-shell/$name")" = "$(stat -c '%a' "$WORK/cache-rust/$name")" ]; then
      pass "$label: $name mode agrees"
    else
      fail "$label: $name modes differ"
    fi
  done
}

# once_pair LABEL [MOCK ARGS] -- [WORKER ARGS] — one --once run per worker,
# each against a fresh mock so the request logs can be compared.
once_pair() {
  local label=$1
  shift
  local mock_args=() worker_args=()
  local target=mock
  for argument in "$@"; do
    if [ "$argument" = "--" ] && [ "$target" = mock ]; then
      target=worker
      continue
    fi
    if [ "$target" = mock ]; then mock_args+=("$argument"); else worker_args+=("$argument"); fi
  done

  start_mock "${mock_args[@]}"
  SHELL_CODE=0
  run_kind shell "$WORK/shell.out" --once "${worker_args[@]}" || SHELL_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/requests-shell.jsonl"
  stop_mock

  start_mock "${mock_args[@]}"
  RUST_CODE=0
  run_kind rust "$WORK/rust.out" --once "${worker_args[@]}" || RUST_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/requests-rust.jsonl"
  stop_mock

  compare_pair "$label"
}

seed_calendar() {
  local fetched=$1
  local kind document
  document=$(printf '%s' '{"month":"2026-11","first":"2026-11-01","last":"2026-11-30","events":[{"date":"2026-11-05","time":"09:00","title":"Cached event","calendar":"Work"}],"holidays":[{"date":"2026-11-04","name":"Cached holiday","name_en":"Cached holiday"}],"holidays_error":null,"workdays":[],"workdays_error":null,"fetched_at":'"$fetched"',"cached":true}')
  for kind in shell rust; do
    mkdir -p "$WORK/cache-$kind"
    printf '%s\n' "$document" > "$WORK/cache-$kind/calendar-2026-11.json"
  done
}

seed_source_caches() {
  local kind
  for kind in shell rust; do
    mkdir -p "$WORK/cache-$kind"
    printf '%s\n' '[{"date":"2026-11-02","localName":"From cache","name":"Cached"}]' \
      > "$WORK/cache-$kind/holidays-2026-RU.json"
    printf '%s' '100000000000000000000000000000' \
      > "$WORK/cache-$kind/workdays-2026-2026-11-RU.txt"
  done
}

seed_pills() {
  local document=$1 kind
  for kind in shell rust; do
    mkdir -p "$WORK/data-$kind/pleamar/Pill"
    printf '%s' "$document" > "$WORK/data-$kind/pleamar/Pill/state.json"
  done
}

clear_calendar_cache() {
  local kind
  for kind in shell rust; do
    rm -f "$WORK/cache-$kind"/calendar-*.json
  done
}

section "fresh fetch (khal, holidays, production calendar)"
begin_pair
once_pair "fresh" -- --month 2026-11 --country RU

section "no --country means no HTTP sources"
begin_pair
once_pair "no-country" -- --month 2026-11
if [ ! -s "$WORK/requests-shell.jsonl" ] && [ ! -s "$WORK/requests-rust.jsonl" ]; then
  pass "no-country: neither worker touched the network"
else
  fail "no-country: a worker made a request"
fi

section "default month (date +%Y-%m vs the local clock)"
begin_pair
once_pair "default-month" --

section "month variants"
begin_pair
once_pair "month-day-form" -- --month 2026-11-15
begin_pair
once_pair "leap-february" -- --month 2024-02

section "khal failure (stderr text / empty stderr)"
export FAKE_KHAL_MODE=fail FAKE_KHAL_STDERR='khal: bad config' FAKE_KHAL_CODE=3
begin_pair
once_pair "khal-fail" -- --month 2026-11
export FAKE_KHAL_STDERR='' FAKE_KHAL_CODE=7
begin_pair
once_pair "khal-exit" -- --month 2026-11
unset FAKE_KHAL_MODE FAKE_KHAL_STDERR FAKE_KHAL_CODE

section "khal ISO rejection retries in dd.mm.yyyy"
export FAKE_KHAL_MODE=retry FAKE_KHAL_TEXT='05.11.2026|09:00|EU event|Work'
begin_pair
once_pair "khal-retry" -- --month 2026-11
export FAKE_KHAL_MODE=critical-first
begin_pair
once_pair "khal-critical" -- --month 2026-11
unset FAKE_KHAL_MODE
export FAKE_KHAL_TEXT="$DEFAULT_KHAL_TEXT"

section "HTTP failures are error fields, not failed samples"
begin_pair
once_pair "http-500" --holidays-status 500 --workdays-status 500 -- \
  --month 2026-11 --country RU
begin_pair
once_pair "workday-503" --workdays-status 503 -- --month 2026-11 --country RU

section "payload cache hit (no khal, no network)"
begin_pair
seed_calendar "$(date +%s)"
seed_source_caches
start_mock
SHELL_CODE=0
run_kind shell "$WORK/shell.out" --once --month 2026-11 --country RU || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/requests-shell.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_kind rust "$WORK/rust.out" --once --month 2026-11 --country RU || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/requests-rust.jsonl"
stop_mock
compare_pair "cache-hit"
if [ "$(jq -r '.data.cached' "$WORK/shell.out" | sed -n '2p')" = true ] \
  && [ "$(jq -r '.data.cached' "$WORK/rust.out" | sed -n '2p')" = true ]; then
  pass "cache-hit: both samples say cached:true"
else
  fail "cache-hit: a worker did not serve the cache"
fi
if [ ! -s "$WORK/requests-shell.jsonl" ] && [ ! -s "$WORK/requests-rust.jsonl" ]; then
  pass "cache-hit: neither worker touched the network"
else
  fail "cache-hit: a worker went to the network"
fi

section "stale payload cache is refetched"
begin_pair
seed_calendar "$(($(date +%s) - 200))"
once_pair "cache-stale" -- --month 2026-11 --country RU

section "a cache for another month / broken JSON is refetched"
begin_pair
printf '%s\n' '{"month":"2026-10","first":"F","last":"L","events":[],"holidays":[],"holidays_error":null,"workdays":[],"workdays_error":null,"fetched_at":'"$(date +%s)"',"cached":true}' \
  > "$WORK/cache-shell/calendar-2026-11.json"
cp "$WORK/cache-shell/calendar-2026-11.json" "$WORK/cache-rust/calendar-2026-11.json"
once_pair "cache-wrong-month" -- --month 2026-11 --country RU
begin_pair
printf 'not json\n' > "$WORK/cache-shell/calendar-2026-11.json"
printf 'not json\n' > "$WORK/cache-rust/calendar-2026-11.json"
once_pair "cache-broken" -- --month 2026-11 --country RU

section "24 h source caches"
begin_pair
seed_source_caches
once_pair "source-cache-hit" -- --month 2026-11 --country RU
if [ ! -s "$WORK/requests-shell.jsonl" ] && [ ! -s "$WORK/requests-rust.jsonl" ]; then
  pass "source-cache-hit: neither worker touched the network"
else
  fail "source-cache-hit: a worker went to the network"
fi
begin_pair
seed_source_caches
touch -d '@0' "$WORK/cache-shell/holidays-2026-RU.json" \
  "$WORK/cache-rust/holidays-2026-RU.json" \
  "$WORK/cache-shell/workdays-2026-2026-11-RU.txt" \
  "$WORK/cache-rust/workdays-2026-2026-11-RU.txt"
once_pair "source-cache-stale" -- --month 2026-11 --country RU

section "pill tracker state"
begin_pair
seed_pills '{"today":"2026-11-03","taken":true,"history":[{"date":"2026-11-02","taken":true},{"date":"2026-11-01","taken":false}]}'
once_pair "pills" -- --month 2026-11
begin_pair
seed_pills 'not json'
once_pair "pills-broken" -- --month 2026-11

section "command dialogue"
cat > "$WORK/dialogue.txt" << 'DIALOGUE'
{"cmd":"subscribe","topic":"calendar","interval_ms":3600000}
{"cmd":"sample","month":"2026-12"}
{"cmd":"set","interval_ms":250}
{"cmd":"bogus"}
not json
null
{"cmd":"subscribe","topic":"calendar2"}
{"cmd":"subscribe","topic":"calendar","interval_ms":50}
{"cmd":"subscribe","topic":"calendar","interval_ms":"x"}
{"cmd":"sample","month":"2026-13"}
{"cmd":"sample","month":"2026-11-15"}
{"cmd":"set"}
{"cmd":"unsubscribe","topic":"calendar"}
{"cmd":"sample"}
{"cmd":"subscribe","topic":"calendar"}
{"cmd":"subscribe","topic":"calendar","month":"2026-09"}
{"cmd":"stop"}
DIALOGUE
# A final line without a newline: bash's read fails at EOF and the shell never
# handles it; the port drops the partial line the same way.
printf '%s' '{"cmd":"stop"}' >> "$WORK/dialogue.txt"

begin_pair
start_mock
SHELL_CODE=0
run_kind shell "$WORK/shell-dialogue.out" --month 2026-11 --country RU \
  < "$WORK/dialogue.txt" || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/requests-shell.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_kind rust "$WORK/rust-dialogue.out" --month 2026-11 --country RU \
  < "$WORK/dialogue.txt" || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/requests-rust.jsonl"
stop_mock

if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "dialogue: exit codes agree ($SHELL_CODE)"
else
  fail "dialogue: exit codes differ (shell $SHELL_CODE, rust $RUST_CODE)"
fi

jq -c 'select(has("topic") | not)' "$WORK/shell-dialogue.out" > "$WORK/shell-control.jsonl"
jq -c 'select(has("topic") | not)' "$WORK/rust-dialogue.out" > "$WORK/rust-control.jsonl"
if diff -u "$WORK/shell-control.jsonl" "$WORK/rust-control.jsonl"; then
  pass "dialogue: handshake, acks and error lines are byte-identical"
else
  fail "dialogue: control lines differ"
fi

SHELL_SAMPLES=$(jq -c 'select(.topic)' "$WORK/shell-dialogue.out" | wc -l)
RUST_SAMPLES=$(jq -c 'select(.topic)' "$WORK/rust-dialogue.out" | wc -l)
if [ "$SHELL_SAMPLES" -eq "$RUST_SAMPLES" ]; then
  pass "dialogue: sample line count agrees ($SHELL_SAMPLES)"
else
  fail "dialogue: sample counts differ (shell $SHELL_SAMPLES, rust $RUST_SAMPLES)"
fi

jq -c 'select(.topic) | .data | del(.fetched_at, .age_s)' \
  "$WORK/shell-dialogue.out" > "$WORK/shell-samples.norm"
jq -c 'select(.topic) | .data | del(.fetched_at, .age_s)' \
  "$WORK/rust-dialogue.out" > "$WORK/rust-samples.norm"
if diff -u "$WORK/shell-samples.norm" "$WORK/rust-samples.norm"; then
  pass "dialogue: sample payloads are byte-identical after removing the clock"
else
  fail "dialogue: sample payloads differ"
fi

jq -c '{method, path, ua}' "$WORK/requests-shell.jsonl" > "$WORK/requests-shell.norm"
jq -c '{method, path, ua}' "$WORK/requests-rust.jsonl" > "$WORK/requests-rust.norm"
if diff -u "$WORK/requests-shell.norm" "$WORK/requests-rust.norm"; then
  pass "dialogue: request URLs are identical"
else
  fail "dialogue: request URLs differ"
fi

if diff -u "$WORK/khal-shell.log" "$WORK/khal-rust.log"; then
  pass "dialogue: khal argv sequence is identical"
else
  fail "dialogue: khal invocations differ"
fi

if diff -u <(cache_names shell) <(cache_names rust); then
  pass "dialogue: the two workers wrote the same cache file set"
else
  fail "dialogue: cache file sets differ"
fi
for name in $(cache_names shell); do
  case "$name" in
    calendar-*.json)
      if diff -u <(jq -c 'del(.fetched_at)' "$WORK/cache-shell/$name") \
        <(jq -c 'del(.fetched_at)' "$WORK/cache-rust/$name") > /dev/null; then
        pass "dialogue: $name shape is identical"
      else
        fail "dialogue: $name differs"
      fi
      ;;
    *)
      if cmp -s "$WORK/cache-shell/$name" "$WORK/cache-rust/$name"; then
        pass "dialogue: $name is byte-identical"
      else
        fail "dialogue: $name bytes differ"
      fi
      ;;
  esac
done

section "option errors (stdout, stderr, exit code)"
check_option() {
  local label=$1
  shift
  set +e
  TMPDIR="$WORK" PATH="$WORK/bin:$PATH" "$BIN" "$@" > "$WORK/rust-opt.out" 2> "$WORK/rust-opt.err"
  local rust_code=$?
  TMPDIR="$WORK" PATH="$WORK/bin:$PATH" bash "$SHELL" "$@" > "$WORK/shell-opt.out" 2> "$WORK/shell-opt.err"
  local shell_code=$?
  set -e
  if [ "$rust_code" -eq "$shell_code" ] \
    && diff -u "$WORK/shell-opt.out" "$WORK/rust-opt.out" \
    && diff -u "$WORK/shell-opt.err" "$WORK/rust-opt.err"; then
    pass "option error: $label (exit $rust_code)"
  else
    fail "option error: $label (rust $rust_code, shell $shell_code)"
  fi
}
check_option "month without value" --month
check_option "country without value" --country
check_option "cache dir without value" --cache-dir
check_option "interval without value" --interval-ms
check_option "workdays base without value" --workdays-base
check_option "holidays base without value" --holidays-base
check_option "unknown option" --bogus
check_option "country too long" --country RUS
check_option "interval not a number" --interval-ms x
check_option "interval below minimum" --interval-ms 99
check_option "month not a month" --month 2026-13
check_option "month without a day digit" --month 2026-1

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

section "closed stdin"
begin_pair
start_mock
SHELL_CODE=0
run_kind shell "$WORK/shell-closed.out" --month 2026-11 < /dev/null || SHELL_CODE=$?
RUST_CODE=0
run_kind rust "$WORK/rust-closed.out" --month 2026-11 < /dev/null || RUST_CODE=$?
stop_mock
if [ "$SHELL_CODE" -eq 0 ] && [ "$RUST_CODE" -eq 0 ]; then
  pass "closed stdin exits 0 for both workers"
else
  fail "closed stdin exit codes (shell $SHELL_CODE, rust $RUST_CODE)"
fi
if diff -u "$WORK/shell-closed.out" "$WORK/rust-closed.out"; then
  pass "closed stdin writes the same lines (handshake only)"
else
  fail "closed stdin output differs"
fi

section "SIGTERM during an in-flight request"
sigterm_case() {
  local kind=$1
  start_mock --delay 5 --delay-route holidays
  reset_kind "$kind"
  rm -f "$WORK/fifo-$kind"
  mkfifo "$WORK/fifo-$kind"
  local common=(--cache-dir "$WORK/cache-$kind"
    --holidays-base "$MOCK_BASE/api/v3"
    --workdays-base "$MOCK_BASE/api/getdata")
  local envargs=(
    "PATH=$WORK/bin:$PATH"
    "TMPDIR=$WORK/tmp-$kind"
    "HOME=$WORK/home-$kind"
    "XDG_DATA_HOME=$WORK/data-$kind"
    "XDG_CACHE_HOME=$WORK/xdg-$kind"
    "FAKE_KHAL_LOG=$WORK/khal-$kind.log"
  )
  if [ "$kind" = shell ]; then
    env "${envargs[@]}" bash "$SHELL" "${common[@]}" --month 2026-11 --country RU \
      < "$WORK/fifo-$kind" > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  else
    env "${envargs[@]}" "$BIN" "${common[@]}" --month 2026-11 --country RU \
      < "$WORK/fifo-$kind" > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  fi
  local pid=$!
  exec 9> "$WORK/fifo-$kind"
  for _ in $(seq 1 300); do
    grep -q '/PublicHolidays/' "$WORK/requests.jsonl" 2> /dev/null && break
    sleep 0.02
  done
  local started elapsed_ns code=0
  started=$(date +%s%N)
  kill -TERM "$pid" 2> /dev/null || true
  wait "$pid" || code=$?
  local ended
  ended=$(date +%s%N)
  exec 9>&-
  rm -f "$WORK/fifo-$kind"
  stop_mock
  elapsed_ns=$((ended - started))
  local elapsed_ms=$((elapsed_ns / 1000000))
  printf '  %s: exit %d after %d ms, %d line(s)\n' \
    "$kind" "$code" "$elapsed_ms" "$(wc -l < "$WORK/sig-$kind.out")"
  [ "$code" -eq 0 ] && [ "$elapsed_ms" -lt 2000 ] \
    && [ "$(wc -l < "$WORK/sig-$kind.out")" -eq 1 ]
}
if sigterm_case shell; then
  pass "SIGTERM during a request: shell exits 0 within 2 s with only the handshake"
else
  fail "SIGTERM during a request: shell"
fi
if sigterm_case rust; then
  pass "SIGTERM during a request: rust exits 0 within 2 s with only the handshake"
else
  fail "SIGTERM during a request: rust"
fi

section "khal text quirks (tab in a field, invalid date, empty title)"
# GNU date -d also understands natural language ("next week"), which khal never
# prints; the port deliberately keeps that fallback to the two khal forms, and
# an invalid calendar date is the shared fallback both workers keep verbatim.
export FAKE_KHAL_TEXT=$'2026-02-31|09:00|Unknown|Cal\n2026-11-05|09:00|A\tB|C|D\n2026-11-06|09:00||Empty|\n'
begin_pair
once_pair "khal-text-quirks" -- --month 2026-11
export FAKE_KHAL_TEXT="$DEFAULT_KHAL_TEXT"

section "pill state edge cases"
pill_index=0
for pill_state in \
  '{"history":[{"date":"2026-11-02","taken":true}]}' \
  '{"today":"2026-11-03","taken":true,"history":[{"date":"2026-11-1","taken":true}]}' \
  '{"today":"bad","taken":true,"history":[{"date":"2026-11-02","taken":true}]}' \
  '{"today":"2026-11-03","taken":true,"history":[null]}'; do
  pill_index=$((pill_index + 1))
  begin_pair
  seed_pills "$pill_state"
  once_pair "pills-edge-$pill_index" -- --month 2026-11
done

section "result"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PARITY CHECKS PASSED"
else
  echo "PARITY CHECKS FAILED" >&2
  exit 1
fi
