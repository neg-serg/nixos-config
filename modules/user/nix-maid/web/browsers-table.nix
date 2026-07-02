{
  lib,
  pkgs,

  ...
}:
{
  zen = {
    name = "zen";
    pkg = pkgs.zen-browser; # Zen Browser (Firefox-based), stable channel from zen-browser flake
    bin = lib.getExe' pkgs.zen-browser "zen-beta";
    desktop = "zen-beta.desktop";
    newTabArg = "-new-tab";
  };
}
