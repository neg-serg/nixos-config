##
# Module: nix-maid/sys/kanata
# Purpose: Kanata keyboard remapper — ported from legacy Salt config.
# Requires uinput kernel module (enabled in hardware/uinput.nix).
{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  n = neg;
  cfg = config.features.input.kanata or { };
in
lib.mkIf (cfg.enable or false) {
  config = n.mkHomeFiles {
    ".config/kanata/kanata.kbd".source = ../../../../files/cli/kanata/kanata.kbd;
  };

  systemd.user.services.kanata = {
    description = "Kanata keyboard remapper";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.kanata} --cfg %h/.config/kanata/kanata.kbd";
      Restart = "on-failure";
      RestartSec = 2;
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
