#!/usr/bin/env bash
# calendar.sh - calendar worker (pleamar helper; protocol: INTERFACES.md §7).
#
# A scene spawns this worker while the calendar view exists, subscribes to the
# `calendar` topic and kills it on close. Events come from `khal list`; the
# month is cached for two minutes in a file, so the grid can be redrawn without
# another khal run. The date arguments are sent in ISO form first and retried
# in the locale's dd.mm.yyyy form when khal rejects them, because khal parses
# CLI dates with the format from its own config (this host's khal needs the
# retry, the legacy Quickshell helper passed ISO and silently got nothing).
# Public holidays are optional (--country) and come from date.nager.at.
#
# Protocol (README.md has the full text):
#   handshake  {"ok":true,"worker":"calendar","version":1,"topics":["calendar"]}
#   commands   {"cmd":"subscribe","topic":"calendar","interval_ms":300000}
#              {"cmd":"sample","month":"2026-11"} {"cmd":"set","month":"2026-11"}
#              {"cmd":"set","interval_ms":60000}
#              {"cmd":"unsubscribe","topic":"calendar"} {"cmd":"stop"}
#   sample     {"ok":true,"worker":"calendar","topic":"calendar","t":<ms>,
#              "data":{month,first,last,events[{date,time,title,calendar}],
#                      holidays[{date,name,name_en}],holidays_error,
#                      fetched_at,cached,age_s}}
#   error      {"ok":false,"worker":"calendar","err":"…","t":<ms>}
#
# `calendar` is auto-subscribed at --interval-ms (300000 by default), so a
# scene that only reads lines gets one month sample at startup; `--once` prints
# the handshake plus one sample and exits. A closed stdin finishes the worker.
#
# Usage: calendar.sh [--month YYYY-MM] [--country CC] [--cache-dir DIR]
#                    [--interval-ms N] [--once] [--holidays-base URL] [--help]
#
# Exit: 0 when stdin closes or on stop; 1 when the worker cannot start.

set -euo pipefail

usage() {
  cat << 'EOF'
calendar.sh - calendar worker (JSON lines, INTERFACES.md §7)

Usage:
  calendar.sh [options]

Options:
  --month YYYY-MM      month to list first (default: the current one)
  --country CC         also fetch public holidays for this ISO country code
  --cache-dir DIR      where month/holiday caches live
                       (default: $XDG_CACHE_HOME/pleamar/helpers)
  --interval-ms N      default cadence of the `calendar` topic, 100..3600000
                       (default: 300000)
  --once               print the handshake and one sample, then exit
  --holidays-base URL  holidays API base (default: https://date.nager.at/api/v3)
  -h, --help           this text

Topic: calendar. Commands: subscribe, unsubscribe, set, sample, stop, with an
optional `month` field on subscribe/sample/set for month navigation (one JSON
object per stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
EOF
}

WORKER=calendar

die() {
  printf 'calendar: error: %s\n' "$*" >&2
  exit 2
}

MONTH=""
COUNTRY=""
CACHE_DIR=""
INTERVAL_MS=300000
ONCE=0
HOLIDAY_BASE="${PLEAMAR_HOLIDAYS_BASE:-https://date.nager.at/api/v3}"

while [ $# -gt 0 ]; do
  case "$1" in
    --month)
      [ $# -ge 2 ] || die "--month needs a value"
      MONTH=$2
      shift 2
      ;;
    --country)
      [ $# -ge 2 ] || die "--country needs a value"
      COUNTRY=$2
      shift 2
      ;;
    --cache-dir)
      [ $# -ge 2 ] || die "--cache-dir needs a value"
      CACHE_DIR=$2
      shift 2
      ;;
    --interval-ms)
      [ $# -ge 2 ] || die "--interval-ms needs a value"
      INTERVAL_MS=$2
      shift 2
      ;;
    --once)
      ONCE=1
      shift
      ;;
    --holidays-base)
      [ $# -ge 2 ] || die "--holidays-base needs a value"
      HOLIDAY_BASE=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option '$1' (see --help)"
      ;;
  esac
done

case "$COUNTRY" in
  '' | [A-Za-z][A-Za-z]) ;;
  *) die "--country must be a two-letter code (got '$COUNTRY')" ;;
