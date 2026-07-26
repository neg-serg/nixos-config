#!/usr/bin/env bash
# Genelec SAM volume control — debounced
set -euo pipefail

STEP=3
STATE=/tmp/genlc-volume
DEBOUNCE=/tmp/genlc-debounce
PIDFILE=/tmp/genlc-debounce.pid
LOG=/tmp/genlc-media.log

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

case "${1:-}" in
  up)   ;;
  down) ;;
  mute) log "mute"; genlc mute >> "\$LOG" 2>&1; exit 0 ;;
  *)    exit 1 ;;
esac

# Kill previous pending timer (ignore errors)
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true

# Accumulate delta
delta=0
[ -f "$DEBOUNCE" ] && delta=$(cat "$DEBOUNCE" 2>/dev/null || echo 0) || true
if [ "$1" = "up" ]; then
  new_delta=$((delta + STEP))
  log "up: ${delta}→${new_delta}"
  echo "$new_delta" > "$DEBOUNCE"
else
  new_delta=$((delta - STEP))
  log "down: ${delta}→${new_delta}"
  echo "$new_delta" > "$DEBOUNCE"
fi

# Fork debounce timer
(
  sleep 0.25 || true
  d=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
  [ "$d" = "0" ] && { log "debounce: delta=0, skip"; exit 0; }
  echo 0 > "$DEBOUNCE"
  
  current=-40
  [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || echo -40) || true
  
  target=$((current + d))
  [ "$target" -gt -30 ] && { log "cap: ${target}→-30"; target=-30; }
  [ "$target" -lt -95 ] && { log "floor: ${target}→-95"; target=-95; }
  
  log "apply: ${current}dB ${d:+$d}→${target}dB"
  if genlc set-volume --volume="${target}dB" >> "$LOG" 2>&1; then
    echo "$target" > "$STATE"
    log "OK: ${target}dB"
  else
    log "FAIL"
  fi
) &
echo $! > "$PIDFILE"
