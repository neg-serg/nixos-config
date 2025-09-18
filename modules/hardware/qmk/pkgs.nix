{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.keymapviz # visualize QMK keymap.c
    pkgs.qmk_hid # CLI for interacting with QMK devices over HID
    pkgs.qmk # QMK Firmware helper
    pkgs.qmk-udev-rules # add QMK udev rules
  ];
}
