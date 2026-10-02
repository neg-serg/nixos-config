{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (config.lib.neg.enabled "gui") (
  lib.mkMerge [
    {
      systemd.user.services.ydotoold = systemdUser.mkUserService {
        description = "ydotool virtual input daemon";
        presets = [
          "defaultWanted"
          "restartOnFailure"
        ];
        serviceConfig = {
          # Generic Linux command-line automation tool
          ExecStart = lib.getExe' pkgs.ydotool "ydotoold";
          RestartSec = "2";
          Slice = "background-graphical.slice";
          # Run unprivileged; uinput access comes from the group. Avoid any
          # capability tweaking because systemd --user cannot adjust caps.
        };
      };
    }
  ]
)
