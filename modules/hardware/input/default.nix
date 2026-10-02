##
# Module: hardware/input/kanata
# Purpose: Kanata keyboard remapper — systemd user service.
# Feature flag: features.input.kanata.enable (declared in features/hardware.nix)
# Config file: deployed via nix-maid (modules/user/nix-maid/sys/kanata.nix)
# Requires: uinput kernel module (hardware/uinput.nix)
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.input.kanata or { };
in
lib.mkIf cfg.enable {
  systemd.user.services.kanata = config.lib.neg.systemdUser.mkUserService {
    presets = [
      "graphicalSession"
      "restartOnFailure"
    ];
    description = "Kanata keyboard remapper";
    # The preset carries wantedBy+partOf; the ordering (After=) stays explicit.
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.kanata} --cfg %h/.config/kanata/kanata.kbd";
      RestartSec = 2;
    };
  };
}
