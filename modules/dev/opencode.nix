{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.opencode.enable or false);
in
lib.mkIf enable {
  environment.systemPackages = [
    pkgs.opencode # AI coding agent built for the terminal
    (pkgs.makeDesktopItem {
      name = "opencode";
      desktopName = "OpenCode";
      exec = "opencode";
      terminal = true;
      icon = "utilities-terminal";
      categories = [ "Development" ];
    })
  ];
}
