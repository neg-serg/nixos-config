{...}: {
  imports = [
    ./bpftrace.nix
    ./hyprland.nix
    ./mpv-openvr.nix
    ./multimon-ng.nix
    ./nix-ld.nix

    ./packages-overlay.nix
    ./settings.nix
    ./wb32-dfu-updater.nix
  ];
}
