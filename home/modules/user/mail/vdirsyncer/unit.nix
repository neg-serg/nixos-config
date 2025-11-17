{
  lib,
  pkgs,
  config,
  systemdUser,
  ...
}:
with lib;
  mkIf (config.features.mail.enable && config.features.mail.vdirsyncer.enable) {
    systemd.user.services.vdirsyncer = lib.mkMerge [
      {
        Unit = {Description = "Vdirsyncer synchronization service";};
        Service = {
          Type = "oneshot";
          ExecStartPre = let
            exe = lib.getExe pkgs.vdirsyncer;
            args = ["metasync"];
          in "${exe} ${lib.escapeShellArgs args}";
          ExecStart = let
            exe = lib.getExe pkgs.vdirsyncer;
            args = ["sync"];
          in "${exe} ${lib.escapeShellArgs args}";
        };
      }
      (systemdUser.mkUnitFromPresets {presets = ["netOnline"];})
    ];
  }
