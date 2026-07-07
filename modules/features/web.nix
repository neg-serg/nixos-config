{ lib, mkBool, ... }:
with lib;
{
  options.features.web = {
    enable = mkBool "enable Web stack (browsers + tools)" true;
    default = mkOption {
      type = types.str;
      default = null;
      description = "Default browser used for XDG handlers, \$BROWSER, and integrations.";
    };
    tools.enable = mkBool "enable web tools (aria2, yt-dlp, misc)" true;
    aria2.service.enable = mkBool "run aria2 download manager as a user service (graphical preset)" false;

    vivaldi.enable = mkBool "enable Vivaldi browser" false;
    chat = {
      enable = mkBool "enable Telegram chat client (installed via flatpak)" true;
    };
  };
}
