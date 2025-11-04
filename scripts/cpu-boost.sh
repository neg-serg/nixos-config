#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
cpu-boost: toggle CPU turbo/boost on Linux

Usage:
  cpu-boost status      # print current boost state
  cpu-boost on          # enable boost/turbo
  cpu-boost off         # disable boost/turbo
  cpu-boost toggle      # toggle boost state

Supports common sysfs interfaces:
  - /sys/devices/system/cpu/intel_pstate/no_turbo (Intel)
  - /sys/devices/system/cpu/cpufreq/boost (Intel/AMD cpufreq)

Note: Requires root to change state.
EOF
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "error: need root (try: sudo $0 $*)" >&2
    exit 1
  fi
}

# Detect control file
detect_iface() {
  if [[ -e /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    echo intel
    return 0
  fi
  if [[ -e /sys/devices/system/cpu/cpufreq/boost ]]; then
    echo cpufreq
    return 0
  fi
  echo none
}

get_status() {
  local iface=$1
  case "$iface" in
    intel)
      local v; v=$(< /sys/devices/system/cpu/intel_pstate/no_turbo)
      # no_turbo: 1 = boost OFF, 0 = boost ON
      if [[ "$v" == "1" ]]; then echo off; else echo on; fi
      ;;
    cpufreq)
      local v; v=$(< /sys/devices/system/cpu/cpufreq/boost)
      # boost: 1 = ON, 0 = OFF
      if [[ "$v" == "1" ]]; then echo on; else echo off; fi
      ;;
    *)
      echo unknown
      ;;
  esac
}

set_status() {
  local iface=$1 want=$2
  case "$iface" in
    intel)
      # no_turbo: 1 = disable boost, 0 = enable
      if [[ "$want" == on ]]; then echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo; else echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo; fi
      ;;
    cpufreq)
      # boost: 1 = enable, 0 = disable
      if [[ "$want" == on ]]; then echo 1 > /sys/devices/system/cpu/cpufreq/boost; else echo 0 > /sys/devices/system/cpu/cpufreq/boost; fi
      ;;
    *)
      echo "error: unsupported CPU boost interface on this system" >&2
      exit 2
      ;;
  esac
}

cmd=${1:-}
case "$cmd" in
  status|on|off|toggle) ;;
  -h|--help|help|"") usage; exit 0 ;;
  *) echo "error: unknown command: $cmd" >&2; usage; exit 1 ;;
esac

iface=$(detect_iface)
if [[ "$cmd" == status ]]; then
  echo "interface: $iface"
  echo "boost: $(get_status "$iface")"
  exit 0
fi

require_root
curr=$(get_status "$iface")
if [[ "$cmd" == toggle ]]; then
  if [[ "$curr" == on ]]; then want=off; else want=on; fi
else
  want=$cmd
fi
set_status "$iface" "$want"
echo "boost: $curr -> $want"

