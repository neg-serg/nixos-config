#!/usr/bin/env bash
# weather.sh - weather worker (pleamar helper; protocol: INTERFACES.md §7).
#
# A scene spawns this worker while the weather view exists, subscribes to the
# `weather` topic and kills it on close. The answer is cached in a file with a
# TTL, so reopening the view does not hit the network; geocoding (city ->
# coordinates) is cached for a day. If Open-Meteo fails, wttr.in's one-line
# text format is used as a fallback (current conditions only). No API keys, no
# secrets.
#
# Protocol (README.md has the full text):
#   handshake  {"ok":true,"worker":"weather","version":1,"topics":["weather"]}
#   commands   {"cmd":"subscribe","topic":"weather","interval_ms":600000}
#              {"cmd":"sample"} {"cmd":"set","interval_ms":300000}
#              {"cmd":"unsubscribe","topic":"weather"} {"cmd":"stop"}
#   sample     {"ok":true,"worker":"weather","topic":"weather","t":<ms>,
#              "data":{city,latitude,longitude,provider,fetched_at,age_s,
#                      cached,current{temp_c,weather_code,wind_ms,
#                      wind_dir_deg,is_day,humidity_pct,pressure_hpa},
#                      daily[{date,tmax_c,tmin_c,weather_code}]}}
#   error      {"ok":false,"worker":"weather","err":"…","t":<ms>}
#
# `weather` is auto-subscribed at --interval-ms (600000 by default), so a scene
# that only reads lines gets one sample at startup; `--once` prints the
# handshake plus one sample and exits. A closed stdin finishes the worker.
#
# Usage: weather.sh [--city NAME] [--lat N --lon N] [--cache-file PATH]
#                   [--ttl SECONDS] [--force] [--interval-ms N]
#                   [--forecast-days N] [--timeout SECONDS] [--once]
#                   [--api-base URL] [--geocoding-base URL] [--wttr-base URL]
#                   [--no-fallback] [--help]
#
# Exit: 0 when stdin closes or on stop; 1 when the worker cannot start.

set -euo pipefail

