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
      # moved to devShells.virt
      # pkgs.guestfs-tools
      # pkgs.lima
      # pkgs.quickemu

      # -- Wine --
      pkgs.dxvk # setup script for DXVK
      pkgs.vkd3d # DX12 for Wine
      pkgs.wineWowPackages.staging # Wine (staging) for Windows apps
      pkgs.winetricks # helpers for Wine (e.g., DXVK)
    ];
  };
}
