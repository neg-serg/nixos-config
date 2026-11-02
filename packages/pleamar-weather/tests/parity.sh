#!/usr/bin/env bash
# Parity harness: run the shipped weather.sh and the Rust port side by side
# against the same local mock providers and compare what the pleamar protocol,
# the data schema and the cache promise.
#
#   tests/parity.sh [--bin PATH] [--shell PATH]
#
# Env: PLEAMAR_WEATHER_BIN / PLEAMAR_WEATHER_SH override the paths.
#
# Needs bash, jq and curl for the shell worker, python3 for the mocks. Exit 0
# only when every check passes; each section prints the evidence it compared.
# Nothing here talks to the internet.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
BIN=${PLEAMAR_WEATHER_BIN:-${CARGO_TARGET_DIR:-$ROOT/target}/debug/pleamar-weather}
SHELL=${PLEAMAR_WEATHER_SH:-$(cd -- "$ROOT/../.." && pwd)/files/pleamar/scripts/helpers/weather.sh}

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
command -v python3 > /dev/null || {
  echo "parity: python3 is required for the mock providers" >&2
  exit 2
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-weather-parity.XXXXXX")
MOCK_PID=""
MOCK_BASE=""

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

start_mock() {
  rm -f "$WORK/port"
  : > "$WORK/requests.jsonl"
  python3 "$HERE/mock_providers.py" --port-file "$WORK/port" --log "$WORK/requests.jsonl" "$@" &
  MOCK_PID=$!
  for _ in $(seq 1 300); do
    [ -s "$WORK/port" ] && break
    sleep 0.02
  done
  [ -s "$WORK/port" ] || {
    echo "parity: the mock providers did not start" >&2
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

# run_worker KIND OUT [WORKER ARG...] — a fresh cache and TMPDIR per kind.
run_worker() {
  local kind=$1 out=$2
  shift 2
  mkdir -p "$WORK/tmp-$kind"
  local cache=$WORK/cache-$kind/weather.json
  local common=(--cache-file "$cache" --api-base "$MOCK_BASE/v1"
    --geocoding-base "$MOCK_BASE/geo/v1" --wttr-base "$MOCK_BASE/wttr"
    --metno-base "$MOCK_BASE/metno" --timeout 3)
  if [ "$kind" = shell ]; then
    TMPDIR=$WORK/tmp-$kind bash "$SHELL" "${common[@]}" "$@" > "$out" 2> "$out.err"
  else
    TMPDIR=$WORK/tmp-$kind "$BIN" "${common[@]}" "$@" > "$out" 2> "$out.err"
  fi
}

# Recursive key/type schema, sorted: what a consumer relies on.
SCHEMA_JQ='def schema:
  if type == "object" then
    {type:"object", fields:(to_entries | map({key:.key, value:(.value|schema)}) | sort_by(.key))}
  elif type == "array" then
    {type:"array", items:(map(schema))}
  else type end;
if .[1].ok then (.[1].data | schema) else null end'

# Payload without the volatile fields (wall clock, age).
NORMALIZE_JQ='def norm_data:
  .data | del(.fetched_at, .age_s);
if .[1].ok then (.[1] | norm_data) else (.[1] | del(.t)) end'

# compare_once KIND-AGNOSTIC EVALUATION of the second line.
compare_once() {
  local label=$1
  if [ "$SHELL_CODE" -ne "$RUST_CODE" ]; then
    fail "$label: exit codes differ (shell $SHELL_CODE, rust $RUST_CODE)"
  elif [ "$SHELL_CODE" -ne 0 ]; then
    fail "$label: --once must finish 0 (both exited $SHELL_CODE; the harness arguments are wrong)"
  else
    pass "$label: both workers exit 0"
  fi

  if diff -u <(head -n1 "$WORK/shell.jsonl") <(head -n1 "$WORK/rust.jsonl") > /dev/null; then
    pass "$label: handshake is byte-identical"
  else
    fail "$label: handshake differs"
  fi

  jq -s -c "$NORMALIZE_JQ" "$WORK/shell.jsonl" > "$WORK/shell-normal.json"
  jq -s -c "$NORMALIZE_JQ" "$WORK/rust.jsonl" > "$WORK/rust-normal.json"
  if diff -u "$WORK/shell-normal.json" "$WORK/rust-normal.json"; then
    pass "$label: sample payload (or error line) is byte-identical after removing the clock"
  else
    fail "$label: payload differs"
  fi

  jq -s -c "$SCHEMA_JQ" "$WORK/shell.jsonl" > "$WORK/shell-schema.json"
  jq -s -c "$SCHEMA_JQ" "$WORK/rust.jsonl" > "$WORK/rust-schema.json"
  if diff -u "$WORK/shell-schema.json" "$WORK/rust-schema.json" > /dev/null; then
    pass "$label: payload schema (keys and types, recursively) is identical"
  else
    fail "$label: payload schema differs"
  fi

  jq -c '{method, path, ua}' "$WORK/shell-requests.jsonl" > "$WORK/shell-requests.norm" 2> /dev/null || :
  jq -c '{method, path, ua}' "$WORK/rust-requests.jsonl" > "$WORK/rust-requests.norm" 2> /dev/null || :
  if diff -u "$WORK/shell-requests.norm" "$WORK/rust-requests.norm"; then
    pass "$label: request URLs (path and User-Agent) are identical"
  else
    fail "$label: requests differ"
  fi

  if [ -f "$WORK/cache-shell/weather.json" ] && [ -f "$WORK/cache-rust/weather.json" ]; then
    jq -c 'del(.fetched_at, .geocoded_at) | .payload |= del(.fetched_at, .age_s)' \
      "$WORK/cache-shell/weather.json" > "$WORK/shell-cache.norm"
    jq -c 'del(.fetched_at, .geocoded_at) | .payload |= del(.fetched_at, .age_s)' \
      "$WORK/cache-rust/weather.json" > "$WORK/rust-cache.norm"
    if diff -u "$WORK/shell-cache.norm" "$WORK/rust-cache.norm"; then
      pass "$label: cache document shape is identical (order, literals, payload)"
    else
      fail "$label: cache documents differ"
    fi
    local shell_mode rust_mode
    shell_mode=$(stat -c '%a' "$WORK/cache-shell/weather.json")
    rust_mode=$(stat -c '%a' "$WORK/cache-rust/weather.json")
    if [ "$shell_mode" = "$rust_mode" ]; then
      pass "$label: cache mode agrees ($shell_mode)"
    else
      fail "$label: cache modes differ (shell $shell_mode, rust $rust_mode)"
    fi
  elif [ -f "$WORK/cache-shell/weather.json" ] || [ -f "$WORK/cache-rust/weather.json" ]; then
    fail "$label: only one worker wrote a cache"
  else
    pass "$label: both workers wrote no cache"
  fi
}

# once_pair LABEL [-- MOCK ARGS -- WORKER ARGS] — one --once run per worker.
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
  rm -rf "$WORK/cache-shell" "$WORK/cache-rust"

  start_mock "${mock_args[@]}"
  SHELL_CODE=0
  run_worker shell "$WORK/shell.jsonl" --once "${worker_args[@]}" || SHELL_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
  stop_mock

  start_mock "${mock_args[@]}"
  RUST_CODE=0
  run_worker rust "$WORK/rust.jsonl" --once "${worker_args[@]}" || RUST_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
  stop_mock

  compare_once "$label"
}

# seed_cache KIND LAT LON GEOCODED_AT FETCHED_AT PROVIDER — a hand-written
# cache document, so a scenario can choose the age of the payload and of the
# geocoding memory.
seed_cache() {
  local kind=$1 lat=$2 lon=$3 geo=$4 fetched=$5 provider=$6
  rm -rf "$WORK/cache-$kind"
  mkdir -p "$WORK/cache-$kind"
  jq -n -c --arg city "Oslo" --argjson lat "$lat" --argjson lon "$lon" \
    --argjson geo "$geo" --argjson fetched "$fetched" --arg provider "$provider" \
    '{city:$city,latitude:$lat,longitude:$lon,geocoded_at:$geo,fetched_at:$fetched,
      payload:{city:$city,latitude:$lat,longitude:$lon,provider:$provider,
        fetched_at:$fetched,age_s:0,cached:false,
        current:{temp_c:5.0,weather_code:3,wind_ms:2.0,wind_dir_deg:90,is_day:1,
          humidity_pct:70,pressure_hpa:1010.0},
        daily:[{date:"2026-11-02",tmax_c:7.0,tmin_c:5.0,weather_code:3}]}}' \
    > "$WORK/cache-$kind/weather.json"
}

# run_seeded LABEL [WORKER ARG...] — both workers against the caches already
# seeded in $WORK/cache-shell and $WORK/cache-rust.
run_seeded() {
  local label=$1
  shift
  start_mock
  SHELL_CODE=0
  run_worker shell "$WORK/shell.jsonl" --once "$@" || SHELL_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
  stop_mock
  start_mock
  RUST_CODE=0
  run_worker rust "$WORK/rust.jsonl" --once "$@" || RUST_CODE=$?
  cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
  stop_mock
  compare_once "$label"
}

section "fresh payload through geocoding"
once_pair "open-meteo" -- --city "Saint Petersburg"
printf '  shell: %s\n' "$(sed -n '2p' "$WORK/shell.jsonl")"
printf '  rust:  %s\n' "$(sed -n '2p' "$WORK/rust.jsonl")"

section "explicit coordinates (geocoding skipped)"
once_pair "coordinates" -- --lat 59.9 --lon 30.7

section "provider fallback: Open-Meteo 503 -> wttr current + met.no daily"
once_pair "fallback" --forecast-status 503 -- --lat 59.9 --lon 30.7

section "--no-fallback keeps the primary error"
once_pair "no-fallback" --forecast-status 500 -- --lat 59.9 --lon 30.7 --no-fallback

section "malformed Open-Meteo answer"
once_pair "malformed" --forecast-body '{"current": "truncated' -- --lat 59.9 --lon 30.7 --no-fallback

section "both providers failing join their errors"
once_pair "joined-errors" --forecast-status 503 --wttr-body 'no weather here' -- \
  --lat 59.9 --lon 30.7

section "broken met.no leaves daily empty"
once_pair "broken-metno" --forecast-status 503 --metno-body '<html>down</html>' -- \
  --lat 59.9 --lon 30.7

section "geocoding finds nothing"
once_pair "city-not-found" --geocode-body '{"results":[]}' -- --city Nowhere

section "geocoding fails"
once_pair "geocode-500" --geocode-status 500 -- --city Nowhere

section "a request timeout has curl's text"
once_pair "timeout" --delay 2 --delay-routes forecast -- \
  --lat 59.9 --lon 30.7 --timeout 1 --no-fallback

section "cache hit with explicit coordinates"
now=$(date +%s)
seed_cache shell 59.9 30.7 "$now" "$now" open-meteo
seed_cache rust 59.9 30.7 "$now" "$now" open-meteo
run_seeded "cache-hit-coords" --city Oslo --lat 59.9 --lon 30.7
if [ "$(wc -l < "$WORK/shell-requests.jsonl")" -eq 0 ] \
  && [ "$(wc -l < "$WORK/rust-requests.jsonl")" -eq 0 ]; then
  pass "cache-hit-coords: neither worker touched the network"
else
  fail "cache-hit-coords: a worker went to the network"
fi

section "a coordinate string mismatch refetches"
now=$(date +%s)
seed_cache shell 59.9 30.7 "$now" "$now" open-meteo
seed_cache rust 59.9 30.7 "$now" "$now" open-meteo
run_seeded "coords-mismatch" --city Oslo --lat 59.90 --lon 30.70

section "an invalid cache file is ignored"
for kind in shell rust; do
  rm -rf "$WORK/cache-$kind"
  mkdir -p "$WORK/cache-$kind"
  printf 'not json\n' > "$WORK/cache-$kind/weather.json"
done
run_seeded "invalid-cache" --city Oslo

section "a failed refresh keeps the last good cache"
now=$(date +%s)
seed_cache shell 59.9 30.7 "$now" "$now" open-meteo
seed_cache rust 59.9 30.7 "$now" "$now" open-meteo
cp "$WORK/cache-shell/weather.json" "$WORK/cache-shell.before"
cp "$WORK/cache-rust/weather.json" "$WORK/cache-rust.before"
start_mock --forecast-status 500
SHELL_CODE=0
run_worker shell "$WORK/shell.jsonl" --once --city Oslo --force --no-fallback || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
stop_mock
start_mock --forecast-status 500
RUST_CODE=0
run_worker rust "$WORK/rust.jsonl" --once --city Oslo --force --no-fallback || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
stop_mock
compare_once "error-keeps-cache"
if diff -q "$WORK/cache-shell.before" "$WORK/cache-shell/weather.json" > /dev/null \
  && diff -q "$WORK/cache-rust.before" "$WORK/cache-rust/weather.json" > /dev/null; then
  pass "error-keeps-cache: both caches are byte-identical after the failed refresh"
else
  fail "error-keeps-cache: a failed refresh rewrote a cache"
fi

section "cache hit inside the TTL (no network)"
for kind in shell rust; do
  rm -rf "$WORK/cache-$kind"
  mkdir -p "$WORK/cache-$kind"
  now=$(date +%s)
  jq -n -c --arg city "Oslo" --argjson lat 59.9 --argjson lon 10.7 \
    --argjson now "$now" \
    '{city:$city,latitude:$lat,longitude:$lon,geocoded_at:$now,fetched_at:$now,
      payload:{city:$city,latitude:$lat,longitude:$lon,provider:"open-meteo",
        fetched_at:$now,age_s:0,cached:false,
        current:{temp_c:5.0,weather_code:3,wind_ms:2.0,wind_dir_deg:90,is_day:1,
          humidity_pct:70,pressure_hpa:1010.0},
        daily:[{date:"2026-11-02",tmax_c:7.0,tmin_c:5.0,weather_code:3}]}}' \
    > "$WORK/cache-$kind/weather.json"
