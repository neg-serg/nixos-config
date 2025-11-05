#!/usr/bin/env bash
# Probe whether motherboard PWM channels support full stop (0% PWM -> 0 RPM)
#
# - Finds Nuvoton/ASUS Super I/O (nct67xx) hwmon device
# - Skips CPU/PUMP channels by default for safety
# - Temporarily switches a PWM channel to manual, sets PWM=0, waits, checks RPM
# - Restores the original pwmN/pwmN_enable values
#
# Usage:
#   sudo scripts/fan-stop-capability-test.sh [--include-cpu] [--device <hwmon-path|name>] \
#       [--wait <sec>] [--threshold <rpm>] [--list]
#
# Options:
#   --include-cpu   Include channels labeled CPU/CPU_OPT/PUMP/AIO (unsafe by default)
#   --device X      Test a specific hwmon (path like /sys/class/hwmon/hwmonN or name like nct6798)
#   --wait S        Seconds to wait after PWM change (default: 6)
#   --threshold R   RPM threshold considered "stopped" (default: 50)
#   --list          Only list detected devices and channels, no testing

set -euo pipefail

WAIT_SECS=6
THRESH=50
INCLUDE_CPU=false
TARGET_DEVICE=""
LIST_ONLY=false

die() { echo "error: $*" >&2; exit 1; }
info() { echo "[i] $*"; }
warn() { echo "[!] $*"; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "run as root (sudo)"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-cpu) INCLUDE_CPU=true; shift ;;
      --device) TARGET_DEVICE=${2:-}; [[ -n "$TARGET_DEVICE" ]] || die "--device requires value"; shift 2 ;;
      --wait) WAIT_SECS=${2:-}; [[ "$WAIT_SECS" =~ ^[0-9]+$ ]] || die "--wait must be integer"; shift 2 ;;
      --threshold) THRESH=${2:-}; [[ "$THRESH" =~ ^[0-9]+$ ]] || die "--threshold must be integer"; shift 2 ;;
      --list) LIST_ONLY=true; shift ;;
      -h|--help) sed -n '1,80p' "$0"; exit 0 ;;
      *) die "unknown arg: $1" ;;
    esac
  done
}

hwmon_name() { local p="$1"; cat "$p/name" 2>/dev/null || true; }

is_nct() {
  local p="$1"; local n; n=$(hwmon_name "$p");
  if [[ "$n" =~ ^nct ]]; then return 0; fi
  if readlink -f "$p" | grep -q 'nct'; then return 0; fi
  return 1
}

find_hwmons() {
  local d
  for d in /sys/class/hwmon/hwmon*; do
    [[ -d "$d" ]] || continue
    if is_nct "$d"; then echo "$d"; fi
  done
}

match_device() {
  local d name
  for d in $(find_hwmons); do
    name=$(hwmon_name "$d")
    if [[ "$TARGET_DEVICE" == "$d" || "$TARGET_DEVICE" == "$name" ]]; then
      echo "$d"; return 0
    fi
  done
  return 1
}

label_for() { local base="$1" idx="$2"; cat "$base/fan${idx}_label" 2>/dev/null || true; }
fan_input_path() { local base="$1" idx="$2"; [[ -f "$base/fan${idx}_input" ]] && echo "$base/fan${idx}_input" || true; }

is_cpu_like_label() {
  local L="${1,,}"
  [[ "$L" =~ cpu ]] || [[ "$L" =~ pump ]] || [[ "$L" =~ aio ]] || [[ "$L" =~ opt ]] || [[ "$L" =~ pch ]]
}

