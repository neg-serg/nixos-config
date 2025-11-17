{
  lib,
  config,
  pkgs,
  systemdUser,
  ...
}:
with lib; let
  scriptText = builtins.readFile ./local-bin/scripts/autoclick-toggle;
  mkLocalBin = import ../../packages/lib/local-bin.nix {inherit lib;};
in
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      home.packages = config.lib.neg.pkgsList [pkgs.ydotool];

      systemd.user.services.ydotoold = lib.mkMerge [
        {
          Unit.Description = "ydotool virtual input daemon";
          Service = {
            ExecStart = let exe = lib.getExe' pkgs.ydotool "ydotoold"; in "${exe}";
            Restart = "on-failure";
            RestartSec = "2";
            Slice = "background-graphical.slice";
            CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_SYS_TTY_CONFIG CAP_SYS_NICE";
            AmbientCapabilities = "CAP_SYS_ADMIN CAP_SYS_TTY_CONFIG CAP_SYS_NICE";
            NoNewPrivileges = false;
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
      ];
    }
    (mkLocalBin "autoclick-toggle" scriptText)
  ])
