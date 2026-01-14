{
  pkgs,
  lib,
  config,
  ...
}:
{
  environment.systemPackages = lib.unique (
    (lib.optionals (config.features.hardware.bluetooth.enable or false) [
      # -- Bluetooth --
      pkgs.bluez-tools # command line bluetooth manager
      pkgs.overskride # bluetooth and obex client
    ])
    ++ [
      # -- Display --
      pkgs.brightnessctl # backlight control helper

      # -- Network --
      pkgs.wirelesstools # iwconfig/ifrename CLI helpers

      # -- System Info --
      pkgs.acpi # ACPI probing utilities
      pkgs.hwinfo # detailed hardware inventory
      pkgs.inxi # summary hardware inspector
      pkgs.lshw # Linux hardware lister
      pkgs.neg.ls_iommu # IOMMU group lister for VFIO planning

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
