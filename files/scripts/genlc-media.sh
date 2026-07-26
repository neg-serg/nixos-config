#!/usr/bin/env bash
# Genelec SAM volume control — called from hyprland media keys
case "${1:-}" in
  up)   genlc set-volume --volume="-5dB" --relative ;;  # +5dB relative
  down) genlc set-volume --volume="-5dB" --relative-down ;; # -5dB relative
  mute) genlc set-mute ;;
  *)    echo "Usage: $0 {up|down|mute}" >&2; exit 1 ;;
esac
