{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  pyprlandEnabled = config.features.gui.enable;
in
  mkIf pyprlandEnabled {
    systemd.user.services.pyprland = {
      Unit = {
        Description = "Pyprland - Hyprland plugin system";
        Documentation = "https://github.com/hyprland-community/pyprland";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session-pre.target"];
      };

      Service = {
        ExecStart = "${lib.getExe pkgs.pyprland}";
        Restart = "on-failure";
        RestartSec = 1;
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  }
