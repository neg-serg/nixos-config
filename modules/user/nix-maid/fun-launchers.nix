{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
  mkIf ((config.features.fun.enable or false) && (config.features.gui.enable or false)) {
    environment.systemPackages = [
      pkgs.lutris
      pkgs.wineWow64Packages.full # full 32/64-bit Wine
    ];
  }
