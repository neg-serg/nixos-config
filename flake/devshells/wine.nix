{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  packages = [
    pkgs.dxvk # setup script for DXVK
    pkgs.vkd3d # DX12 for Wine
    pkgs.wineWow64Packages.staging # Wine (staging) for Windows apps
    pkgs.winetricks # helpers for Wine (e.g., DXVK)
    pkgs.wineWow64Packages.full # full 32/64-bit Wine
  ];
}
