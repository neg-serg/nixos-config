{
  lib,
  pkgs,
  systemdUser,
  ...
}:
{
  systemdServices = {
    # Hypridle — idle daemon (locks to a fading black screen after 2 min; no DPMS off)
    hypridle = systemdUser.mkUserService {
      description = "Hyprland idle daemon";
      presets = [ "restartOnFailure" ];
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      # Same login-phase guard as quickshell.service: the idle daemon has no
      # business running while the login screen is up (it locks/blank the screen),
      # and nix-maid's sd-switch can start a changed unit without the session
      # target. See modules/user/session/greetd/session-wrapper.sh.
      unitConfig.ConditionPathExists = "!%t/quickshell-login/login-phase";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.hypridle}";
        RestartSec = "2";
      };
    };

    # hyprlock-sleep service temporarily disabled (2026-08-31): no lock before sleep.
    # Restore together with the hyprlock package: oneshot ExecStart hyprlock --immediate on sleep.target.
  };
}
