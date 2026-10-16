#!/usr/bin/env bash
# calendar.sh - calendar worker: one month of khal events as JSON.
#
# A scene spawns this worker while the calendar view exists and reads its JSON
# lines. Events come from `khal list`; the month is cached for two minutes in
# a file, so the grid can be redrawn without another khal run. The date
# arguments are sent in ISO form first and retried in the locale's
# dd.mm.yyyy form when khal rejects them, because khal parses CLI dates with
# the format from its own config (this host's khal needs the retry, the legacy
# Quickshell helper passed ISO and silently got nothing). Public holidays are
# optional (--country) and come from date.nager.at. See README.md for the
# line protocol.
#
# Usage: calendar.sh [--month YYYY-MM] [--country CC] [--cache-dir DIR]
#                    [--watch] [--interval SECONDS] [--holidays-base URL]
#                    [--help]
#
# Output: {"ok": {...}} once per run (one line and exit without --watch; one
# line per interval with it), or {"err": "..."} when khal cannot list at all.
# Exit: 0 after the work (even after an err line), 2 on a usage error.

set -euo pipefail

usage() {
  cat << 'EOF'
calendar.sh - one month of khal events (and optional holidays) as JSON

Usage:
  calendar.sh [options]

Options:
  --month YYYY-MM      month to list (default: the current one)
  --country CC         also fetch public holidays for this ISO country code
  --cache-dir DIR      where month/holiday caches live
                       (default: $XDG_CACHE_HOME/pleamar/helpers)
  --watch              print a line every --interval and keep running
  --interval SECONDS   watch period (default: 120)
  --holidays-base URL  holidays API base (default: https://date.nager.at/api/v3)
  -h, --help           this text

Output keys: month, first, last, events[{date,time,title,calendar}],
holidays[{date,name,name_en}], holidays_error, fetched_at, cached.

Exit status: 0 work done (also after an err line); 2 usage error.
EOF
}

die() {
  printf 'calendar: error: %s\n' "$*" >&2
  exit 2
}

MONTH=""
COUNTRY=""
CACHE_DIR=""
WATCH=0
INTERVAL=120
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
    --watch)
      WATCH=1
      shift
      ;;
    --interval)
      [ $# -ge 2 ] || die "--interval needs a value"
      INTERVAL=$2
      shift 2
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

if [ -z "$MONTH" ]; then
  MONTH=$(date +%Y-%m)
fi
case "$MONTH" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]) MONTH=$MONTH ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) MONTH=${MONTH%-*} ;;
  *) die "--month must be YYYY-MM or YYYY-MM-DD (got '$MONTH')" ;;
esac
case "$COUNTRY" in
  '' | *[!A-Za-z]*) [ -z "$COUNTRY" ] || die "--country must be a two-letter code (got '$COUNTRY')" ;;
esac
case "$INTERVAL" in
  '' | *[!0-9]*) die "--interval must be a positive integer (got '$INTERVAL')" ;;
esac
[ "$INTERVAL" -ge 1 ] || die "--interval must be at least 1"

if [ -z "$CACHE_DIR" ]; then
  CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/helpers"
fi

if ! command -v jq > /dev/null 2>&1; then
  printf '{"err":"jq not installed"}\n'
  exit 0
fi
if ! command -v khal > /dev/null 2>&1; then
  printf '{"err":"khal not installed"}\n'
  exit 0
fi

emit_err() {
  jq -cn --arg e "$1" '{err:$e}' || exit 0
}

emit_ok() {
  printf '{"ok":%s}\n' "$1" || exit 0
}

KHAL_FORMAT='{start-date}|{start-time}|{title}|{calendar}'
FIRST="$MONTH-01"
LAST=$(date -d "$FIRST +1 month -1 day" +%F) || die "cannot compute the end of $MONTH"
FIRST_EU=$(date -d "$FIRST" +%d.%m.%Y)
LAST_EU=$(date -d "$LAST" +%d.%m.%Y)
YEAR=${MONTH%%-*}

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pleamar-calendar.XXXXXX")

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

KHAL_TEXT=""
ERR_MSG=""
HOLIDAYS_JSON="[]"
HOLIDAY_ERROR=""

