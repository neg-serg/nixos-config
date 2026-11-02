#!/usr/bin/env bash
# journal.sh - journal snapshot worker (pleamar helper; protocol: INTERFACES.md §7).
#
# The system dashboard (the `system` drawer) shows what the reference's
# SystemMonitorPopup shows: how many lines the journal wrote in the last day,
# how many of them were errors, how many user services are running, and the last
# few entries with a time, a unit and a message.
#
# Unlike the sampling workers this one does not stream: it prints one JSON
# object and exits, so the scene spawns it when the drawer opens and reads a
# single line.
#
#   {"ok":true,"worker":"journal","version":1,
#    "data":{"logs":N,"errors":N,"services":N,
#            "entries":[{"time":"14:32","service":"x.service","msg":"…"}]}}
#
# Usage: journal.sh [--since "-24h"] [--entries N] [--help]
#
# Exit: 0 on success, 1 when journalctl or systemctl is missing.

set -euo pipefail

SINCE="-24h"
ENTRIES=8

while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      SINCE="${2:-}"
      shift 2
      ;;
    --entries)
      ENTRIES="${2:-8}"
      shift 2
      ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "journal: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

command -v journalctl > /dev/null || {
  echo "journal: journalctl not found" >&2
  exit 1
}
command -v jq > /dev/null || {
  echo "journal: jq not found" >&2
  exit 1
}

logs=$(journalctl --user --since "$SINCE" --no-pager -o cat 2> /dev/null | wc -l) || logs=0
errors=$(journalctl --user --since "$SINCE" -p err --no-pager -o cat 2> /dev/null | wc -l) || errors=0
services=$(systemctl --user list-units --type=service --state=running --no-legend 2> /dev/null | wc -l) || services=0

entries=$(
  journalctl --user --since "$SINCE" -p warning --no-pager -o json \
    --output-fields=__REALTIME_TIMESTAMP,_SYSTEMD_UNIT,SYSLOG_IDENTIFIER,MESSAGE -n "$ENTRIES" 2> /dev/null \
    | jq -s -c '[ .[] | {
        time: ((.__REALTIME_TIMESTAMP | tonumber? // 0) / 1000000 | strflocaltime("%H:%M")),
        service: (._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "journal"),
        msg: ((.MESSAGE // "") | if type == "array" then join(" ") else tostring end | .[0:120])
      } ]' 2> /dev/null || echo '[]'
)
[ -n "$entries" ] || entries='[]'

jq -n -c \
  --argjson logs "$logs" --argjson errors "$errors" --argjson services "$services" \
  --argjson entries "$entries" \
  '{ok:true, worker:"journal", version:1,
    data:{logs:$logs, errors:$errors, services:$services, entries:$entries}}'
