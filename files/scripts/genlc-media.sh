#!/usr/bin/env bash
# Genelec SAM volume control via media keys
# Usage: genlc-media.sh {up|down|mute}

STEP=3  # dB per keypress

case "${1:-}" in
  up|down)
    current=$(genlc status --json 2>/dev/null | jq -r '.volume // -40')
    if [ -z "$current" ] || [ "$current" = "null" ]; then current=-40; fi
    if [ "$1" = "up" ]; then
      target=$((current + STEP))
      [ "$target" -gt -25 ] && target=-25  # cap
    else
      target=$((current - STEP))
      [ "$target" -lt -95 ] && target=-95  # floor
    fi
    genlc set-volume --volume="${target}dB"
    ;;
  mute)
    genlc set-mute
    ;;
  *) echo "Usage: $0 {up|down|mute}" >&2; exit 1 ;;
esac
