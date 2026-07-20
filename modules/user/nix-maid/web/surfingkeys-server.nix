{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  systemdUser = import ../../../lib/systemd-user.nix { inherit lib; };
in
with lib;
mkIf (config.features.web.enable or false) {
  systemd.user.services.surfingkeys-server =
    let
      preset = systemdUser.mkUnitFromPresets { };
      serverScript = pkgs.writeText "surfingkeys-server.py" (
        builtins.readFile (self + "/packages/local-bin/bin/surfingkeys-server")
      );
    in
    {
      description = "HTTP server for Surfingkeys configuration (focus/close/addressbar/proxy)";
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 -u ${serverScript}";
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
      patchScript = pkgs.writeScript "surfingkeys-extension-patch" (
        builtins.readFile (self + "/packages/local-bin/bin/surfingkeys-extension-patch")
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
