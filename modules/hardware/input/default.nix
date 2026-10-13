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
    # A remapper must come back by itself. With systemd's default start limit
    # (5 starts / 10 s) a crash loop kills the unit for good and caps→Ctrl stays
    # gone until a manual restart — that is exactly what happened on 2026-10-13
    # when kanata fought ydotoold/vicinae for their virtual keyboards, five
    # restarts in four seconds. The device list is now fixed at the source
    # (files/cli/kanata/kanata.kbd); this keeps a future crash self-healing.
    unitConfig = {
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.kanata} --cfg %h/.config/kanata/kanata.kbd";
      RestartSec = 2;
    };
  };
}
