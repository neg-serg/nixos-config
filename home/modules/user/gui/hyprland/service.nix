{
  config,
  lib,
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
        ExecStart = "%h/.local/bin/pypr-run";
        Restart = "always";
        RestartSec = 1;
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  }
