{
  pkgs,
  lib,
  config,
  ...
}:
let
  vmEnabled = (config.profiles.vm or { enable = false; }).enable;
in
{
  config = lib.mkIf (!vmEnabled) {
    environment.systemPackages = [
      # -- Container --
      pkgs.ctop # container metrics TUI
      pkgs.dive # inspect Docker image layers
      pkgs.nerdctl # Docker-compatible CLI for containerd
      pkgs.podman-compose # compose for Podman
      pkgs.podman-tui # Podman status TUI

      # -- VM --
      pkgs.guestfs-tools # virt-sysprep et al.
      pkgs.lima # run Linux VMs
      pkgs.quickemu # fast/simple VM builder

      # -- Wine --
      pkgs.dxvk # setup script for DXVK
      pkgs.vkd3d # DX12 for Wine
      pkgs.wineWowPackages.staging # Wine (staging) for Windows apps
      pkgs.winetricks # helpers for Wine (e.g., DXVK)
    ];
  };
}