esac
case "$INTERVAL_MS" in
  '' | *[!0-9]*) die "--interval-ms must be an integer (got '$INTERVAL_MS')" ;;
esac
[ "$INTERVAL_MS" -ge 100 ] && [ "$INTERVAL_MS" -le 3600000 ] || die "--interval-ms must be 100..3600000"

if [ -z "$CACHE_DIR" ]; then
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/helpers"
fi

# A worker that cannot start says so in the protocol shape and exits non-zero.
start_error() {
  printf '{"ok":false,"worker":"%s","err":"%s"}\n' "$WORKER" "$1"
  exit 1
}

if ! command -v jq > /dev/null 2>&1; then
  start_error "jq not installed"
fi
if ! command -v khal > /dev/null 2>&1; then
  start_error "khal not installed"
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

KHAL_FORMAT='{start-date}|{start-time}|{title}|{calendar}'
FIRST=""
LAST=""
FIRST_EU=""
LAST_EU=""
YEAR=""

# Accepts YYYY-MM or YYYY-MM-DD; sets MONTH/FIRST/LAST/FIRST_EU/LAST_EU/YEAR.
set_month() {
  local raw=$1
  case "$raw" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]) raw=$raw ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) raw=${raw%-*} ;;
    *) return 1 ;;
  esac
  MONTH=$raw
  FIRST="$MONTH-01"
  if ! LAST=$(date -d "$FIRST +1 month -1 day" +%F 2> /dev/null); then
    return 1
  fi
  FIRST_EU=$(date -d "$FIRST" +%d.%m.%Y)
  LAST_EU=$(date -d "$LAST" +%d.%m.%Y)
  YEAR=${MONTH%%-*}
  return 0
}

