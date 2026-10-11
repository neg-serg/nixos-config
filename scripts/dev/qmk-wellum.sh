#!/usr/bin/env bash
set -euo pipefail

# Wellum keymap for the Ferris Sweep: install the keymap into a QMK firmware
# checkout, compile it, and flash both halves.
#
# Usage: scripts/dev/qmk-wellum.sh [build|flash]   (default: flash)
#
# Environment:
#   QMK_HOME            QMK firmware checkout (default: ~/src/qmk_firmware).
#   WELLUM_CONVERT      Pro Micro -> RP2040 converter target, default
#                       "rp2040_ce" (Sea-Picro, Elite-Pi, RP2040 Pro Micro
#                       clones). Use "sparkfun_pm2040" for the SparkFun Pro
#                       Micro RP2040, or an empty string for an AVR Pro
#                       Micro/Elite-C build.
#   WELLUM_BOOTLOADER   QMK bootloader override for `qmk flash -bl`, e.g. dfu
#                       on an Elite-C.
#
# The keymap sources live in files/hardware/qmk/ferris-sweep/wellum/ (a copy
# of wellum firmware/qmk, revision recorded in that directory's README.md).

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root)"

QMK_HOME="${QMK_HOME:-$HOME/src/qmk_firmware}"
export QMK_HOME
KEYBOARD="ferris/sweep"
KEYMAP="wellum"
CONVERT="${WELLUM_CONVERT-rp2040_ce}"
SRC_DIR="$REPO_ROOT/files/hardware/qmk/ferris-sweep/wellum"
KEYMAP_DIR="$QMK_HOME/keyboards/ferris/sweep/keymaps/$KEYMAP"

mode="${1:-flash}"
case "$mode" in
  build | flash) ;;
  *)
    echo "usage: $0 [build|flash]" >&2
    exit 2
    ;;
esac

# Keep in sync with the source directory: QMK only sees the oneshot/swapper
# helpers when they sit next to keymap.c.
keymap_files=(keymap.c oneshot.c oneshot.h rules.mk swapper.c swapper.h)

if [[ ! -d "$QMK_HOME/.git" ]]; then
  echo "==> Cloning QMK firmware into $QMK_HOME"
  mkdir -p "$(dirname "$QMK_HOME")"
  git clone --depth 1 https://github.com/qmk/qmk_firmware "$QMK_HOME"
fi

# AVR builds (Pro Micro/Elite-C) link against LUFA; RP2040 builds go through
# ChibiOS with the RP port and the Pi Pico SDK. QMK errors out when the
# submodules it needs are missing.
if [[ -n "$CONVERT" ]]; then
  submodules=(lib/chibios lib/chibios-contrib lib/pico-sdk)
else
  submodules=(lib/lufa)
fi
echo "==> Ensuring required QMK submodules (${submodules[*]})"
git -C "$QMK_HOME" submodule update --init --depth 1 "${submodules[@]}"

echo "==> Installing the Wellum keymap into $KEYMAP_DIR"
mkdir -p "$KEYMAP_DIR"
for file in "${keymap_files[@]}"; do
  install -m 0644 "$SRC_DIR/$file" "$KEYMAP_DIR/$file"
done

# The converter turns the AVR Pro Micro pin names of ferris/sweep into RP2040
# GPIOs, so one keyboard definition serves both controller families.
build_args=(-kb "$KEYBOARD" -km "$KEYMAP")
if [[ -n "$CONVERT" ]]; then
  build_args+=(-e "CONVERT_TO=$CONVERT")
fi

echo "==> Building $KEYBOARD:$KEYMAP${CONVERT:+ (CONVERT_TO=$CONVERT)}"

# Everything runs inside the repo's pinned QMK devshell (avr-gcc,
# arm-none-eabi-gcc, avrdude, ...), so the host needs no global QMK install.
qmk_shell() {
  nix --option substitute false develop "$REPO_ROOT#qmk" --command "$@"
}

qmk_shell qmk compile "${build_args[@]}"

if [[ "$mode" == build ]]; then
  echo "==> Firmware written under $QMK_HOME/.build"
  exit 0
fi

flash_args=(qmk flash "${build_args[@]}")
if [[ -n "${WELLUM_BOOTLOADER:-}" ]]; then
  flash_args+=(-bl "$WELLUM_BOOTLOADER")
fi

for half in left right; do
  echo
  echo "==> $half half: put its controller into the bootloader"
  echo "    RP2040: hold BOOTSEL while plugging in USB (or double-tap reset once"
  echo "    flashed with QMK); Pro Micro/Elite-C: tap reset, or hold the top"
  echo "    outer key (top-left on the left half, top-right on the right half)"
  echo "    while plugging in USB. QMK waits for the bootloader device."
  read -r -p "    Press Enter when the $half half is ready (Ctrl-C aborts): "
  qmk_shell "${flash_args[@]}"
done

echo "==> Done: both halves are running Wellum."
