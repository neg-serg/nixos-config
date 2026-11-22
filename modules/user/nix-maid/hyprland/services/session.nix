{
  lib,
  pkgs,
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
    # No hyprpolkitagent unit: the desktop lives in the greetd session, and a
    # user unit runs in the user-manager session, which polkitd refuses to
    # register an agent for (the passed XDG_SESSION_ID and the caller's session
    # differ; the agent then crashes on exit). hyprland.lua starts it from the
    # compositor's session instead — see @hyprpolkitagent@ in main.nix.

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
