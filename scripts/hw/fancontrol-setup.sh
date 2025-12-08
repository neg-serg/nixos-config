#!/usr/bin/env bash
set -eu

echo "fancontrol-setup: probing hwmon devices" >&2

# Locate Nuvoton/ASUS Super I/O (nct6775*) hwmon for PWM control
nct_path=""
for d in /sys/class/hwmon/hwmon*; do
  if [ -f "$d/name" ] && grep -Eiq '^nct' "$d/name"; then
    nct_path="$d"
    break
  fi
done
if [ -z "$nct_path" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if readlink -f "$d" | grep -q 'nct'; then
      nct_path="$d"
      break
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
    cpu_path="$d"
    break
  fi
done
if [ -z "$cpu_path" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && grep -Eiq 'asusec' "$d/name"; then
      cpu_path="$d"
      break
    fi
  done
fi
if [ -z "$cpu_path" ]; then
  echo "fancontrol-setup: no CPU temperature sensor found; skipping" >&2
  exit 0
fi

# Choose the most suitable CPU temperature input:
#  - Prefer Tdie when available (actual die temperature)
#  - Else fall back to Tctl (control temperature, may include offset)
#  - Else use temp1_input
cpu_temp_name="temp1_input"
if ls "$cpu_path"/temp*_label > /dev/null 2>&1; then
  tdie=""
  tctl=""
  for lab in "$cpu_path"/temp*_label; do
    [ -e "$lab" ] || continue
    name=$(< "$lab")
    n=${lab##*/}
    n=${n%_label}
    if echo "$name" | grep -Eiq '^tdie$'; then
      tdie="${n}_input"
      break
    fi
    if echo "$name" | grep -Eiq '^tctl$'; then
      tctl="${n}_input"
    fi
  done
  if [ -n "$tdie" ]; then
    cpu_temp_name="$tdie"
  elif [ -n "$tctl" ]; then
    cpu_temp_name="$tctl"
  fi
fi

# Optional AMDGPU hwmon for GPU fan control
gpu_path=""
if [ "${GPU_ENABLE:-false}" = "true" ]; then
  for d in /sys/class/hwmon/hwmon*; do
    if [ -f "$d/name" ] && grep -Eiq '^amdgpu$' "$d/name"; then
      gpu_path="$d"
      break
    fi
  done
fi

# Build DEVPATH/DEVNAME map with stable keys (hwmon1=nct, hwmon2=cpu, hwmon3=gpu [optional])
devs=""
names=""
idx=1
add_dev() {
  local path="$1"
  local base=$(basename "$path") # actual hwmonN symlink name
  local name=$(cat "$path/name")
  # Align with fancontrol's expected DEVPATH: the real device target of $hwmon/device
  local devtarget=$(readlink -f "$path/device" 2> /dev/null || true)
  if [ -n "$devtarget" ]; then
    # Strip leading /sys/
    devtarget=${devtarget#/sys/}
  else
    # Fallback to full path without /sys/
    local full=$(readlink -f "$path")
    devtarget=${full#/sys/}
  fi
  devs="$devs $base=$devtarget"
  names="$names $base=$name"
}
# Record actual hwmon symlink basenames for later use
nct_base=$(basename "$nct_path")
cpu_base=$(basename "$cpu_path")
[ -n "$gpu_path" ] && gpu_base=$(basename "$gpu_path") || gpu_base=""

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
ALLOW_STOP=${ALLOW_STOP:-false}
GPU_PWM_CHANNELS=${GPU_PWM_CHANNELS:-}

# Derive safe start/stop PWM thresholds used by fancontrol
# MINSTART should be high enough to reliably spin up a stopped fan.
# MINSTOP is the minimum PWM during regulation. Keep <= MINSTART.
# Choose a conservative default: start slightly above MIN_PWM.
START_DELTA=${START_DELTA:-20}
calc_minstart() {
  local v=$((MIN_PWM + START_DELTA))
  [ "$v" -gt "$MAX_PWM" ] && v=$MAX_PWM
  echo "$v"
}
if [ "$ALLOW_STOP" = "true" ]; then
  # Allow fans to stop: keep MINSTOP=0 and use a higher MINSTART to ensure reliable spin-up
  MIN_START_DEFAULT=${MIN_START_OVERRIDE:-100}
  MIN_STOP_DEFAULT=0
  EFF_MIN_PWM=0
else
  MIN_START_DEFAULT=$(calc_minstart)
  MIN_STOP_DEFAULT=$MIN_PWM
  EFF_MIN_PWM=$MIN_PWM
fi

fcfans=""
fctemps=""
mintemp=""
maxtemp=""
minpwm=""
maxpwm=""
minstart=""
minstop=""
hyst=""
found_pwm=0

# Prepare optional GPU temperature name for case-fan control mapping
gpu_temp_name=""
if [ -n "$gpu_path" ]; then
  gtemp="$gpu_path/temp2_input"
  if ls "$gpu_path"/temp*_label > /dev/null 2>&1; then
    gjunc=""
    gedge=""
    for lab in "$gpu_path"/temp*_label; do
      [ -e "$lab" ] || continue
      name=$(< "$lab")
      n=${lab##*/}
      n=${n%_label}
      if echo "$name" | grep -Eiq 'junction'; then
        gjunc="${n}_input"
        break
      fi
      if echo "$name" | grep -Eiq 'edge'; then
        gedge="${n}_input"
      fi
    done
    if [ -n "$gjunc" ]; then
      gpu_temp_name="$gjunc"
    elif [ -n "$gedge" ]; then
      gpu_temp_name="$gedge"
    fi
  fi
  if [ -z "$gpu_temp_name" ]; then
    [ -e "$gtemp" ] && gpu_temp_name=$(basename "$gtemp") || gpu_temp_name=""
  fi
fi

# Parse list of motherboard PWM channels that should follow GPU temperature
IFS=',' read -r -a gpu_pwm_arr <<< "$GPU_PWM_CHANNELS"
for pwm in "$nct_path"/pwm[1-9]; do
  [ -e "$pwm" ] || continue
  base=$(basename "$pwm") # pwmN
  n=${base#pwm}
  fan="$nct_path/fan${n}_input"
  [ -e "$fan" ] || continue
  found_pwm=1

  fcfans="$fcfans $nct_base/$base=$nct_base/fan${n}_input"
  # Use GPU temp for selected channels, else CPU temp
  use_gpu_temp=false
  for ch in "${gpu_pwm_arr[@]}"; do
    [ -n "$ch" ] || continue
    if [ "$ch" = "$n" ]; then
      use_gpu_temp=true
      break
    fi
  done
  if [ "$use_gpu_temp" = true ] && [ -n "$gpu_path" ] && [ -n "$gpu_temp_name" ]; then
    fctemps="$fctemps $nct_base/$base=$gpu_base/$gpu_temp_name"
  else
    fctemps="$fctemps $nct_base/$base=$cpu_base/$cpu_temp_name"
  fi
  mintemp="$mintemp $nct_base/$base=$MIN_TEMP"
  maxtemp="$maxtemp $nct_base/$base=$MAX_TEMP"
  minpwm="$minpwm $nct_base/$base=$EFF_MIN_PWM"
  maxpwm="$maxpwm $nct_base/$base=$MAX_PWM"
  minstart="$minstart $nct_base/$base=$MIN_START_DEFAULT"
  minstop="$minstop $nct_base/$base=$MIN_STOP_DEFAULT"
  hyst="$hyst $nct_base/$base=$HYST"

  # Switch to manual control so fancontrol can drive it
  if [ -w "${pwm}_enable" ]; then
    echo 1 > "${pwm}_enable" || true
  fi
done

if [ "$found_pwm" -ne 1 ]; then
  echo "fancontrol-setup: found nct6775 but no PWM-capable fans; skipping" >&2
  exit 0
fi

# Optionally add AMDGPU fan (pwm1) controlled by GPU temp (prefer Junction when labeled)
if [ -n "$gpu_path" ] && [ -e "$gpu_path/pwm1" ]; then
  # Choose temperature input by label when available (junction preferred)
  gtemp="$gpu_path/temp2_input"
  if ls "$gpu_path"/temp*_label > /dev/null 2>&1; then
    gjunc=""
    gedge=""
    for lab in "$gpu_path"/temp*_label; do
      [ -e "$lab" ] || continue
      name=$(< "$lab")
      n=${lab##*/}
      n=${n%_label}
      if echo "$name" | grep -Eiq 'junction'; then
        gjunc="${n}_input"
        break
      fi
      if echo "$name" | grep -Eiq 'edge'; then
        gedge="${n}_input"
      fi
    done
    if [ -n "$gjunc" ]; then
      gtemp="$gpu_path/$gjunc"
    elif [ -n "$gedge" ]; then
      gtemp="$gpu_path/$gedge"
    else
      [ -e "$gtemp" ] || gtemp="$gpu_path/temp1_input"
    fi
  else
    [ -e "$gtemp" ] || gtemp="$gpu_path/temp1_input"
  fi
  if [ -e "$gtemp" ] && [ -e "$gpu_path/fan1_input" ]; then
    # Try to switch GPU fan to manual control first; skip if not allowed
    if [ -w "$gpu_path/pwm1_enable" ]; then echo 1 > "$gpu_path/pwm1_enable" 2> /dev/null || true; fi
    if [ ! -r "$gpu_path/pwm1_enable" ] || [ "$(cat "$gpu_path/pwm1_enable" 2> /dev/null)" != "1" ]; then
      echo "fancontrol-setup: GPU pwm1 manual control not available; skipping GPU" >&2
    else
      fcfans="$fcfans $gpu_base/pwm1=$gpu_base/fan1_input"
      fctemps="$fctemps $gpu_base/pwm1=$gpu_base/$(basename "$gtemp")"
      GPU_MIN_TEMP=${GPU_MIN_TEMP:-50}
      GPU_MAX_TEMP=${GPU_MAX_TEMP:-85}
      GPU_MIN_PWM=${GPU_MIN_PWM:-70}
      GPU_MAX_PWM=${GPU_MAX_PWM:-255}
      GPU_HYST=${GPU_HYST:-3}
      mintemp="$mintemp $gpu_base/pwm1=$GPU_MIN_TEMP"
      maxtemp="$maxtemp $gpu_base/pwm1=$GPU_MAX_TEMP"
      if [ "$ALLOW_STOP" = "true" ]; then
        minpwm="$minpwm $gpu_base/pwm1=0"
      else
        minpwm="$minpwm $gpu_base/pwm1=$GPU_MIN_PWM"
      fi
      maxpwm="$maxpwm $gpu_base/pwm1=$GPU_MAX_PWM"
      # Derive GPU MINSTART/MINSTOP similarly; respect allow-stop for GPU if global ALLOW_STOP is set
      if [ "$ALLOW_STOP" = "true" ]; then
        gstart=${MIN_START_OVERRIDE:-100}
        minstart="$minstart $gpu_base/pwm1=$gstart"
        minstop="$minstop $gpu_base/pwm1=0"
      else
        gstart=$((GPU_MIN_PWM + START_DELTA))
        [ "$gstart" -gt "$GPU_MAX_PWM" ] && gstart=$GPU_MAX_PWM
        minstart="$minstart $gpu_base/pwm1=$gstart"
        minstop="$minstop $gpu_base/pwm1=$GPU_MIN_PWM"
      fi
      hyst="$hyst $gpu_base/pwm1=$GPU_HYST"
    fi
  fi
fi

umask 022
cat > /etc/fancontrol.auto << EOF
INTERVAL=$INTERVAL
DEVPATH=${devs# }
DEVNAME=${names# }
FCTEMPS=${fctemps# }
FCFANS=${fcfans# }
MINTEMP=${mintemp# }
MAXTEMP=${maxtemp# }
MINPWM=${minpwm# }
MAXPWM=${maxpwm# }
MINSTART=${minstart# }
MINSTOP=${minstop# }
HYSTERESIS=${hyst# }
EOF

# Preserve any manual config once (backup) and point fancontrol to the generated profile
if [ ! -L /etc/fancontrol ] && [ -f /etc/fancontrol ]; then
  cp -n /etc/fancontrol /etc/fancontrol.backup || true
fi
ln -sf /etc/fancontrol.auto /etc/fancontrol
echo "fancontrol-setup: wrote /etc/fancontrol.auto and symlinked /etc/fancontrol" >&2
