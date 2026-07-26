#!/usr/bin/env bash
# Genelec SAM volume control — debounced: only fires when wheel stops
# Accumulates delta, applies once after 250ms of inactivity
STEP=3
STATE=/tmp/genlc-volume
DEBOUNCE=/tmp/genlc-debounce
PIDFILE=/tmp/genlc-debounce.pid

case "${1:-}" in
  up)   ;;
  down) ;;
  mute) genlc mute 2>/dev/null; exit 0 ;;
  *)    exit 1 ;;
esac

# Kill previous pending timer
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null

# Accumulate delta
delta=0
[ -f "$DEBOUNCE" ] && delta=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
[ "$1" = "up" ] && echo $((delta + STEP)) > "$DEBOUNCE"
[ "$1" = "down" ] && echo $((delta - STEP)) > "$DEBOUNCE"

# Fork debounce timer
(
  sleep 0.25
  d=$(cat "$DEBOUNCE" 2>/dev/null || echo 0)
  [ "$d" = "0" ] && exit 0
  echo 0 > "$DEBOUNCE"
  
  current=-40
  [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || true)
  if [ -z "$current" ] || ! [ "$current" -eq "$current" ] 2>/dev/null; then current=-40; fi
  
  target=$((current + d))
  [ "$target" -gt -30 ] && target=-30
  [ "$target" -lt -95 ] && target=-95
  genlc set-volume --volume="${target}dB" 2>/dev/null && echo "$target" > "$STATE"
) &
echo $! > "$PIDFILE"
