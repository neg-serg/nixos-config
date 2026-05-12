{
  pkgs,
  lib,
  config,
  ...
}:
let
  wifiEnabled = config.profiles.network.wifi.enable || (config.features.net.wifi.enable or false);
in
{
  environment.systemPackages = lib.unique (
    (lib.optionals (config.features.hardware.bluetooth.enable or false) [
      # -- Bluetooth --
      pkgs.bluez-tools # command line bluetooth manager
      pkgs.overskride # bluetooth and obex client
    ])
    ++ (lib.optionals wifiEnabled [
      # -- Network --
      pkgs.wirelesstools # iwconfig/ifrename CLI helpers
    ])
    ++ [
      # -- Display --
      pkgs.brightnessctl # backlight control helper

      # -- System Info --
      pkgs.acpi # ACPI probing utilities
      pkgs.hwinfo # detailed hardware inventory
      pkgs.inxi # summary hardware inspector
      pkgs.lshw # Linux hardware lister

      # -- Peripherals --
      pkgs.evhz # HID polling rate monitor
      pkgs.openrgb # peripheral RGB controller

      # -- Embedded / Firmware --
      pkgs.flashrom # firmware flashing CLI
      pkgs.minicom # serial console helper
      pkgs.openocd # on-chip debugger/JTAG helper
    ]
  );
}