usage() {
  cat << 'EOF'
weather.sh - weather worker (JSON lines, INTERFACES.md §7)

Usage:
  weather.sh [options]

Options:
  --city NAME          place to geocode (default: $PLEAMAR_WEATHER_CITY)
  --lat N --lon N      coordinates; skips geocoding (both required together)
  --cache-file PATH    cache file (default: $XDG_CACHE_HOME/pleamar/helpers/weather.json)
  --ttl SECONDS        serve a cached payload younger than this (default: 300)
  --force              ignore a fresh cache for the next fetch
  --interval-ms N      default cadence of the `weather` topic, 100..3600000
                       (default: 600000)
  --once               print the handshake and one sample, then exit
  --forecast-days N    daily entries to ask for, 1..16 (default: 5)
  --timeout SECONDS    curl timeout per request (default: 8)
  --api-base URL       Open-Meteo forecast base (default: https://api.open-meteo.com/v1)
  --geocoding-base URL Open-Meteo geocoding base
  --wttr-base URL      wttr.in fallback base (default: https://wttr.in)
  --no-fallback        do not use wttr.in when Open-Meteo fails
  -h, --help           this text

Topic: weather. Commands: subscribe, unsubscribe, set, sample, stop (one JSON
object per stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
EOF
}

WORKER=weather

die() {
  printf 'weather: error: %s\n' "$*" >&2
  exit 2
}

CITY="${PLEAMAR_WEATHER_CITY:-}"
LAT=""
LON=""
CACHE_FILE=""
TTL=300
FORCE=0
INTERVAL_MS=600000
ONCE=0
FORECAST_DAYS=5
TIMEOUT=8
API_BASE="${PLEAMAR_WEATHER_API_BASE:-https://api.open-meteo.com/v1}"
GEO_BASE="${PLEAMAR_WEATHER_GEOCODING_BASE:-https://geocoding-api.open-meteo.com/v1}"
WTTR_BASE="${PLEAMAR_WEATHER_WTTR_BASE:-https://wttr.in}"
FALLBACK=1
USER_AGENT="${PLEAMAR_WEATHER_USER_AGENT:-pleamar-weather/1.0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --city)
      [ $# -ge 2 ] || die "--city needs a value"
      CITY=$2
      shift 2
      ;;
    --lat)
      [ $# -ge 2 ] || die "--lat needs a value"
      LAT=$2
      shift 2
      ;;
    --lon)
      [ $# -ge 2 ] || die "--lon needs a value"
      LON=$2
      shift 2
      ;;
    --cache-file)
      [ $# -ge 2 ] || die "--cache-file needs a value"
      CACHE_FILE=$2
      shift 2
      ;;
    --ttl)
      [ $# -ge 2 ] || die "--ttl needs a value"
      TTL=$2
      shift 2
      ;;
    --force)
      FORCE=1
      shift
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
    --forecast-days)
      [ $# -ge 2 ] || die "--forecast-days needs a value"
      FORECAST_DAYS=$2
      shift 2
      ;;
    --timeout)
      [ $# -ge 2 ] || die "--timeout needs a value"
      TIMEOUT=$2
      shift 2
      ;;
    --api-base)
      [ $# -ge 2 ] || die "--api-base needs a value"
      API_BASE=$2
      shift 2
      ;;
    --geocoding-base)
      [ $# -ge 2 ] || die "--geocoding-base needs a value"
      GEO_BASE=$2
      shift 2
      ;;
    --wttr-base)
      [ $# -ge 2 ] || die "--wttr-base needs a value"
      WTTR_BASE=$2
      shift 2
      ;;
    --no-fallback)
      FALLBACK=0
      shift
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

is_uint() {
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
  esac
  return 0
}

is_number() {
  case "$1" in
    '' | *[!0-9.+-]*) return 1 ;;
  esac
  awk -v v="$1" 'BEGIN { exit !(v ~ /^[+-]?[0-9]+(\.[0-9]+)?$/) }'
}

if [ -n "$LAT" ] || [ -n "$LON" ]; then
  [ -n "$LAT" ] && [ -n "$LON" ] || die "--lat and --lon must be given together"
  is_number "$LAT" || die "--lat must be a number (got '$LAT')"
  is_number "$LON" || die "--lon must be a number (got '$LON')"
fi
is_uint "$TTL" || die "--ttl must be a non-negative integer (got '$TTL')"
is_uint "$INTERVAL_MS" || die "--interval-ms must be an integer (got '$INTERVAL_MS')"
[ "$INTERVAL_MS" -ge 100 ] && [ "$INTERVAL_MS" -le 3600000 ] || die "--interval-ms must be 100..3600000"
is_uint "$FORECAST_DAYS" && [ "$FORECAST_DAYS" -ge 1 ] && [ "$FORECAST_DAYS" -le 16 ] || die "--forecast-days must be 1..16"
is_uint "$TIMEOUT" && [ "$TIMEOUT" -ge 1 ] && [ "$TIMEOUT" -le 120 ] || die "--timeout must be 1..120"

if [ -z "$CACHE_FILE" ]; then
  CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/helpers/weather.json"
fi

# A worker that cannot start says so in the protocol shape and exits non-zero.
start_error() {
  printf '{"ok":false,"worker":"%s","err":"%s"}\n' "$WORKER" "$1"
  exit 1
}

if ! command -v jq > /dev/null 2>&1; then
  start_error "jq not installed"
fi
if ! command -v curl > /dev/null 2>&1; then
  start_error "curl not installed"
fi

now_ms() {
  local t=$EPOCHREALTIME
  printf '%s' "$((10#${t%.*} * 1000 + 10#${t#*.} / 1000))"
}

json_err() {
  jq -cn --arg e "$1" '{ok:false,err:$e}'
}

sample_error() {
  jq -cn --arg w "$WORKER" --arg e "$1" --argjson t "$(now_ms)" '{ok:false,worker:$w,err:$e,t:$t}'
}

ack() {
  printf '{"ok":true,"ack":"%s"}\n' "$1"
}

# One cached JSON document (empty when there is none or it is unreadable).
CACHE_JSON=""
if [ -f "$CACHE_FILE" ]; then
  CACHE_JSON=$(jq -c . "$CACHE_FILE" 2> /dev/null || true)
fi

NOW=0
HTTP_BODY=""
HTTP_ERROR=""
ERR_MSG=""
GEOCODED_AT=0
PAYLOAD=""

# Sets HTTP_BODY on 0, HTTP_ERROR on 1. Never runs in a subshell: callers
# need both globals, and error text must survive back to emit_sample.
http_get() {
  local url=$1 out
  HTTP_BODY=""
  HTTP_ERROR=""
  if ! out=$(curl --fail --silent --show-error --location --max-time "$TIMEOUT" \
    --user-agent "$USER_AGENT" "$url" 2>&1); then
    HTTP_ERROR=${out##*$'\n'}
    if [ -z "$HTTP_ERROR" ]; then
      HTTP_ERROR="curl failed"
    fi
    return 1
  fi
  HTTP_BODY=$out
  return 0
}

geocode_city() {
  local encoded lat lon
  encoded=$(jq -rn --arg c "$CITY" '$c | @uri')
  if ! http_get "$GEO_BASE/search?name=$encoded&count=1&language=en&format=json"; then
    ERR_MSG="geocoding failed: $HTTP_ERROR"
    return 1
  fi
  lat=$(printf '%s' "$HTTP_BODY" | jq -r '.results[0].latitude // empty' 2> /dev/null || true)
  lon=$(printf '%s' "$HTTP_BODY" | jq -r '.results[0].longitude // empty' 2> /dev/null || true)
  if [ -z "$lat" ] || [ -z "$lon" ]; then
    ERR_MSG="city not found: $CITY"
    return 1
  fi
  LAT=$lat
  LON=$lon
  return 0
}

# Sets PAYLOAD (normalized JSON) on 0, ERR_MSG on 1.
fetch_openmeteo() {
  local norm current_temp
  if ! http_get "$API_BASE/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,relative_humidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&wind_speed_unit=ms&timezone=auto&forecast_days=$FORECAST_DAYS"; then
    ERR_MSG="open-meteo request failed: $HTTP_ERROR"
    return 1
  fi
  current_temp=$(printf '%s' "$HTTP_BODY" | jq -r '.current.temperature_2m // empty' 2> /dev/null || true)
  if [ -z "$current_temp" ]; then
    ERR_MSG="open-meteo response has no current weather"
    return 1
  fi
  if ! norm=$(printf '%s' "$HTTP_BODY" | jq -c \
    --argjson now "$NOW" --arg city "$CITY" --argjson lat "$LAT" --argjson lon "$LON" '
      {
        city: $city, latitude: $lat, longitude: $lon,
        provider: "open-meteo", fetched_at: $now, age_s: 0, cached: false,
        current: {
          temp_c: .current.temperature_2m,
          weather_code: .current.weather_code,
          wind_ms: .current.wind_speed_10m,
          wind_dir_deg: .current.wind_direction_10m,
          is_day: .current.is_day,
          humidity_pct: .current.relative_humidity_2m,
          pressure_hpa: .current.surface_pressure
        },
        daily: [ (.daily.time // []) as $t
                 | range(0; ($t | length)) as $i
                 | { date: $t[$i],
                     tmax_c: .daily.temperature_2m_max[$i],
                     tmin_c: .daily.temperature_2m_min[$i],
                     weather_code: .daily.weathercode[$i] } ]
      }' 2> /dev/null); then
    ERR_MSG="open-meteo response could not be normalized"
    return 1
  fi
  PAYLOAD=$norm
  return 0
}

# Sets PAYLOAD on 0, ERR_MSG on 1. wttr.in's text format is deliberately
# used (its JSON stream is often truncated); there is no daily forecast.
fetch_wttr() {
  local raw temp hum wind cond pres code temp_c hum_pct wind_ms wind_dir pressure
  if ! http_get "$WTTR_BASE/$LAT,$LON?format=%c|%t|%h|%w|%C|%p|%P|%u"; then
    ERR_MSG="wttr.in request failed: $HTTP_ERROR"
    return 1
  fi
  raw=$HTTP_BODY
  IFS='|' read -r _ temp hum wind cond _ pres _ <<< "$raw"
  temp_c=$(awk -v s="$temp" 'BEGIN { if (match(s, /[-+]?[0-9]+(\.[0-9]+)?/)) print substr(s, RSTART, RLENGTH) }')
  if [ -z "$temp_c" ]; then
    ERR_MSG="wttr.in response has no temperature"
    return 1
  fi
  hum_pct=$(awk -v s="$hum" 'BEGIN { if (match(s, /[0-9]+/)) print substr(s, RSTART, RLENGTH); else print 0 }')
  wind_ms=$(awk -v s="$wind" 'BEGIN { if (match(s, /[0-9]+(\.[0-9]+)?/)) printf "%.1f", substr(s, RSTART, RLENGTH) / 3.6; else print 0 }')
  pressure=$(awk -v s="$pres" 'BEGIN { if (match(s, /[0-9]+(\.[0-9]+)?/)) print substr(s, RSTART, RLENGTH); else print 0 }')
  case "$wind" in
    "↑"*) wind_dir=0 ;;
    "↗"*) wind_dir=45 ;;
    "→"*) wind_dir=90 ;;
    "↘"*) wind_dir=135 ;;
    "↓"*) wind_dir=180 ;;
    "↙"*) wind_dir=225 ;;
    "←"*) wind_dir=270 ;;
    "↖"*) wind_dir=315 ;;
    *) wind_dir=0 ;;
  esac
  case "$cond" in
    *Thunder*) code=95 ;;
    *Snow* | *Sleet* | *Blizzard*) code=71 ;;
    *Rain* | *Drizzle* | *Shower*) code=61 ;;
    *Fog* | *Mist* | *Haze*) code=45 ;;
    *Overcast*) code=3 ;;
    *Cloud*) code=2 ;;
    *Sun* | *Clear*) code=0 ;;
    *) code=2 ;;
  esac
  PAYLOAD=$(jq -cn \
    --argjson now "$NOW" --arg city "$CITY" --argjson lat "$LAT" --argjson lon "$LON" \
    --argjson temp "$temp_c" --argjson hum "$hum_pct" --argjson wind "$wind_ms" \
    --argjson dir "$wind_dir" --argjson code "$code" --argjson pres "$pressure" '
      {
        city: $city, latitude: $lat, longitude: $lon,
        provider: "wttr.in", fetched_at: $now, age_s: 0, cached: false,
        current: {
          temp_c: $temp, weather_code: $code, wind_ms: $wind, wind_dir_deg: $dir,
          is_day: null, humidity_pct: $hum, pressure_hpa: $pres
        },
        daily: []
      }')
  return 0
}