done
start_mock
SHELL_CODE=0
run_worker shell "$WORK/shell.jsonl" --once --city Oslo || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_worker rust "$WORK/rust.jsonl" --once --city Oslo || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
stop_mock
compare_once "cache-hit"
jq -s -c '.[1].data | {cached, age_s, provider}' "$WORK/shell.jsonl"
if [ "$(wc -l < "$WORK/shell-requests.jsonl")" -eq 0 ] \
  && [ "$(wc -l < "$WORK/rust-requests.jsonl")" -eq 0 ]; then
  pass "cache-hit: neither worker touched the network"
else
  fail "cache-hit: a worker went to the network"
fi

section "--force ignores a fresh cache"
for kind in shell rust; do
  now=$(date +%s)
  jq -n -c --arg city "Oslo" --argjson lat 59.9 --argjson lon 10.7 \
    --argjson now "$now" \
    '{city:$city,latitude:$lat,longitude:$lon,geocoded_at:$now,fetched_at:$now,
      payload:{city:$city,latitude:$lat,longitude:$lon,provider:"wttr.in",
        fetched_at:$now,age_s:0,cached:false,
        current:{temp_c:5.0,weather_code:3,wind_ms:2.0,wind_dir_deg:90,is_day:null,
          humidity_pct:70,pressure_hpa:1010.0},
        daily:[]}}' > "$WORK/cache-$kind/weather.json"
