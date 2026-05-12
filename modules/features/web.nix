{ lib, ... }:
with lib;
let
  mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };
in
{
  options.features.web = {
    enable = mkBool "enable Web stack (browsers + tools)" true;
    default = mkOption {
      type = types.enum [
        "floorp"
        "firefox"
        "librewolf"

        "chrome"
        "brave"
        "vivaldi"
        "edge"
      ];
      default = "floorp";
      description = "Default browser used for XDG handlers, $BROWSER, and integrations.";
    };
    tools.enable = mkBool "enable web tools (aria2, yt-dlp, misc)" true;
    aria2.service.enable = mkBool "run aria2 download manager as a user service (graphical preset)" false;
    addonsFromNUR.enable = mkBool "install Mozilla addons from NUR packages (heavier eval)" true;
    floorp = {
      enable = mkBool "enable Floorp browser" true;
    };

    firefox.enable = mkBool "enable Firefox browser" false;
    librewolf.enable = mkBool "enable LibreWolf browser" false;

    chrome.enable = mkBool "enable Google Chrome browser" true;
    brave.enable = mkBool "enable Brave browser" false;
    vivaldi.enable = mkBool "enable Vivaldi browser" false;
    edge.enable = mkBool "enable Microsoft Edge browser" false;
    prefs = {
      fastfox.enable = mkBool "enable FastFox-like perf prefs for Mozilla browsers" true;
    };
  };
}
