# Module: hyprland/ru-layout — per-window keyboard layout daemon.
#
# Upstream `hyprland-per-window-layout` (nixpkgs) runs as a systemd user service:
# it subscribes to the Hyprland event socket (`.socket2.sock`) and remembers the
# XKB group per window address, replaying it when the window regains focus.
# Event-driven — no polling, no shell loop (the in-house polling daemon it
# replaced burned 48 min of CPU in 30 h: two `hyprctl` spawns per second).
#
# `usClasses` reaches the daemon as `default_layouts` in
# ~/.config/hyprland-per-window-layout/options.toml (generated in files.nix).
# A window matching that list is switched to `usLayoutIndex` on focus; any other
# window *starts* on `usLayoutIndex` as well — that is `us` under the invariant
# kb_layout = "us,ru" — and then keeps whatever layout it was switched to, so
# `ru` picked once in a typing-first window survives focus changes.
#
# Feature flag: features.input.ruHotkeys.* (declared in features/hardware.nix).
# Mechanics and the per-app coverage matrix: docs/howto/hotkeys-ru-layout.md.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.input.ruHotkeys or { };
  enabled = cfg.enable or false;

  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf enabled {
  # The binary calls `hyprctl` itself: user units run with a minimal PATH, so
  # hyprctl is injected through the unit's own `path`.
  systemd.user.services.ru-layout = systemdUser.mkUserService {
    description = "Per-window keyboard layout switching (hyprland-per-window-layout)";
    partOf = [ "hyprland-session.target" ];
    after = [ "graphical-session-pre.target" ];
    wantedBy = [ "hyprland-session.target" ];
    path = [ pkgs.hyprland ];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe pkgs.hyprland-per-window-layout;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
