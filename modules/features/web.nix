{ lib, mkBool, ... }:
with lib;
{
  options.features.web = {
    enable = mkBool "enable Web stack (browsers + tools)" true;
    default = mkOption {
      type = types.enum [
        "zen"
      ];
      default = "zen";
      description = "Default browser used for XDG handlers, \$BROWSER, and integrations.";
    };
    tools.enable = mkBool "enable web tools (aria2, yt-dlp, misc)" true;
    aria2.service.enable = mkBool "run aria2 download manager as a user service (graphical preset)" false;
    floorp = {
      enable = mkBool "enable Floorp browser" false;
    };

    zen.enable = mkBool "enable Zen browser (package only; profile managed manually)" true;
    prefs = {
      fastfox.enable = mkBool "enable FastFox-like perf prefs for Mozilla browsers" true;
    };
    chat = {
      enable = mkBool "enable Telegram chat client (depends on webkitgtk via telegram-desktop)" true;
    };
  };
}