TMP_CACHE=""
cleanup() {
  if [ -n "$TMP_CACHE" ]; then
    rm -f -- "$TMP_CACHE"
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

cache_write() {
  local payload=$1 dir tmp
  dir=$(dirname -- "$CACHE_FILE")
  mkdir -p -- "$dir"
  tmp=$(mktemp -- "$dir/.weather.XXXXXX")
  TMP_CACHE=$tmp
  jq -cn --argjson payload "$payload" \
    --arg city "$CITY" --argjson lat "$LAT" --argjson lon "$LON" \
    --argjson now "$NOW" --argjson geo "$GEOCODED_AT" \
    '{city:$city, latitude:$lat, longitude:$lon, geocoded_at:$geo,
      fetched_at:$now, payload:$payload}' > "$tmp"
  mv -f -- "$tmp" "$CACHE_FILE"
  TMP_CACHE=""
}

# Resolve coordinates from --lat/--lon, the cache, or the geocoding API.
resolve_coords() {
  local c_city c_lat c_lon c_geo age
  if [ -n "$LAT" ] && [ -n "$LON" ]; then
    GEOCODED_AT=$NOW
    return 0
  fi
  if [ -n "$CACHE_JSON" ]; then
    c_city=$(printf '%s' "$CACHE_JSON" | jq -r '.city // ""')
    c_lat=$(printf '%s' "$CACHE_JSON" | jq -r '.latitude // empty')
    c_lon=$(printf '%s' "$CACHE_JSON" | jq -r '.longitude // empty')
    c_geo=$(printf '%s' "$CACHE_JSON" | jq -r '.geocoded_at // 0')
    age=$((NOW - c_geo))
    if [ "$c_city" = "$CITY" ] && [ -n "$c_lat" ] && [ -n "$c_lon" ] && [ "$age" -lt 86400 ]; then
      LAT=$c_lat
      LON=$c_lon
      GEOCODED_AT=$c_geo
      return 0
    fi
  fi
  if [ -z "$CITY" ]; then
    ERR_MSG="no city configured (use --city, --lat/--lon or PLEAMAR_WEATHER_CITY)"
    return 1
  fi
  if ! geocode_city; then
    return 1
  fi
  GEOCODED_AT=$NOW
  return 0
}

