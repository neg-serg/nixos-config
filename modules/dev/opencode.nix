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
      exec = "${
          pkgs.writeShellScript "opencode-debug" ''
            ${pkgs.opencode}/bin/opencode --print-logs --log-level DEBUG 2> /tmp/opencode.log; sleep 10
          ''
        }";
      terminal = true;
      icon = "utilities-terminal";
      categories = [ "Development" ];
    })
  ];
}
