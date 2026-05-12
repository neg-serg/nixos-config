{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = import ../../../lib/systemd-user.nix { inherit lib; };
in
with lib;
mkIf (config.features.gui.enable or false) (
  lib.mkMerge [
    {
      systemd.user.services.ydotoold =
        let
          preset = systemdUser.mkUnitFromPresets { presets = [ "defaultWanted" ]; };
        in
        {
          description = "ydotool virtual input daemon";
          serviceConfig = {
            ExecStart =
              let
                exe = lib.getExe' pkgs.ydotool "ydotoold"; # Generic Linux command-line automation tool
              in
              "${exe}";
            Restart = "on-failure";
            RestartSec = "2";
            Slice = "background-graphical.slice";
            # Run unprivileged; uinput access comes from the group. Avoid any
            # capability tweaking because systemd --user cannot adjust caps.
          };
          after = preset.Unit.After or [ ];
          wants = preset.Unit.Wants or [ ];
          partOf = preset.Unit.PartOf or [ ];
          wantedBy = preset.Install.WantedBy or [ ];
        };
    }
  ]
)
