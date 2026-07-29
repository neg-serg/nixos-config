#!/usr/bin/env bash
# Genelec SAM volume control — keyboard wheel
# Snaps to nearest 0.5dB, applies step, calls genlc instantly.
# Writes state file for QML display sync.
set -euo pipefail

STATE=/tmp/genlc-volume
STEP_DB=0.5
LOG=/tmp/genlc-media.log

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

case "${1:-}" in
  up|down)
    current=-40.0
    [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || echo -40.0) || true

    # Snap current to nearest 0.5 before applying step
    current=$(awk "BEGIN { printf \"%.1f\", int($current * 2 + ($current < 0 ? -0.5 : 0.5)) / 2 }")

    if [ "$1" = "up" ]; then
      target=$(awk "BEGIN { printf \"%.1f\", $current + $STEP_DB }")
      capped=$(awk "BEGIN { printf \"%.1f\", ($target > -30.0) ? -30.0 : $target }")
    else
      target=$(awk "BEGIN { printf \"%.1f\", $current - $STEP_DB }")
      capped=$(awk "BEGIN { printf \"%.1f\", ($target < -95.0) ? -95.0 : $target }")
    fi
    echo "$capped" > "$STATE"
    log "$1: ${capped}dB"
    ;;
  mute)
    # Mute goes directly to genlc — instant
    genlc set-volume --volume -95dB 2>/dev/null
    log "mute"
    ;;
  *) exit 1 ;;
esac
