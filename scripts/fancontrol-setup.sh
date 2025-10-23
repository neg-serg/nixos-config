#!/usr/bin/env bash
set -eu

echo "fancontrol-setup: probing hwmon devices" >&2

# Locate Nuvoton/ASUS Super I/O (nct6775*) hwmon for PWM control
nct_path=""
for d in /sys/class/hwmon/hwmon*; do
  if [ -f "$d/name" ] && grep -Eiq '^nct' "$d/name"; then
    nct_path="$d"; break
  fi
done
if [ -z "$nct_path" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if readlink -f "$d" | grep -q 'nct'; then
      nct_path="$d"; break
    fi
  done
fi
if [ -z "$nct_path" ]; then
  echo "fancontrol-setup: no nct6775 hwmon found; skipping generation" >&2
  exit 0
fi

# Prefer AMD CPU sensor (k10temp); fall back to ASUS EC if needed
cpu_path=""
for d in /sys/class/hwmon/hwmon*; do
  if [ -f "$d/name" ] && grep -Eiq 'k10temp' "$d/name"; then
    cpu_path="$d"; break
  fi
done
if [ -z "$cpu_path" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && grep -Eiq 'asusec' "$d/name"; then
      cpu_path="$d"; break
    fi
  done
fi
if [ -z "$cpu_path" ]; then
  echo "fancontrol-setup: no CPU temperature sensor found; skipping" >&2
  exit 0
fi

# Optional AMDGPU hwmon for GPU fan control
gpu_path=""
if [ "${GPU_ENABLE:-false}" = "true" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && grep -Eiq '^amdgpu$' "$d/name"; then
      gpu_path="$d"; break
    fi
  done
fi

# Build DEVPATH/DEVNAME map with stable keys (hwmon1=nct, hwmon2=cpu, hwmon3=gpu [optional])
devs=""; names=""; idx=1
add_dev() {
  local path="$1"
  local name=$(cat "$path/name")
  # Prefer devices/... tail for DEVPATH; otherwise full path
  local full=$(readlink -f "$path")
  local devpath=$(printf '%s\n' "$full" | sed -n 's#^.*/\(devices/.*\)$#\1#p')
  [ -n "$devpath" ] || devpath="$full"
  devs="$devs hwmon$idx=$devpath"
  names="$names hwmon$idx=$name"
  idx=$((idx+1))
}
add_dev "$nct_path"
add_dev "$cpu_path"
[ -n "$gpu_path" ] && add_dev "$gpu_path"

# Tuning from environment (provided via systemd service Environment=)
MIN_TEMP=${MIN_TEMP:-35}
MAX_TEMP=${MAX_TEMP:-75}
MIN_PWM=${MIN_PWM:-70}
MAX_PWM=${MAX_PWM:-255}
HYST=${HYST:-3}
INTERVAL=${INTERVAL:-2}

fcfans=""; fctemps=""; mintemp=""; maxtemp=""; minpwm=""; maxpwm=""; hyst=""
found_pwm=0
for pwm in "$nct_path"/pwm[1-9]; do
  [ -e "$pwm" ] || continue
  base=$(basename "$pwm")      # pwmN
  n=${base#pwm}
  fan="$nct_path/fan${n}_input"
  [ -e "$fan" ] || continue
  found_pwm=1

  fcfans="$fcfans hwmon1/$base=hwmon1/fan${n}_input"
  # Use CPU temp for control (quiet and safe)
  fctemps="$fctemps hwmon1/$base=hwmon2/temp1_input"
  mintemp="$mintemp hwmon1/$base=$MIN_TEMP"
  maxtemp="$maxtemp hwmon1/$base=$MAX_TEMP"
  minpwm="$minpwm hwmon1/$base=$MIN_PWM"
  maxpwm="$maxpwm hwmon1/$base=$MAX_PWM"
  hyst="$hyst hwmon1/$base=$HYST"

  # Switch to manual control so fancontrol can drive it
  if [ -w "${pwm}_enable" ]; then
    echo 1 > "${pwm}_enable" || true
  fi
done

if [ "$found_pwm" -ne 1 ]; then
  echo "fancontrol-setup: found nct6775 but no PWM-capable fans; skipping" >&2
  exit 0
fi

# Optionally add AMDGPU fan (pwm1) controlled by GPU temp (prefer junction temp2 if exists)
if [ -n "$gpu_path" ] && [ -e "$gpu_path/pwm1" ]; then
  # Choose temperature input: temp2_input (junction) preferred, else temp1_input (edge)
  gtemp="$gpu_path/temp2_input"
  [ -e "$gtemp" ] || gtemp="$gpu_path/temp1_input"
  if [ -e "$gtemp" ] && [ -e "$gpu_path/fan1_input" ]; then
    fcfans="$fcfans hwmon3/pwm1=hwmon3/fan1_input"
    fctemps="$fctemps hwmon3/pwm1=hwmon3/$(basename "$gtemp")"
    GPU_MIN_TEMP=${GPU_MIN_TEMP:-50}
    GPU_MAX_TEMP=${GPU_MAX_TEMP:-85}
    GPU_MIN_PWM=${GPU_MIN_PWM:-70}
    GPU_MAX_PWM=${GPU_MAX_PWM:-255}
    GPU_HYST=${GPU_HYST:-3}
    mintemp="$mintemp hwmon3/pwm1=$GPU_MIN_TEMP"
    maxtemp="$maxtemp hwmon3/pwm1=$GPU_MAX_TEMP"
    minpwm="$minpwm hwmon3/pwm1=$GPU_MIN_PWM"
    maxpwm="$maxpwm hwmon3/pwm1=$GPU_MAX_PWM"
    hyst="$hyst hwmon3/pwm1=$GPU_HYST"
    # Switch GPU fan to manual control
    if [ -w "$gpu_path/pwm1_enable" ]; then echo 1 > "$gpu_path/pwm1_enable" || true; fi
  fi
fi

umask 022
cat > /etc/fancontrol.auto <<EOF
INTERVAL=$INTERVAL
DEVPATH=${devs# }
DEVNAME=${names# }
FCTEMPS=${fctemps# }
FCFANS=${fcfans# }
MINTEMP=${mintemp# }
MAXTEMP=${maxtemp# }
MINPWM=${minpwm# }
MAXPWM=${maxpwm# }
HYSTERESIS=${hyst# }
EOF

# Preserve any manual config once (backup) and point fancontrol to the generated profile
if [ ! -L /etc/fancontrol ] && [ -f /etc/fancontrol ]; then
  cp -n /etc/fancontrol /etc/fancontrol.backup || true
fi
ln -sf /etc/fancontrol.auto /etc/fancontrol
echo "fancontrol-setup: wrote /etc/fancontrol.auto and symlinked /etc/fancontrol" >&2

