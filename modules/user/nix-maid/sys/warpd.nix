##
# Module: nix-maid/sys/warpd
# Purpose: warpd — modal keyboard-driven virtual pointer (daemon).
# Hotkeys must be bound in the compositor (Hyprland/sway), e.g.:
#   bind = $mod CTRL, X, exec, warpd --hint
#   bind = $mod CTRL, C, exec, warpd --normal
#   bind = $mod CTRL, G, exec, warpd --grid
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.input.warpd or { };
in
lib.mkIf (cfg.enable or false) {
  environment.systemPackages = [ pkgs.warpd ];

  systemd.user.services.warpd = {
    description = "warpd keyboard-driven pointer daemon";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.warpd}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
