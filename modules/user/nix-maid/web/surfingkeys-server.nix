{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  systemdUser = import ../../../lib/systemd-user.nix { inherit lib; };
  port = 18888;
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
      description = "HTTP server for Surfingkeys configuration (focus/close/proxy)";
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 -u ${serverScript}";
        Restart = "on-failure";
        RestartSec = "5";
        Slice = "background.slice";
      };
      after = preset.Unit.After or [ ] ++ [ "graphical-session.target" ];
      wants = preset.Unit.Wants or [ ] ++ [ "graphical-session.target" ];
      partOf = preset.Unit.PartOf or [ ] ++ [ "graphical-session.target" ];
      wantedBy = preset.Install.WantedBy or [ ] ++ [ "graphical-session.target" ];
    };
}
