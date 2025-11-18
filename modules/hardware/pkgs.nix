{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.overskride # bluetooth and obex client
    pkgs.brightnessctl # backlight control helper
    pkgs.wirelesstools # iwconfig/ifrename CLI helpers
    pkgs.acpi # ACPI probing utilities
    pkgs.hwinfo # detailed hardware inventory
    pkgs.inxi # summary hardware inspector
    pkgs.lshw # Linux hardware lister
    pkgs.evhz # HID polling rate monitor
    pkgs.openrgb # peripheral RGB controller
    pkgs.flashrom # firmware flashing CLI
    pkgs.minicom # serial console helper
    pkgs.openocd # on-chip debugger/JTAG helper
  ];
}
