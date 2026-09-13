# Module: hyprland/ru-layout — per-window keyboard layout daemon.
#
# Watches the focused Hyprland window class and switches the XKB layout on
# focus transitions: hotkey-heavy windows (kitty, mpv, …) get `us`, everything
# else defaults to `ru` (typing-first). This fixes bare-letter hotkeys under
# the ru layout for ALL apps at once — including the ones that cannot be fixed
# by config at all (mutt, rustmission, btop, kitty hints, zsh vi-mode, …).
#
# Rules apply only on transitions, so a manual M4+S switch inside a window is
# never reverted until the focus moves away.
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

  # Window classes forced to `us` come from the option's default in
  # modules/features/hardware.nix (each class annotated there) — the list is
  # deliberately not duplicated here. The fallback only covers a trimmed eval
  # that drops the hardware domain, in which case the module is not imported.
  usClasses = lib.concatStringsSep " " (cfg.usClasses or [ ]);
  usIdx = toString (cfg.usLayoutIndex or 0);
  ruIdx = toString (cfg.ruLayoutIndex or 1);
  pollSec = cfg.pollSec or "0.5";

  # All runtime binaries are embedded by absolute path — no PATH assumptions in
  # the user session.
  daemon = pkgs.writeShellScript "ru-layout-daemon" (
    builtins.readFile (
      pkgs.replaceVars ./ru-layout-daemon.sh {
        sleepBin = lib.getExe' pkgs.coreutils "sleep";
        awkBin = lib.getExe' pkgs.gawk "awk";
        hyprctlBin = lib.getExe' pkgs.hyprland "hyprctl";
        inherit
          pollSec
          ruIdx
          usIdx
          usClasses
          ;
      }
    )
  );
in
lib.mkIf enabled {
  systemd.user.services.ru-layout = {
    description = "Per-window keyboard layout switching (us in hotkey-heavy apps)";
    partOf = [ "hyprland-session.target" ];
    after = [ "graphical-session-pre.target" ];
    wantedBy = [ "hyprland-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${daemon}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
