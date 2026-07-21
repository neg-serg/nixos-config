{ ... }:
{
  imports = [
    ./clblast.nix # OpenCL BLAS for GPU-accelerated compute
    ./hyprland.nix
    ./multimon-ng.nix
    # packages-overlay.nix removed — overlay already applied via flake/lib.nix mkPkgs
    ./settings.nix
    ./wb32-dfu-updater.nix
  ];
}
