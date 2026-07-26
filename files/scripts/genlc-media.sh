#!/usr/bin/env bash
# Genelec SAM volume control via media keys
# Rate-limited: max 1 command per 200ms to prevent GLM adapter overload
STEP=3
STATE=/tmp/genlc-volume
LOCK=/tmp/genlc-media.lock

# Rate limit: skip if last call was <200ms ago
now=$(date +%s%3N)  # milliseconds
if [ -f "$LOCK" ]; then
  last=$(cat "$LOCK" 2>/dev/null || echo 0)
  if [ $((now - last)) -lt 200 ]; then
    exit 0  # too soon, skip
  fi
fi
echo "$now" > "$LOCK"

case "${1:-}" in
  up|down|mute) ;;
  *) echo "Usage: $0 {up|down|mute}" >&2; exit 1 ;;
esac

# Read current volume, default -40
current=-40
[ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null) || true
if [ -z "$current" ] || ! [ "$current" -eq "$current" ] 2>/dev/null; then current=-40; fi

if [ "$1" = "mute" ]; then
  genlc mute 2>/dev/null
  exit 0
fi

if [ "$1" = "up" ]; then
  target=$((current + STEP))
  [ "$target" -gt -30 ] && target=-30
else
  target=$((current - STEP))
  [ "$target" -lt -95 ] && target=-95
fi

genlc set-volume --volume="${target}dB" 2>/dev/null && echo "$target" > "$STATE"
