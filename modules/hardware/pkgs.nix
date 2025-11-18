{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.overskride # bluetooth and obex client
    pkgs.brightnessctl # backlight control helper
    pkgs.wirelesstools # iwconfig/ifrename CLI helpers
  ];
}
