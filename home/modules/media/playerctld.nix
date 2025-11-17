{
  pkgs,
  lib,
  config,
  systemdUser,
  ...
}:
with lib;
  mkIf (config.features.media.audio.apps.enable or false) {
    systemd.user.services.playerctld = lib.mkMerge [
      {
        Unit = {Description = "Keep track of media player activity";};
        Service = {
          Type = "simple";
          ExecStart = let
            exe = lib.getExe' pkgs.playerctl "playerctld";
            args = ["daemon"];
          in "${exe} ${lib.escapeShellArgs args}";
          Restart = "on-failure";
          RestartSec = "2";
        };
      }
      (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
    ];
  }
