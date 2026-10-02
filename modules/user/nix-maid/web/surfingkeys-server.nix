{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.lib.neg.enabled "web") {
  systemd.user.services.surfingkeys-server =
    let
      serverScript = pkgs.writeText "surfingkeys-server.py" (
        builtins.readFile (config.lib.neg.path "packages/local-bin/bin/surfingkeys-server")
      );
    in
    config.lib.neg.systemdUser.mkUserService {
      presets = [
        "graphicalSession"
        "restartOnFailure"
      ];
      description = "HTTP server for Surfingkeys configuration (focus/close/addressbar/proxy)";
      # The preset carries wantedBy+partOf; ordering (After=/Wants=) stays explicit.
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.python3 "python3"} -u ${serverScript}";
        Environment = "PATH=${pkgs.hyprland}/bin:$PATH";
        RestartSec = "5";
        Slice = "background.slice";
      };
    };

  systemd.user.services.surfingkeys-extension-patch =
    let
      patchScript = pkgs.writeShellScript "surfingkeys-extension-patch" (
        builtins.readFile (config.lib.neg.path "packages/local-bin/bin/surfingkeys-extension-patch")
      );
    in
    {
      description = "Patch SurfingKeys extension to auto-load config from local server";
      # The script logs every patch through `logger` (util-linux), which is not
      # part of systemd's default service PATH — without it the unit died with
      # status 127 on every login since at least 2026-09-19.
      path = [ pkgs.util-linux ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = patchScript;
      };
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };
}
