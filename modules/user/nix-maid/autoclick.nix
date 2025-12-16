{
  lib,
  config,
  pkgs,
  systemdUser,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      systemd.user.services.ydotoold = lib.mkMerge [
        {
          Unit.Description = "ydotool virtual input daemon";
          Service = {
            ExecStart = let exe = lib.getExe' pkgs.ydotool "ydotoold"; in "${exe}";
            Restart = "on-failure";
            RestartSec = "2";
            Slice = "background-graphical.slice";
            # Run unprivileged; uinput access comes from the group. Avoid any
            # capability tweaking because systemd --user cannot adjust caps.
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
      ];
    }
  ])