done
start_mock
SHELL_CODE=0
run_worker shell "$WORK/shell.jsonl" --once --city Oslo --force || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_worker rust "$WORK/rust.jsonl" --once --city Oslo --force || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
stop_mock
compare_once "force"

section "stale cache is refetched"
for kind in shell rust; do
  old=$(($(date +%s) - 1000))
  jq -n -c --arg city "Oslo" --argjson lat 59.9 --argjson lon 10.7 \
    --argjson old "$old" \
    '{city:$city,latitude:$lat,longitude:$lon,geocoded_at:$old,fetched_at:$old,
      payload:{city:$city,latitude:$lat,longitude:$lon,provider:"wttr.in",
        fetched_at:$old,age_s:0,cached:false,
        current:{temp_c:5.0,weather_code:3,wind_ms:2.0,wind_dir_deg:90,is_day:null,
          humidity_pct:70,pressure_hpa:1010.0},
        daily:[]}}' > "$WORK/cache-$kind/weather.json"
done
start_mock
SHELL_CODE=0
run_worker shell "$WORK/shell.jsonl" --once --city Oslo || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_worker rust "$WORK/rust.jsonl" --once --city Oslo || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
stop_mock
compare_once "stale"

section "geocoding memory is reused for a day"
for kind in shell rust; do
  now=$(date +%s)
  jq -n -c --arg city "Oslo" --argjson lat 59.9 --argjson lon 10.7 \
    --argjson now "$now" \
    '{city:$city,latitude:$lat,longitude:$lon,geocoded_at:($now - 3600),
      fetched_at:($now - 1000),
      payload:{city:$city,latitude:$lat,longitude:$lon,provider:"open-meteo",
        fetched_at:($now - 1000),age_s:0,cached:false,
        current:{temp_c:5.0,weather_code:3,wind_ms:2.0,wind_dir_deg:90,is_day:1,
          humidity_pct:70,pressure_hpa:1010.0},daily:[]}}' \
    > "$WORK/cache-$kind/weather.json"
