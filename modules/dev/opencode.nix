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
    pkgs.herdr # Agent multiplexer for AI coding agents
    pkgs.nodejs # Node.js runtime — required by MCP servers (npx) and git hooks
    (pkgs.makeDesktopItem {
      name = "opencode";
      desktopName = "OpenCode";
      exec = "${pkgs.opencode}/bin/opencode";
      terminal = true;
      icon = "utilities-terminal";
      categories = [ "Development" ];
    })
  ];
}
