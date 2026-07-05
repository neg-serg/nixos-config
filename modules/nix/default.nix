{ ... }:
{
  imports = [
    ./clblast.nix # OpenCL BLAS for GPU-accelerated compute
    ./hyprland.nix
    ./multimon-ng.nix
    ./packages-overlay.nix
    ./settings.nix
    ./wb32-dfu-updater.nix
  ];
}