done
start_mock
SHELL_CODE=0
run_worker shell "$WORK/shell.jsonl" --once --city Oslo || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-requests.jsonl"
stop_mock
start_mock
RUST_CODE=0
run_worker rust "$WORK/rust.jsonl" --once --city Oslo || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-requests.jsonl"
stop_mock
compare_once "geo-reuse"
if ! grep -q '/search' "$WORK/shell-requests.norm" \
  && ! grep -q '/search' "$WORK/rust-requests.norm"; then
  pass "geo-reuse: neither worker re-geocoded"
else
  fail "geo-reuse: a worker re-geocoded"
fi

section "command dialogue"
cat > "$WORK/dialogue.txt" << 'DIALOGUE'
{"cmd":"subscribe","topic":"weather","interval_ms":600000}
{"cmd":"set","interval_ms":250}
{"cmd":"unsubscribe","topic":"weather"}
{"cmd":"sample"}
{"cmd":"bogus"}
not json
{"cmd":"subscribe","topic":"weather"}
{"cmd":"subscribe","topic":"weather2"}
{"cmd":"subscribe","topic":"weather","interval_ms":50}
{"cmd":"subscribe","topic":"weather","interval_ms":"x"}
{}
{"cmd":{}}
{"cmd":{"a":1}}
{"cmd":"subscribe","topic":"weather","interval_ms":100.0}
{"cmd":"set","interval_ms":"600000"}
{} {}
   
