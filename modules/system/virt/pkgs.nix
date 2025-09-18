{
  pkgs,
  lib,
  config,
  ...
}: let
  vmEnabled = (config.profiles.vm or {enable = false;}).enable;
in {
  config = lib.mkIf (!vmEnabled) {
    environment.systemPackages = [
      pkgs.ctop # container metrics TUI
      pkgs.dive # inspect Docker image layers
      pkgs.dxvk # setup script for DXVK
      pkgs.guestfs-tools # virt-sysprep et al.
      pkgs.lima # run Linux VMs
      pkgs.nerdctl # Docker-compatible CLI for containerd
      pkgs.podman-compose # compose for Podman
      pkgs.podman-tui # Podman status TUI
      pkgs.quickemu # fast/simple VM builder
      pkgs.vkd3d # DX12 for Wine
      pkgs.wineWowPackages.staging # Wine (staging) for Windows apps
      pkgs.winetricks # helpers for Wine (e.g., DXVK)
    ];
  };
}
