{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  guiEnabled = config.features.gui.enable or false;
  qtEnabled = config.features.gui.qt.enable or false;
  quickshellEnabled =
    guiEnabled
    && qtEnabled
    && (config.features.gui.quickshell.enable or false)
    && (!(config.features.devSpeed.enable or false));
  hostSystem = pkgs.stdenv.hostPlatform.system;
  rsmetrxPkg =
    if inputs ? rsmetrx then
      lib.attrByPath [ "packages" hostSystem "default" ] null inputs.rsmetrx
    else
      null;
  rofiPackages = [
    config.neg.rofi.package # main themed rofi build for this profile
    pkgs.gopass # password store with extensions
  ];
  quickshellExtras = lib.optionals (rsmetrxPkg != null) [
    rsmetrxPkg # rsmetrx shader pack for Quickshell HUDs
  ];
in
{
  config = lib.mkMerge [
    (lib.mkIf guiEnabled {
      environment.systemPackages = lib.mkAfter rofiPackages;
    })
    (lib.mkIf quickshellEnabled {
      environment.systemPackages = lib.mkAfter quickshellExtras;
    })
  ];

  # Available GUI tools (from stone-recipes, ported for future use):
  # pkgs.blender # 3D creation suite
  # pkgs.iverilog # Verilog simulator
  # pkgs.wofi # Wayland launcher (rofi alternative)
  # pkgs.ytop # TUI system monitor written in Rust
}