{"cmd":"subscribe","topic":"weather"}
{"cmd":"sample"}
DIALOGUE
# A final line without a newline: bash's read fails at EOF and the shell never
# handles it; the port drops the partial line the same way.
printf '%s' '{"cmd":"stop"}' >> "$WORK/dialogue.txt"

start_mock
SHELL_CODE=0
rm -rf "$WORK/cache-shell"
mkdir -p "$WORK/tmp-shell"
TMPDIR=$WORK/tmp-shell bash "$SHELL" --cache-file "$WORK/cache-shell/weather.json" \
  --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
  --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" --timeout 3 \
  --city Oslo < "$WORK/dialogue.txt" > "$WORK/shell-dialogue.jsonl" \
  2> "$WORK/shell-dialogue.err" || SHELL_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/shell-dialogue-requests.jsonl"
stop_mock

start_mock
RUST_CODE=0
rm -rf "$WORK/cache-rust"
mkdir -p "$WORK/tmp-rust"
TMPDIR=$WORK/tmp-rust "$BIN" --cache-file "$WORK/cache-rust/weather.json" \
  --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
  --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" --timeout 3 \
  --city Oslo < "$WORK/dialogue.txt" > "$WORK/rust-dialogue.jsonl" \
  2> "$WORK/rust-dialogue.err" || RUST_CODE=$?
