{
  lib,
  pkgs,

  ...
}:
let
  # Floorp upstream source package is deprecated in nixpkgs >= 12.x; always use floorp-bin.
  floorpPkg = pkgs.floorp-bin;
in
{
  floorp = {
    name = "floorp";
    pkg = floorpPkg;
    bin = lib.getExe' floorpPkg "floorp";
    desktop = "floorp.desktop";
    newTabArg = "-new-tab";
  };
  zen = {
    name = "zen";
    pkg = pkgs.zen-browser; # Zen Browser (Firefox-based), stable channel from zen-browser flake
    bin = lib.getExe' pkgs.zen-browser "zen-beta";
    desktop = "zen-beta.desktop";
    newTabArg = "-new-tab";
  };
}
