{
  lib,
  config,
  pkgs,
  systemdUser,
  negLib,
  ...
}:
with lib; let
  scriptRoot = config.neg.repoRoot + "/packages/local-bin/scripts";
  scriptText = builtins.readFile (scriptRoot + "/autoclick-toggle");
  mkLocalBin = negLib.mkLocalBin;
in
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
            # Run as an unprivileged user; uinput access is granted via the group
            # (hardware.uinput + extraGroups). Dropping capability requests avoids
            # failure in user systemd (exit 218/CAPABILITIES).
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
          };
        }
        (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
      ];
    }
    (mkLocalBin "autoclick-toggle" scriptText)
  ])
