{
  lib,
  pkgs,
  systemdUser,
  ...
}:
{
  systemdTargets = {
    hyprland-session = {
      unitConfig = {
        Description = "Hyprland compositor session";
        Documentation = [ "man:systemd.special(7)" ];
        BindsTo = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
      };
    };
  };

  systemdServices = {
    # Hyprland Polkit Agent
    hyprpolkitagent = systemdUser.mkUserService {
      presets = [
        "graphicalWanted"
        "restartOnFailure"
      ];
      description = "Hyprland Polkit Agent";
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"; # Polkit authentication agent written in QT/QML
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
          "XDG_CURRENT_DESKTOP=Hyprland"
        ];
        RestartSec = "2s";
      };
    };

    # Screen time tracker: polls `hyprctl activewindow` every 200 ms and writes
    # per class/window-title time into ~/.local/share/niri-screen-time/db.db.
    # Read it back with `niri-screen-time [-from=YYYY-MM-DD -to=YYYY-MM-DD]`.
    niri-screen-time = {
      description = "Screen time tracker (per window class / title)";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.neg.niri-screen-time} -daemon";
        Environment = [
          # The binary selects its compositor backend from XDG_CURRENT_DESKTOP
          # and panics on an unknown value; the systemd user environment does
          # not carry the session's value.
          "XDG_CURRENT_DESKTOP=Hyprland"
          "XDG_SESSION_TYPE=wayland"
        ];
        Restart = "always";
        RestartSec = "2";
      };
    };
  };
}
