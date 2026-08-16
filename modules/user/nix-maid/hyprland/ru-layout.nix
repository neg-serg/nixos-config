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
# Mechanics and the per-app coverage matrix: docs/howto/hotkeys-ru-layout.ru.md.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.input.ruHotkeys or { };
  enabled = cfg.enable or false;

  usClasses = lib.concatStringsSep " " (
    cfg.usClasses or [
      "kitty"
      "mpv"
    ]
  );
  usIdx = toString (cfg.usLayoutIndex or 0);
  ruIdx = toString (cfg.ruLayoutIndex or 1);
  pollSec = cfg.pollSec or "0.5";

  # All runtime binaries are embedded by absolute path — no PATH assumptions in
  # the user session.
  daemon = pkgs.writeShellScript "ru-layout-daemon" ''
    # Per-window keyboard layout switching for Hyprland.
    # us for hotkey-heavy window classes, ru for everything else.
    set -u

    hyprctl_bin='${lib.getExe' pkgs.hyprland "hyprctl"}'
    awk_bin='${lib.getExe' pkgs.gawk "awk"}'
    sleep_bin='${lib.getExe' pkgs.coreutils "sleep"}'

    us_classes='${usClasses}'
    us_idx='${usIdx}'
    ru_idx='${ruIdx}'
    poll_sec='${pollSec}'

    focused_class() {
      "$hyprctl_bin" activewindow 2>/dev/null | "$awk_bin" -F': ' '/^class:/ {print $2; exit}'
    }

    current=""
    while :; do
      class="$(focused_class)"
      if [ "$class" != "$current" ]; then
        current="$class"
        case " $us_classes " in
          *" $class "*) idx="$us_idx" ;;
          *) idx="$ru_idx" ;;
        esac
        "$hyprctl_bin" switchxkblayout current "set $idx" 2>/dev/null || true
      fi
      "$sleep_bin" "$poll_sec"
    done
  '';
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
