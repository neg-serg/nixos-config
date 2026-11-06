# Waylandar — standalone Wayland calendar widget + dashboard (Quickshell + Python).
# The package lives in packages/waylandar; the system only installs an on-demand
# launcher so the Quickshell/python closure does not enter system-path.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  quickshellEnabled = config.lib.neg.quickshellEnabled;
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  config = lib.mkIf quickshellEnabled {
    environment.systemPackages = lib.mkAfter [
      (onDemand {
        name = "waylandar";
        attr = "waylandar";
      })
    ];
  };
}