# Fetch or serve the cache; sets PAYLOAD on 0, ERR_MSG on 1.
build_payload() {
  local c_city c_fetched c_lat c_lon age coords_ok primary_error
  NOW=$(date +%s)
  if [ "$FORCE" -eq 0 ] && [ -n "$CACHE_JSON" ]; then
    c_city=$(printf '%s' "$CACHE_JSON" | jq -r '.city // ""')
    c_fetched=$(printf '%s' "$CACHE_JSON" | jq -r '.fetched_at // 0')
    c_lat=$(printf '%s' "$CACHE_JSON" | jq -r '.latitude // empty')
    c_lon=$(printf '%s' "$CACHE_JSON" | jq -r '.longitude // empty')
    coords_ok=1
    if [ -n "$LAT" ] && [ -n "$LON" ]; then
      [ "$c_lat" = "$LAT" ] && [ "$c_lon" = "$LON" ] || coords_ok=0
    fi
    age=$((NOW - c_fetched))
    if [ "$c_city" = "$CITY" ] && [ "$coords_ok" -eq 1 ] && [ "$age" -lt "$TTL" ]; then
      PAYLOAD=$(printf '%s' "$CACHE_JSON" | jq -c --argjson now "$NOW" \
        '.payload + {cached:true, age_s:($now - (.fetched_at // $now))}')
      return 0
    fi
  fi
  if ! resolve_coords; then
    return 1
  fi
  if fetch_openmeteo; then
    cache_write "$PAYLOAD"
    FORCE=0
    return 0
  fi
  if [ "$FALLBACK" -eq 1 ]; then
    primary_error=$ERR_MSG
    if fetch_wttr; then
      cache_write "$PAYLOAD"
      FORCE=0
      return 0
    fi
    ERR_MSG="$primary_error; $ERR_MSG"
    return 1
  fi
  return 1
}