cp "$WORK/requests.jsonl" "$WORK/rust-dialogue-requests.jsonl"
stop_mock

if [ "$SHELL_CODE" -eq "$RUST_CODE" ]; then
  pass "dialogue: exit codes agree ($SHELL_CODE)"
else
  fail "dialogue: exit codes differ (shell $SHELL_CODE, rust $RUST_CODE)"
fi

jq -c 'select(has("topic") | not)' "$WORK/shell-dialogue.jsonl" > "$WORK/shell-control.jsonl"
jq -c 'select(has("topic") | not)' "$WORK/rust-dialogue.jsonl" > "$WORK/rust-control.jsonl"
if diff -u "$WORK/shell-control.jsonl" "$WORK/rust-control.jsonl"; then
  pass "dialogue: handshake, acks and error lines are byte-identical"
else
  fail "dialogue: control lines differ"
fi

SHELL_SAMPLES=$(jq -c 'select(.topic)' "$WORK/shell-dialogue.jsonl" | wc -l)
RUST_SAMPLES=$(jq -c 'select(.topic)' "$WORK/rust-dialogue.jsonl" | wc -l)
if [ "$SHELL_SAMPLES" -eq "$RUST_SAMPLES" ]; then
  pass "dialogue: sample line count agrees ($SHELL_SAMPLES)"
else
  fail "dialogue: sample counts differ (shell $SHELL_SAMPLES, rust $RUST_SAMPLES)"
fi

jq -c 'select(.topic) | .data | del(.fetched_at, .age_s)' "$WORK/shell-dialogue.jsonl" > "$WORK/shell-samples.norm"
jq -c 'select(.topic) | .data | del(.fetched_at, .age_s)' "$WORK/rust-dialogue.jsonl" > "$WORK/rust-samples.norm"
if diff -u "$WORK/shell-samples.norm" "$WORK/rust-samples.norm"; then
  pass "dialogue: sample payloads are byte-identical after removing the clock"
else
  fail "dialogue: sample payloads differ"
fi

jq -c '{path, ua}' "$WORK/shell-dialogue-requests.jsonl" > "$WORK/shell-dialogue-requests.norm"
jq -c '{path, ua}' "$WORK/rust-dialogue-requests.jsonl" > "$WORK/rust-dialogue-requests.norm"
if diff -u "$WORK/shell-dialogue-requests.norm" "$WORK/rust-dialogue-requests.norm"; then
  pass "dialogue: request URLs are identical"
else
  fail "dialogue: request URLs differ"
fi

