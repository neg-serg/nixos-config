{pkgs, ...}: {
  environment.systemPackages = [
    # -- Bluetooth --
    pkgs.bluez-tools # command line bluetooth manager
    pkgs.overskride # bluetooth and obex client

    # -- Display --
    pkgs.brightnessctl # backlight control helper

    # -- Network --
    pkgs.wirelesstools # iwconfig/ifrename CLI helpers

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
  ];
}
