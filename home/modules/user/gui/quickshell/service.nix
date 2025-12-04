{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  quickshellEnabled =
    config.features.gui.enable
    && (config.features.gui.qt.enable or false)
    && (config.features.gui.quickshell.enable or false)
    && (! (config.features.devSpeed.enable or false));

  # Use the wrapped package if available, otherwise fallback to standard package
  qsPkg = config.neg.quickshell.wrapperPackage;
  qsBin =
    if qsPkg != null
    then lib.getExe qsPkg
    else "${pkgs.quickshell}/bin/quickshell";
in
  mkIf quickshellEnabled {
    systemd.user.services.quickshell = {
      Unit = {
        Description = "Quickshell - QtQuick based shell for Wayland";
        Documentation = "https://github.com/outfoxxed/quickshell";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session-pre.target"];
      };

      Service = {
        ExecStart = "${qsBin} -p %h/.config/quickshell/shell.qml";
        Restart = "on-failure";
        RestartSec = 1;
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  }
