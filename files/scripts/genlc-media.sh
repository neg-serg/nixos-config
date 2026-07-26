#!/usr/bin/env bash
# Genelec SAM volume control — debounced, 0.5dB steps
# Works in half-dB units internally, converts to dB for genlc
set -euo pipefail

HALF_STEP=1       # 0.5dB per wheel click
STATE=/tmp/genlc-volume-halves  # stored as half-dB integer
DEBOUNCE=/tmp/genlc-debounce
PIDFILE=/tmp/genlc-debounce.pid
LOG=/tmp/genlc-media.log
MAX_HALF=-60      # -30dB
MIN_HALF=-190     # -95dB

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }
to_dB() { awk "BEGIN { printf \"%.1f\", $1 / 2 }"; }

case "${1:-}" in
  up)   ;;
  down) ;;
  mute) log "mute"; genlc mute >> "$LOG" 2>&1; exit 0 ;;
  *)    exit 1 ;;
esac

# Kill previous pending timer
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true

# Accumulate delta (in half-dB units)
delta=0
[ -f "$DEBOUNCE" ] && delta=$(cat "$DEBOUNCE" 2>/dev/null || echo 0) || true
if [ "$1" = "up" ]; then
  echo $((delta + HALF_STEP)) > "$DEBOUNCE"
else
  echo $((delta - HALF_STEP)) > "$DEBOUNCE"
fi

# Fork debounce timer
(
  sleep 0.25 || true
  d=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
  [ "$d" = "0" ] && { log "debounce: delta=0"; exit 0; }
  echo 0 > "$DEBOUNCE"
  
  # Read current volume (half-dB), default -40dB = -80
  current=-80
  [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || echo -80) || true
  
  target=$((current + d))
  [ "$target" -gt "$MAX_HALF" ] && target=$MAX_HALF
  [ "$target" -lt "$MIN_HALF" ] && target=$MIN_HALF
  
  db=$(to_dB "$target")
  log "apply: half=${target} db=${db}dB (was half=${current} delta=${d})"
  if genlc set-volume --volume="${db}dB" >> "$LOG" 2>&1; then
    echo "$target" > "$STATE"; echo "${db}" > /tmp/genlc-volume
    log "OK: ${db}dB"
  else
    log "FAIL"
  fi
) &
echo $! > "$PIDFILE"
