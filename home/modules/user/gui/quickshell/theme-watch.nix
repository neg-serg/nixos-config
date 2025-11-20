{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  filesRoot = "${config.neg.hmConfigRoot}/files";
  quickshellEnabled =
    config.features.gui.enable
    && (config.features.gui.qt.enable or false)
    && (config.features.gui.quickshell.enable or false)
    && (! (config.features.devSpeed.enable or false));
  themeRoot = filesRoot + "/quickshell/quickshell";
  buildTheme = pkgs.writeShellApplication {
    name = "quickshell-build-theme";
    runtimeInputs = [pkgs.coreutils pkgs.nodejs_24 pkgs.systemd];
    text = ''
      set -euo pipefail
      cd ${themeRoot}
      ${pkgs.nodejs_24}/bin/node Tools/build-theme.mjs --quiet
      if systemctl --user is-active -q quickshell.service; then
        systemctl --user restart quickshell.service >/dev/null 2>&1 || true
      fi
    '';
  };
in
  mkIf quickshellEnabled {
    systemd.user.services.quickshell-theme-watch = lib.mkMerge [
      {
        Unit.Description = "Watch Quickshell theme tokens";
        Service = {
          Type = "simple";
          ExecStartPre = lib.getExe buildTheme;
          ExecStart = ''
            ${pkgs.watchexec}/bin/watchexec \
              --restart \
              --watch ${themeRoot}/Theme \
              --watch ${themeRoot}/Theme/manifest.json \
              --exts json,jsonc \
              --ignore ${themeRoot}/Theme/.theme.json \
              --debounce 250ms \
              -- ${lib.getExe buildTheme}
          '';
          Restart = "on-failure";
          RestartSec = "2";
        };
      }
      (config.lib.neg.systemdUser.mkUnitFromPresets {presets = ["graphical"];})
    ];
  }
