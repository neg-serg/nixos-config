{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = import ../../../lib/systemd-user.nix { inherit lib; };
  port = 18888;
  # Serve from home config where surfingkeys.js is symlinked
  serveDir = "/home/neg/.config";
in
with lib;
mkIf (config.features.web.enable or false) {
  systemd.user.services.surfingkeys-server =
    let
      preset = systemdUser.mkUnitFromPresets { presets = [ "defaultWanted" ]; };
    in
    {
      description = "HTTP server for Surfingkeys configuration";
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString port} --directory ${serveDir}"; # High-level dynamically-typed programming language
        Restart = "on-failure";
        RestartSec = "5";
        Slice = "background.slice";
      };
      after = preset.Unit.After or [ ];
      wants = preset.Unit.Wants or [ ];
      partOf = preset.Unit.PartOf or [ ];
      wantedBy = preset.Install.WantedBy or [ ];
    };
}
