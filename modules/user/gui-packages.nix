{
  lib,
  config,
  pkgs,
  inputs ? {},
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  qtEnabled = config.features.gui.qt.enable or false;
  quickshellEnabled = guiEnabled && qtEnabled && (config.features.gui.quickshell.enable or false) && (! (config.features.devSpeed.enable or false));
  hostSystem = pkgs.stdenv.hostPlatform.system;
  rsmetrxPkg =
    if inputs ? rsmetrx
    then lib.attrByPath ["packages" hostSystem "default"] null inputs.rsmetrx
    else null;
  rofiPackages = [
    config.neg.rofi.package
    pkgs.rofi-pass-wayland
    pkgs.rofi-systemd
  ];
  quickshellExtras = lib.optionals (rsmetrxPkg != null) [rsmetrxPkg];
in {
  config = lib.mkMerge [
    (lib.mkIf guiEnabled {
      environment.systemPackages = lib.mkAfter rofiPackages;
    })
    (lib.mkIf quickshellEnabled {
      environment.systemPackages = lib.mkAfter quickshellExtras;
    })
  ];
}
