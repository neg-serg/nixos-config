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
      # warpd double-forks by default (parent exits 0) — systemd would kill
      # the orphaned daemon with the cgroup; --foreground keeps it tracked.
      # Its Wayland backend errors against Hyprland (wl_display invalid object
      # 19) — unset WAYLAND_DISPLAY to select the X11 backend via XWayland.
      ExecStart = "${lib.getExe pkgs.warpd} --foreground";
      Restart = "on-failure";
      RestartSec = 2;
      UnsetEnvironment = "WAYLAND_DISPLAY";
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
