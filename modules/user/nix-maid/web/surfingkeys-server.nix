{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };
in
with lib;
mkIf (config.lib.neg.enabled "web") {
  systemd.user.services.surfingkeys-server =
    let
      preset = systemdUser.mkUnitFromPresets { };
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
      after = preset.Unit.After or [ ] ++ [ "graphical-session.target" ];
      wants = preset.Unit.Wants or [ ] ++ [ "graphical-session.target" ];
      partOf = preset.Unit.PartOf or [ ] ++ [ "graphical-session.target" ];
      wantedBy = preset.Install.WantedBy or [ ] ++ [ "graphical-session.target" ];
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
