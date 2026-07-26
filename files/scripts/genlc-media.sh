#!/usr/bin/env bash
# Genelec SAM volume control via media keys
# Stores volume in /tmp/genlc-volume (initialized from last set)
STEP=3
STATE=/tmp/genlc-volume

case "${1:-}" in
  up|down|mute) ;;
  *) echo "Usage: $0 {up|down|mute}" >&2; exit 1 ;;
esac

# Read current volume, default -40
current=-40
[ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null) || true
if [ -z "$current" ] || ! [ "$current" -eq "$current" ] 2>/dev/null; then current=-40; fi

if [ "$1" = "mute" ]; then
  genlc mute
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
