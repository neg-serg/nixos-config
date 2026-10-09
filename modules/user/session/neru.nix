##
# Module: user/session/neru
# Purpose: Neru keyboard navigation daemon — hints, grids and vim-style modes.
# Feature flag: features.input.neru.enable (declared in features/hardware.nix)
# Config file: deployed via nix-maid (modules/user/nix-maid/sys/neru.nix)
# Requires: input group + writable /dev/uinput (hardware/uinput.nix)
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.input.neru or { };
in
lib.mkIf cfg.enable {
  environment.systemPackages = [
    pkgs.neg.neru # Desktop keyboard navigation (hints/grids/vim keys; Wayland/X11)
  ];

  systemd.user.services.neru = config.lib.neg.systemdUser.mkUserService {
    presets = [
      "graphicalSession"
      "restartOnFailure"
    ];
    description = "Neru keyboard navigation daemon";
    # The preset carries wantedBy+partOf; the ordering (After=) stays explicit.
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.neg.neru} launch --config %h/.config/neru/config.toml";
      RestartSec = 2;
    };
  };
}
