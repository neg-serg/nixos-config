{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  guiEnabled = config.lib.neg.enabled "gui";
  quickshellEnabled = config.lib.neg.quickshellEnabled;
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