emit_sample() {
  local now
  now=$(now_ms)
  if build_payload; then
    printf '{"ok":true,"worker":"%s","topic":"weather","t":%s,"data":%s}\n' "$WORKER" "$now" "$PAYLOAD"
  else
    sample_error "$ERR_MSG"
  fi
  return 0
}

KNOWN_TOPICS="weather"
topic_known() {
  case " $KNOWN_TOPICS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

declare -A SUB_INTERVAL=()
declare -A SUB_NEXT=()
SUB_INTERVAL[weather]=$INTERVAL_MS
SUB_NEXT[weather]=0

handle_command() {
  local line=$1 parts cmd topic interval now
  parts=$(printf '%s' "$line" | jq -r '[.cmd // "", .topic // "", ((.interval_ms // "") | tostring)] | join("|")' 2> /dev/null) || {
    json_err "bad command line"
    return 0
  }
  IFS='|' read -r cmd topic interval <<< "$parts"
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
      if [ "$interval" -lt 100 ] || [ "$interval" -gt 3600000 ]; then
        json_err "interval_ms must be 100..3600000"
        return 0
      fi
      for topic in "${!SUB_INTERVAL[@]}"; do
        SUB_INTERVAL[$topic]=$interval
      done
      ack set
      ;;
    sample)
      now=$(now_ms)
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

printf '{"ok":true,"worker":"%s","version":1,"topics":["weather"]}\n' "$WORKER"

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
  emit_due_samples "$(now_ms)"
done
exit 0
