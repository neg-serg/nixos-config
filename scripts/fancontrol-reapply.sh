#!/usr/bin/env bash
set -eu

case "${1:-}" in
  post)
    # Re-enable manual control for motherboard PWM via nct6775
    for d in /sys/class/hwmon/hwmon*; do
      if [ -f "$d/name" ] && grep -Eiq '^nct' "$d/name"; then
        for en in "$d"/pwm[1-9]_enable; do
          [ -e "$en" ] || continue
          echo 1 > "$en" 2>/dev/null || true
        done
      fi
    done
    # Re-enable AMDGPU pwm1 if configured
    if [ "@GPU_ENABLE@" = "true" ]; then
      for d in /sys/class/hwmon/hwmon*; do
        if [ -f "$d/name" ] && grep -Eiq '^amdgpu$' "$d/name"; then
          [ -w "$d/pwm1_enable" ] && echo 1 > "$d/pwm1_enable" 2>/dev/null || true
        fi
      done
    fi
    # Nudge fancontrol in case device state changed
    systemctl try-restart fancontrol.service >/dev/null 2>&1 || true
    ;;
esac

