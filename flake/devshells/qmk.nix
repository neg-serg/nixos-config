{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.qmk # Program to help users work with QMK Firmware
    pkgs.qmk_hid # Commandline tool for interactng with QMK devices over HID
    pkgs.keymapviz # Qmk keymap.c visualizer
  ];
}
