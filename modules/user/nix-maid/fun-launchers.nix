{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
  mkIf ((config.features.fun.enable or false) && (config.features.gui.enable or false)) {
    programs.lutris = {
      enable = true;
      winePackages = [
        pkgs.wineWow64Packages.full # full 32/64-bit Wine
      ];
    };
  }
