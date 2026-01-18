{
  lib,
  pkgs,

  ...
}:
let
    else
  # Floorp upstream source package is deprecated in nixpkgs >= 12.x; always use floorp-bin.
  floorpPkg = pkgs.floorp-bin; # Fork of Firefox that seeks balance between versatility, p...
in
{
  firefox = {
    name = "firefox";
    pkg = pkgs.firefox; # Web browser built from Firefox source tree
    bin = lib.getExe' pkgs.firefox "firefox"; # Web browser built from Firefox source tree
    desktop = "firefox.desktop";
    newTabArg = "-new-tab";
  };
  librewolf = {
    name = "librewolf";
    pkg = pkgs.librewolf; # Fork of Firefox, focused on privacy, security and freedom
    bin = lib.getExe' pkgs.librewolf "librewolf"; # Fork of Firefox, focused on privacy, security and freedom
    desktop = "librewolf.desktop";
    newTabArg = "-new-tab";
  };
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
    pkg = pkgs.google-chrome; # Freeware web browser developed by Google
    bin = lib.getExe' pkgs.google-chrome "google-chrome-stable"; # Freeware web browser developed by Google
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
    pkg = pkgs.vivaldi; # Browser for our Friends, powerful and personal
    bin = lib.getExe' pkgs.vivaldi "vivaldi"; # Browser for our Friends, powerful and personal
    desktop = "vivaldi-stable.desktop";
    newTabArg = "--new-tab";
  };
  edge = {
    name = "edge";
    pkg = pkgs.microsoft-edge; # Web browser from Microsoft
    bin = lib.getExe' pkgs.microsoft-edge "microsoft-edge"; # Web browser from Microsoft
    desktop = "microsoft-edge.desktop";
    newTabArg = "--new-tab";
  };
}
