#!/usr/bin/env bash
set -euo pipefail

# Usage: fan-manual [PWM_VALUE]
# PWM_VALUE: 0-255 (default: 70)

target_pwm="${1:-70}"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Find nct6799 hwmon directory
hwmon_dir=""
for hm in /sys/class/hwmon/hwmon*; do
  if grep -q "nct6799" "$hm/name" 2> /dev/null; then
    hwmon_dir="$hm"
    break
  fi
done

if [ -z "$hwmon_dir" ]; then
  echo "Error: nct6799 hardware monitor not found."
  exit 1
fi

echo "Found nct6799 at $hwmon_dir"

echo "Stopping fancontrol service..."
systemctl stop fancontrol

# PWM channels for CPU/Case fans: 1, 4, 5, 6, 7
# PWM channels for GPU fans (to exclude): 2, 3
channels=(1 4 5 6 7)

echo "Setting CPU/Case fans to PWM $target_pwm..."

for ch in "${channels[@]}"; do
  # Enable manual control (usually 1 for manual, 5 for SmartFan, 0 for full speed sometimes but generally 1)
  # driver nct6775: 1=manual, 2=thermal cruise/auto
  if [ -f "$hwmon_dir/pwm${ch}_enable" ]; then
    echo 1 > "$hwmon_dir/pwm${ch}_enable"
    echo "$target_pwm" > "$hwmon_dir/pwm${ch}"
    echo "Set pwm${ch} to $target_pwm"
  else
    echo "Warning: $hwmon_dir/pwm${ch}_enable not found, skipping."
  fi
done

echo "Done."
echo "WARNING: GPU fans (pwm2, pwm3) are now unmanaged and locked at their last speed!"
echo "Run 'fan-auto' to restore automatic control."
