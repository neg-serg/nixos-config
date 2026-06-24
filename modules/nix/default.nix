{ ... }:
{
  imports = [
    ./bpftrace.nix
    ./hyprland.nix
    ./multimon-ng.nix
    ./packages-overlay.nix
    ./settings.nix
    ./wb32-dfu-updater.nix
  ];
}