TMP_DIR=""
cleanup() {
  if [ -n "$CURL_PID" ]; then
    kill "$CURL_PID" 2> /dev/null || true
  fi
  if [ -n "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR"
  fi
  if [ -n "$HOLIDAY_TMP" ]; then
    rm -rf -- "$HOLIDAY_TMP"
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-calendar.XXXXXX")

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

KHAL_TEXT=""
ERR_MSG=""
HOLIDAY_TMP=""
CURL_PID=""
HOLIDAYS_JSON="[]"
HOLIDAY_ERROR=""

# Run khal for the month; ISO dates first, the locale's dd.mm.yyyy second.
# Sets KHAL_TEXT on 0 and ERR_MSG on 1.
khal_list_month() {
  local out err_file rc first_error
  err_file="$TMP_DIR/khal.err"
  out=""
  rc=0
  out=$(khal list --format "$KHAL_FORMAT" "$FIRST" "$LAST" 2> "$err_file") || rc=$?
  if [ "$rc" -ne 0 ] || grep -qE 'critical|Traceback' "$err_file"; then
    rc=0
    out=$(khal list --format "$KHAL_FORMAT" "$FIRST_EU" "$LAST_EU" 2> "$err_file") || rc=$?
  fi
  if [ "$rc" -ne 0 ] || grep -qE 'critical|Traceback' "$err_file"; then
    first_error=$(head -n 1 "$err_file" 2> /dev/null || true)
    [ -n "$first_error" ] || first_error="khal exited $rc"
    ERR_MSG="khal list failed: $first_error"
    return 1
  fi
  KHAL_TEXT=$out
  return 0
}

# Build the events JSON array from khal's pipe-separated lines.
parse_events() {
  local text=$1
  local line raw_line raw_date raw_time title calendar rest iso_date entry tsv
  tsv=""
  while IFS= read -r raw_line; do
    line=$(printf '%s' "$raw_line" | LC_ALL=C sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')
    case "$line" in
      *"|"*"|"*"|"*) ;;
      *) continue ;;
    esac
    raw_date=$(trim "${line%%|*}")
    rest=${line#*|}
    raw_time=$(trim "${rest%%|*}")
    rest=${rest#*|}
    title=$(trim "${rest%|*}")
    calendar=$(trim "${rest##*|}")
    iso_date=$(date -d "$raw_date" +%F 2> /dev/null) || iso_date=$raw_date
    printf -v entry '%s\t%s\t%s\t%s\n' "$iso_date" "$raw_time" "$title" "$calendar"
    tsv+=$entry
  done <<< "$text"
  printf '%s' "$tsv" | jq -R -s -c \
    'split("\n") | map(select(length > 0) | split("\t")
      | {date: .[0], time: .[1], title: .[2], calendar: .[3]})'
}

# Holidays are static per year: cache the raw answer for a day.
# Sets HOLIDAYS_JSON and HOLIDAY_ERROR.
holidays_json() {
  local file raw mtime age rc
  HOLIDAY_ERROR=""
  HOLIDAYS_JSON="[]"
  if [ -z "$COUNTRY" ]; then
    return 0
  fi
  file="$CACHE_DIR/holidays-$YEAR-$COUNTRY.json"
  if [ -f "$file" ]; then
    mtime=$(stat -c %Y -- "$file" 2> /dev/null || echo 0)
    age=$((NOW - mtime))
    if [ "$age" -lt 86400 ]; then
      raw=$(< "$file")
      HOLIDAYS_JSON=$(printf '%s' "$raw" | jq -c --arg m "$MONTH" '
        [ .[] | select((.date // "") | startswith($m))
          | {date: .date, name: .localName, name_en: .name} ]')
      return 0
    fi
  fi
  if ! command -v curl > /dev/null 2>&1; then
    HOLIDAY_ERROR="curl not installed"
    return 0
  fi
  HOLIDAY_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-calendar-http.XXXXXX")
  curl --fail --silent --show-error --location --max-time 8 \
    --user-agent "pleamar-calendar/1.0" "$HOLIDAY_BASE/PublicHolidays/$YEAR/$COUNTRY" \
    > "$HOLIDAY_TMP/body" 2> "$HOLIDAY_TMP/err" &
  CURL_PID=$!
  rc=0
  wait "$CURL_PID" || rc=$?
  CURL_PID=""
  if [ "$rc" -ne 0 ]; then
    raw=$(< "$HOLIDAY_TMP/err")
    HOLIDAY_ERROR="holidays request failed: ${raw##*$'\n'}"
    rm -rf -- "$HOLIDAY_TMP"
    HOLIDAY_TMP=""
    return 0
  fi
  raw=$(< "$HOLIDAY_TMP/body")
  rm -rf -- "$HOLIDAY_TMP"
  HOLIDAY_TMP=""
  mkdir -p -- "$CACHE_DIR"
  if printf '%s' "$raw" | jq -c . > "$CACHE_DIR/.holidays.$$.tmp" 2> /dev/null; then
    mv -f -- "$CACHE_DIR/.holidays.$$.tmp" "$file"
  fi
  HOLIDAYS_JSON=$(printf '%s' "$raw" | jq -c --arg m "$MONTH" '
    [ .[] | select((.date // "") | startswith($m))
      | {date: .date, name: .localName, name_en: .name} ]')
  return 0
}

PAYLOAD=""

# Cache or khal; sets PAYLOAD on 0, ERR_MSG on 1.
build_payload() {
  local cache_file c_month c_fetched age events payload
  NOW=$(date +%s)
  cache_file="$CACHE_DIR/calendar-$MONTH.json"
  if [ -f "$cache_file" ]; then
    c_month=$(jq -r '.month // ""' "$cache_file" 2> /dev/null || true)
    c_fetched=$(jq -r '.fetched_at // 0' "$cache_file" 2> /dev/null || true)
    age=$((NOW - c_fetched))
    if [ "$c_month" = "$MONTH" ] && [ "$age" -lt 120 ]; then
      PAYLOAD=$(jq -c --argjson now "$NOW" \
        '{month, first, last, events, holidays, holidays_error, fetched_at,
          cached: true, age_s: ($now - (.fetched_at // $now))}' "$cache_file")
      return 0
    fi
  fi
  ERR_MSG=""
  if ! khal_list_month; then
    return 1
  fi
  events=$(parse_events "$KHAL_TEXT")
  holidays_json
  payload=$(jq -cn --arg month "$MONTH" --arg first "$FIRST" --arg last "$LAST" \
    --argjson events "$events" --argjson holidays "$HOLIDAYS_JSON" \
    --arg holi_err "$HOLIDAY_ERROR" --argjson now "$NOW" \
    '{month:$month, first:$first, last:$last, events:$events, holidays:$holidays,
      holidays_error:(if $holi_err == "" then null else $holi_err end),
      fetched_at:$now, cached:false, age_s:0}')
  mkdir -p -- "$CACHE_DIR"
  jq -cn --arg month "$MONTH" --arg first "$FIRST" --arg last "$LAST" \
    --argjson events "$events" --argjson holidays "$HOLIDAYS_JSON" \
    --arg holi_err "$HOLIDAY_ERROR" --argjson now "$NOW" \
    '{month:$month, first:$first, last:$last, events:$events, holidays:$holidays,
      holidays_error:(if $holi_err == "" then null else $holi_err end),
      fetched_at:$now, cached:true}' > "$CACHE_DIR/.calendar.$$.tmp"
  mv -f -- "$CACHE_DIR/.calendar.$$.tmp" "$cache_file"
  PAYLOAD=$payload
  return 0
}

emit_sample() {
  local now
  now_ms
  now=$NOW_MS
  if build_payload; then
    printf '{"ok":true,"worker":"%s","topic":"calendar","t":%s,"data":%s}\n' "$WORKER" "$now" "$PAYLOAD"
  else
    sample_error "$ERR_MSG"
  fi
  return 0
}

KNOWN_TOPICS="calendar"
topic_known() {
  case " $KNOWN_TOPICS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

declare -A SUB_INTERVAL=()
declare -A SUB_NEXT=()

handle_command() {
  local line=$1 parts cmd topic interval month now
  parts=$(printf '%s' "$line" | jq -r '[.cmd // "", .topic // "", ((.interval_ms // "") | tostring), (.month // "")] | join("|")' 2> /dev/null) || {
    json_err "bad command line"
    return 0
  }
  IFS='|' read -r cmd topic interval month <<< "$parts"
  # A month in the command navigates before anything else answers.
  if [ -n "$month" ]; then
    if ! set_month "$month"; then
      json_err "bad month: $month"
      return 0
    fi
    SUB_NEXT[calendar]=0
  fi
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
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 3600000 ]; then
        json_err "interval_ms must be 100..3600000"
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
      if [ -n "$interval" ]; then
        case "$interval" in
          *[!0-9]*)
            json_err "interval_ms must be an integer"
            return 0
            ;;
        esac
        if [ "$interval" -lt 100 ] || [ "$interval" -gt 3600000 ]; then
          json_err "interval_ms must be 100..3600000"
          return 0
        fi
        for topic in "${!SUB_INTERVAL[@]}"; do
          SUB_INTERVAL[$topic]=$interval
        done
      elif [ -z "$month" ]; then
        json_err "set needs interval_ms or month"
        return 0
      fi
      ack set
      ;;
    sample)
      now_ms
      now=$NOW_MS
      for topic in "${!SUB_NEXT[@]}"; do
        SUB_NEXT[$topic]=0
      done
      ack sample
      emit_due_samples "$now"
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

if ! set_month "${MONTH:-$(date +%Y-%m)}"; then
  die "--month must be YYYY-MM or YYYY-MM-DD (got '$MONTH')"
fi

printf '{"ok":true,"worker":"%s","version":1,"topics":["calendar"]}\n' "$WORKER"

SUB_INTERVAL[calendar]=$INTERVAL_MS
SUB_NEXT[calendar]=0

if [ "$ONCE" -eq 1 ]; then
  emit_sample
  exit 0
fi

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
  now_ms
  emit_due_samples "$NOW_MS"
done
exit 0
