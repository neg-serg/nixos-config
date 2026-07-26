#!/usr/bin/env bash
# Genelec SAM volume control — keyboard wheel
# Only updates state files. QML handles genlc dispatch.
set -euo pipefail

HALF_STEP=1       # 0.5dB per click  
STATE=/tmp/genlc-volume-halves
LOG=/tmp/genlc-media.log
MAX_HALF=-60      # -30dB
MIN_HALF=-190     # -95dB

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }

case "${1:-}" in
  up|down)
    current=-80
    [ -f "$STATE" ] && current=$(cat "$STATE" 2>/dev/null || echo -80) || true
    
    if [ "$1" = "up" ]; then
      target=$((current + HALF_STEP))
    else
      target=$((current - HALF_STEP))
    fi
    
    [ "$target" -gt "$MAX_HALF" ] && target=$MAX_HALF
    [ "$target" -lt "$MIN_HALF" ] && target=$MIN_HALF
    
    echo "$target" > "$STATE"
    awk "BEGIN { printf \"%.1f\", $target / 2 }" > /tmp/genlc-volume
    log "wheel: $(awk "BEGIN { printf \"%.1f\", $target / 2 }")dB"
    ;;
  mute)
    genlc mute >> "$LOG" 2>&1 || true
    log "mute"
    ;;
  *) exit 1 ;;
esac