section "option errors (stdout, stderr, exit code)"
check_option() {
  local label=$1
  shift
  set +e
  "$BIN" "$@" > "$WORK/rust-opt.out" 2> "$WORK/rust-opt.err"
  local rust_code=$?
  (TMPDIR=$WORK bash "$SHELL" "$@" > "$WORK/shell-opt.out" 2> "$WORK/shell-opt.err")
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
check_option "lat without lon" --lat 59.9
check_option "lon without lat" --lon 30.7
check_option "lat not a number" --lat x --lon 1
check_option "lon not a number" --lat 1 --lon x
check_option "ttl negative" --ttl -1
check_option "ttl empty" --ttl ''
check_option "interval below minimum" --interval-ms 99
check_option "interval above maximum" --interval-ms 3600001
check_option "interval not a number" --interval-ms x
check_option "forecast days zero" --forecast-days 0
check_option "forecast days too large" --forecast-days 17
check_option "timeout zero" --timeout 0
check_option "timeout too large" --timeout 121
check_option "city without a value" --city
check_option "unknown option" --bogus
check_option "unknown option after --once" --once --bogus

section "--help text"
set +e
"$BIN" --help > "$WORK/rust-help.out" 2> "$WORK/rust-help.err"
RUST_HELP=$?
TMPDIR=$WORK bash "$SHELL" --help > "$WORK/shell-help.out" 2> "$WORK/shell-help.err"
SHELL_HELP=$?
set -e
if [ "$RUST_HELP" -eq "$SHELL_HELP" ] && diff -u "$WORK/shell-help.out" "$WORK/rust-help.out"; then
  pass "--help stdout and exit code are identical"
else
  fail "--help differs"
fi

section "closed stdin"
start_mock
SHELL_CODE=0
rm -rf "$WORK/cache-shell"
TMPDIR=$WORK bash "$SHELL" --cache-file "$WORK/cache-shell/weather.json" \
  --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
  --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" --timeout 3 \
  < /dev/null > "$WORK/shell-closed.jsonl" 2>&1 || SHELL_CODE=$?
stop_mock
start_mock
RUST_CODE=0
rm -rf "$WORK/cache-rust"
TMPDIR=$WORK "$BIN" --cache-file "$WORK/cache-rust/weather.json" \
  --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
  --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" --timeout 3 \
  < /dev/null > "$WORK/rust-closed.jsonl" 2>&1 || RUST_CODE=$?
stop_mock
if [ "$SHELL_CODE" -eq 0 ] && [ "$RUST_CODE" -eq 0 ]; then
  pass "closed stdin exits 0 for both workers"
else
  fail "closed stdin exit codes (shell $SHELL_CODE, rust $RUST_CODE)"
fi
if diff -u "$WORK/shell-closed.jsonl" "$WORK/rust-closed.jsonl"; then
  pass "closed stdin writes the same lines"
else
  fail "closed stdin output differs"
fi

section "SIGTERM during an in-flight request"
sigterm_case() {
  local kind=$1
  start_mock --delay 5
  rm -f "$WORK/fifo-$kind"
  mkfifo "$WORK/fifo-$kind"
  rm -rf "$WORK/cache-$kind"
  if [ "$kind" = shell ]; then
    TMPDIR=$WORK bash "$SHELL" --cache-file "$WORK/cache-$kind/weather.json" \
      --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
      --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" \
      --timeout 30 --lat 59.9 --lon 30.7 \
      < "$WORK/fifo-$kind" > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  else
    TMPDIR=$WORK "$BIN" --cache-file "$WORK/cache-$kind/weather.json" \
      --api-base "$MOCK_BASE/v1" --geocoding-base "$MOCK_BASE/geo/v1" \
      --wttr-base "$MOCK_BASE/wttr" --metno-base "$MOCK_BASE/metno" \
      --timeout 30 --lat 59.9 --lon 30.7 \
      < "$WORK/fifo-$kind" > "$WORK/sig-$kind.out" 2> "$WORK/sig-$kind.err" &
  fi
  local pid=$!
  exec 9> "$WORK/fifo-$kind"
  for _ in $(seq 1 300); do
    grep -q '/v1/forecast' "$WORK/requests.jsonl" 2> /dev/null && break
    sleep 0.02
  done
  local started elapsed_ns
  started=$(date +%s%N)
  kill -TERM "$pid"
  set +e
  wait "$pid"
  local code=$?
  set -e
  exec 9>&-
  rm -f "$WORK/fifo-$kind"
  elapsed_ns=$(($(date +%s%N) - started))
  stop_mock
  local elapsed_ms=$((elapsed_ns / 1000000))
  printf '  %s: exit %d after %d ms\n' "$kind" "$code" "$elapsed_ms"
  [ "$code" -eq 0 ] && [ "$elapsed_ms" -lt 2000 ]
}
if sigterm_case shell; then
  pass "SIGTERM during a request: shell exits 0 within 2 s"
else
  fail "SIGTERM during a request: shell"
fi
if sigterm_case rust; then
  pass "SIGTERM during a request: rust exits 0 within 2 s"
else
  fail "SIGTERM during a request: rust"
fi

section "result"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PARITY CHECKS PASSED"
else
  echo "PARITY CHECKS FAILED" >&2
  exit 1
fi
