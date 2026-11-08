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
  onDemand = config.lib.neg.onDemand pkgs;
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
