{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";
  qtEnabled = config.lib.neg.enabled "gui.qt";
  quickshellEnabled =
    guiEnabled
    && qtEnabled
    && (config.lib.neg.enabled "gui.quickshell")
    && (!(config.lib.neg.enabled "devSpeed"));
  hostSystem = pkgs.stdenv.hostPlatform.system;
  rsmetrxPkg =
    if inputs ? rsmetrx then
      lib.attrByPath [ "packages" hostSystem "default" ] null inputs.rsmetrx
    else
      null;
  quickshellExtras = lib.optionals (rsmetrxPkg != null) [
    rsmetrxPkg # rsmetrx shader pack for Quickshell HUDs
  ];
in
{
  config = lib.mkMerge [
    (lib.mkIf guiEnabled {
      environment.systemPackages = lib.mkAfter [ pkgs.gopass ]; # password store with extensions
    })
    (lib.mkIf quickshellEnabled {
      environment.systemPackages = lib.mkAfter quickshellExtras;
    })
  ];

}
