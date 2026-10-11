{ pkgs, ... }:
let
  # The nixpkgs QMK CLI already propagates its flashing and AVR build
  # toolchain (avrdude, dfu tools, avr-gcc, make), so only fixes belong here.
  # This host builds without binary substitutes: avrdude's default PDF docs
  # drag in a full TeX Live, so build it doc-less and hand that copy to QMK.
  qmkPkgs = pkgs.extend (
    final: prev: {
      avrdude = prev.avrdude.override { docSupport = false; };
      qmk = prev.qmk.override { avrdude = final.avrdude; };
    }
  );
in
{
  nativeBuildInputs = [
    qmkPkgs.qmk # Program to help users work with QMK Firmware (flash tools included)
    qmkPkgs.qmk_hid # Commandline tool for interactng with QMK devices over HID
    pkgs.keymapviz # Qmk keymap.c visualizer
    pkgs.git # QMK CLI uses git for submodule and version handling
    pkgs.picotool # RP2040 BOOTSEL flashing, for RP2040-based Sweep revisions
  ];
}
