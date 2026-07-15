{
  lib,
  pkgs,

  ...
}:
{
  vivaldi = {
    name = "Vivaldi";
    pkg = pkgs.vivaldi;
    bin = "${lib.getExe pkgs.vivaldi}";
    desktop = "vivaldi-stable";
    newTabArg = "";
  };
}