list_channels() {
  local base="$1"; local p idx lbl fin
  for p in "$base"/pwm[1-9]; do
    [[ -e "$p" ]] || continue
    idx=${p##*pwm}
    lbl=$(label_for "$base" "$idx")
    fin=$(fan_input_path "$base" "$idx")
    printf "  - pwm%s (%s)%s\n" "$idx" "${lbl:-no-label}" "${fin:+ -> fan${idx}}"
  done
}

test_channel() {
  local base="$1" idx="$2" lbl="$3"
  local pwm="$base/pwm${idx}" en="$base/pwm${idx}_enable" fin="$base/fan${idx}_input"
  [[ -e "$pwm" && -w "$pwm" ]] || { warn "pwm${idx}: not writable, skipping"; return; }
  [[ -e "$en"  && -w "$en"  ]] || { warn "pwm${idx}_enable: not writable, skipping"; return; }
  [[ -e "$fin" ]] || { warn "fan${idx}_input: missing, skipping"; return; }

  if [[ "$INCLUDE_CPU" == false ]]; then
    if is_cpu_like_label "$lbl"; then
      info "pwm${idx}: skipping CPU/PUMP-labeled channel ('$lbl')"
      return
    fi
  fi

  local orig_en orig_pwm
  orig_en=$(cat "$en" 2>/dev/null || echo 2)
  orig_pwm=$(cat "$pwm" 2>/dev/null || echo 0)

  local base_rpm stop_rpm new_pwm
  base_rpm=$(cat "$fin" 2>/dev/null || echo 0)

  info "pwm${idx} ('$lbl'): baseline ${base_rpm} RPM; switching to manual and testing 0%"

  # switch to manual
  if ! echo 1 > "$en" 2>/dev/null; then
    warn "pwm${idx}: cannot set manual mode, skipping"
    return
  fi

  # set to 0% and wait
  if ! echo 0 > "$pwm" 2>/dev/null; then
    warn "pwm${idx}: write 0 failed (HW clamp?), skipping"
    echo "$orig_pwm" > "$pwm" 2>/dev/null || true
    echo "$orig_en"  > "$en"  2>/dev/null || true
    return
  fi

  sleep "$WAIT_SECS"
  stop_rpm=$(cat "$fin" 2>/dev/null || echo 0)
  new_pwm=$(cat "$pwm" 2>/dev/null || echo 0)

  # restore
  echo "$orig_pwm" > "$pwm" 2>/dev/null || true
  echo "$orig_en"  > "$en"  2>/dev/null || true

  if [[ "$new_pwm" -ne 0 ]]; then
    echo "    result: NOT SUPPORTED (controller clamped PWM to $new_pwm)"
    return
  fi

  if [[ "$stop_rpm" -le "$THRESH" ]]; then
    echo "    result: SUPPORTED (RPM ${stop_rpm} <= ${THRESH})"
  else
    echo "    result: NOT SUPPORTED (RPM stayed at ${stop_rpm} > ${THRESH})"
  fi
}

main() {
  parse_args "$@"
  need_root

  local fanctl_active=0
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet fancontrol 2>/dev/null; then
      fanctl_active=1
      warn "fancontrol.service is active; it may fight this test. Consider 'systemctl stop fancontrol' for accurate results."
    fi
  fi

  local devices=()
  if [[ -n "$TARGET_DEVICE" ]]; then
    local m
    if m=$(match_device); then devices+=("$m"); else die "device not found: $TARGET_DEVICE"; fi
  else
    mapfile -t devices < <(find_hwmons)
  fi

  [[ ${#devices[@]} -gt 0 ]] || die "no nct* hwmon device found"

  local d name
  for d in "${devices[@]}"; do
    name=$(hwmon_name "$d")
    echo "Device: $d (name: ${name:-unknown})"
    list_channels "$d"
    if [[ "$LIST_ONLY" == true ]]; then
      continue
    fi
    for p in "$d"/pwm[1-9]; do
      [[ -e "$p" ]] || continue
      local idx lbl
      idx=${p##*pwm}
      lbl=$(label_for "$d" "$idx")
      test_channel "$d" "$idx" "${lbl:-no-label}"
    done
    echo
  done

  if [[ $fanctl_active -eq 1 ]]; then
    warn "fancontrol.service was active. If results look odd, rerun with the service stopped."
  fi
}

main "$@"