# Run khal for the month; ISO dates first, the locale's dd.mm.yyyy second.
# Sets KHAL_TEXT on 0 and ERR_MSG on 1.
khal_list_month() {
  local out err_file rc
  err_file="$TMP_DIR/khal.err"
  out=""
  rc=0
  out=$(khal list --format "$KHAL_FORMAT" "$FIRST" "$LAST" 2> "$err_file") || rc=$?
  if [ "$rc" -ne 0 ] || grep -qE 'critical|Traceback' "$err_file"; then
    rc=0
    out=$(khal list --format "$KHAL_FORMAT" "$FIRST_EU" "$LAST_EU" 2> "$err_file") || rc=$?
  fi
  if [ "$rc" -ne 0 ] || grep -qE 'critical|Traceback' "$err_file"; then
    local first_error
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
  local file raw mtime age
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
  if ! raw=$(curl --fail --silent --show-error --location --max-time 8 \
    --user-agent "pleamar-calendar/1.0" "$HOLIDAY_BASE/PublicHolidays/$YEAR/$COUNTRY" 2>&1); then
    HOLIDAY_ERROR="holidays request failed: ${raw##*$'\n'}"
    return 0
  fi
  mkdir -p -- "$CACHE_DIR"
  if printf '%s' "$raw" | jq -c . > "$CACHE_DIR/.holidays.$$.tmp" 2> /dev/null; then
    mv -f -- "$CACHE_DIR/.holidays.$$.tmp" "$file"
  fi
  HOLIDAYS_JSON=$(printf '%s' "$raw" | jq -c --arg m "$MONTH" '
    [ .[] | select((.date // "") | startswith($m))
      | {date: .date, name: .localName, name_en: .name} ]')
  return 0
}

# Print one month line: cache when fresh, otherwise a khal run.
run_once() {
  local cache_file c_month c_fetched age events payload cached
  NOW=$(date +%s)
  cache_file="$CACHE_DIR/calendar-$MONTH.json"
  if [ -f "$cache_file" ]; then
    c_month=$(jq -r '.month // ""' "$cache_file" 2> /dev/null || true)
    c_fetched=$(jq -r '.fetched_at // 0' "$cache_file" 2> /dev/null || true)
    age=$((NOW - c_fetched))
    if [ "$c_month" = "$MONTH" ] && [ "$age" -lt 120 ]; then
      payload=$(jq -c --argjson now "$NOW" \
        '{month, first, last, events, holidays, holidays_error, fetched_at,
          cached: true, age_s: ($now - (.fetched_at // $now))}' "$cache_file")
      emit_ok "$payload"
      return 0
    fi
  fi
  ERR_MSG=""
  if ! khal_list_month; then
    emit_err "$ERR_MSG"
    return 1
  fi
  events=$(parse_events "$KHAL_TEXT")
  holidays_json
  cached=false
  payload=$(jq -cn --arg month "$MONTH" --arg first "$FIRST" --arg last "$LAST" \
    --argjson events "$events" --argjson holidays "$HOLIDAYS_JSON" \
    --arg holi_err "$HOLIDAY_ERROR" --argjson now "$NOW" --argjson cached "$cached" \
    '{month:$month, first:$first, last:$last, events:$events, holidays:$holidays,
      holidays_error:(if $holi_err == "" then null else $holi_err end),
      fetched_at:$now, cached:$cached, age_s:0}')
  mkdir -p -- "$CACHE_DIR"
  cached=true
  jq -cn --arg month "$MONTH" --arg first "$FIRST" --arg last "$LAST" \
    --argjson events "$events" --argjson holidays "$HOLIDAYS_JSON" \
    --arg holi_err "$HOLIDAY_ERROR" --argjson now "$NOW" --argjson cached "$cached" \
    '{month:$month, first:$first, last:$last, events:$events, holidays:$holidays,
      holidays_error:(if $holi_err == "" then null else $holi_err end),
      fetched_at:$now, cached:$cached}' > "$CACHE_DIR/.calendar.$$.tmp"
  mv -f -- "$CACHE_DIR/.calendar.$$.tmp" "$cache_file"
  emit_ok "$payload"
  return 0
}

if [ "$WATCH" -eq 1 ]; then
  while :; do
    run_once || true
    sleep "$INTERVAL"
  done
else
  run_once || true
  exit 0
fi
