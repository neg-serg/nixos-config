#!/usr/bin/env bash
# Genelec SAM volume control — debounced
# Accumulates deltas, applies once after 250ms of inactivity
set -euo pipefail

STEP=3
STATE=/tmp/genlc-volume
DEBOUNCE=/tmp/genlc-debounce
PIDFILE=/tmp/genlc-debounce.pid
LOG=/tmp/genlc-media.log

log() { echo "[$(date +%H:%M:%S.%3N)] $*" >> "$LOG"; }

case "${1:-}" in
  up)   ;;
  down) ;;
  mute) log "mute"; genlc mute 2>&1 | head -1 >> "$LOG"; exit 0 ;;
  *)    exit 1 ;;
esac

# Kill previous pending timer
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null

# Accumulate delta
delta=0
[ -f "$DEBOUNCE" ] && delta=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
if [ "$1" = "up" ]; then
  new_delta=$((delta + STEP))
  log "wheel up: delta ${delta}→${new_delta}"
  echo "$new_delta" > "$DEBOUNCE"
else
  new_delta=$((delta - STEP))
  log "wheel down: delta ${delta}→${new_delta}"
  echo "$new_delta" > "$DEBOUNCE"
fi

# Fork debounce timer — read state FRESH inside subshell
(
  sleep 0.25
  d=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
  [ "$d" = "0" ] && { log "debounce: delta=0, skip"; exit 0; }
  echo 0 > "$DEBOUNCE"
  
  # Read current volume FRESH (not inherited — avoids stale value)
  current=-40
  [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || true)
  if [ -z "$current" ] || ! [ "$current" -eq "$current" ] 2>/dev/null; then current=-40; fi
  
  target=$((current + d))
  [ "$target" -gt -30 ] && { log "cap: ${target}→-30"; target=-30; }
  [ "$target" -lt -95 ] && { log "floor: ${target}→-95"; target=-95; }
  
  log "apply: ${current}dB + ${d} = ${target}dB"
  if genlc set-volume --volume="${target}dB" 2>&1 | head -1 >> "$LOG"; then
    echo "$target" > "$STATE"
    log "OK: saved ${target}dB to state"
  else
    log "FAIL: genlc error"
  fi
) &
echo $! > "$PIDFILE"
