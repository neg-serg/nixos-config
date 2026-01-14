{
  lib,
  pkgs,

  nyxt4 ? null,
  ...
}:
let
  nyxtPkg =
    if nyxt4 != null then
      nyxt4
    else if lib.hasAttr "nyxt4-bin" pkgs then
      pkgs.nyxt4-bin # nyxt 4 (binary)
    else
      pkgs.nyxt; # nyxt (source)
  # Floorp upstream source package is deprecated in nixpkgs >= 12.x; always use floorp-bin.
  floorpPkg = pkgs.floorp-bin;
in
{
  firefox = {
    name = "firefox";
    pkg = pkgs.firefox;
    bin = lib.getExe' pkgs.firefox "firefox";
    desktop = "firefox.desktop";
    newTabArg = "-new-tab";
  };
  librewolf = {
    name = "librewolf";
    pkg = pkgs.librewolf;
    bin = lib.getExe' pkgs.librewolf "librewolf";
    desktop = "librewolf.desktop";
    newTabArg = "-new-tab";
  };
  nyxt = {
    name = "nyxt";
    pkg = nyxtPkg;
    bin = lib.getExe' nyxtPkg "nyxt";
    desktop = "nyxt.desktop";
    newTabArg = "";
  };
  floorp = {
    name = "floorp";
    pkg = floorpPkg;
    bin = lib.getExe' floorpPkg "floorp";
    desktop = "floorp.desktop";
    newTabArg = "-new-tab";
  };
  chrome = {
    name = "chrome";
    pkg = pkgs.google-chrome;
    bin = lib.getExe' pkgs.google-chrome "google-chrome-stable";
    desktop = "google-chrome.desktop";
    newTabArg = "--new-tab";
  };
  brave = {
    name = "brave";
    pkg = pkgs.brave;
    bin = lib.getExe' pkgs.brave "brave";
    desktop = "brave-browser.desktop";
    newTabArg = "--new-tab";
  };
  vivaldi = {
    name = "vivaldi";
    pkg = pkgs.vivaldi;
    bin = lib.getExe' pkgs.vivaldi "vivaldi";
    desktop = "vivaldi-stable.desktop";
    newTabArg = "--new-tab";
  };
  edge = {
    name = "edge";
    pkg = pkgs.microsoft-edge;
    bin = lib.getExe' pkgs.microsoft-edge "microsoft-edge";
    desktop = "microsoft-edge.desktop";
    newTabArg = "--new-tab";
  };
}
