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
    # Restart with kanata: neru proxies kanata's virtual keyboard and re-learns
    # the device hand-off on every start, while a long-lived proxy can drift out
    # of sync with the remapper. That is the state in which neru silently stopped
    # forwarding W until it was restarted (2026-10-13); PartOf makes every kanata
    # restart or stop reset it instead of leaving a dead key behind.
    partOf = [ "kanata.service" ];
    # hyprctl (from pkgs.hyprland) must be on PATH: user units run with a
    # minimal PATH, and neru shells out to `hyprctl -j activewindow` to find
    # the focused window before scanning for hints.
    path = [ pkgs.hyprland ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.neg.neru} launch --config %h/.config/neru/config.toml";
      RestartSec = 2;
    };
  };
}
