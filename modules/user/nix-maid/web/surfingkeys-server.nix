{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
mkIf (config.lib.neg.enabled "web") {
  systemd.user.services.surfingkeys-server =
    let
      serverScript = pkgs.writeText "surfingkeys-server.py" (
        builtins.readFile (config.lib.neg.path "packages/local-bin/bin/surfingkeys-server")
      );
    in
    {
      description = "HTTP server for Surfingkeys configuration (focus/close/addressbar/proxy)";
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.python3 "python3"} -u ${serverScript}";
        Environment = "PATH=${pkgs.hyprland}/bin:$PATH";
        Restart = "on-failure";
        RestartSec = "5";
        Slice = "background.slice";
      };
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };

  systemd.user.services.surfingkeys-extension-patch =
    let
      patchScript = pkgs.writeShellScript "surfingkeys-extension-patch" (
        builtins.readFile (config.lib.neg.path "packages/local-bin/bin/surfingkeys-extension-patch")
      );
    in
    {
      description = "Patch SurfingKeys extension to auto-load config from local server";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = patchScript;
      };
      after = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
    };
}
