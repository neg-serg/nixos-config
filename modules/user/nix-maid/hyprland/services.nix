{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Hyprland window list via vicinae (moved here from modules/user/session/hyprland.nix)
  hyprWinList = pkgs.writeShellApplication {
    name = "hypr-win-list"; # Hyprland window list via vicinae
    runtimeInputs = [
      pkgs.python3 # Python interpreter
      pkgs.wl-clipboard # clipboard manager for Wayland
      pkgs.hyprland # dynamic tiling Wayland compositor
    ];
    text =
      let
        tpl = builtins.readFile (
          inputs.self # flake self-reference
          + "/modules/user/nix-maid/scripts/hypr/hypr-win-list.py" # hypr-win-list script
        );
      in
      ''
                     exec python3 <<'PY'
        ${tpl}
        PY
      '';
  };
in
{
  packages = [
    pkgs.hypridle # idle daemon (locks to a fading black screen)
    pkgs.hyprlock # Hyprland's GPU-accelerated screen locking utility
    pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
    pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
    pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland

    pkgs.hyprcursor # modern cursor theme format for Hyprland
    pkgs.hyprpicker # color picker for Wayland/Hyprland
    pkgs.hyprprop # Hyprland property helper
    pkgs.hyprutils # assorted Hyprland utilities
    inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
    hyprWinList # Hyprland window list via vicinae

    pkgs.hyprscratch # sashetophizika/hyprscratch with event-listener keep-alive fix

    # hyprmusic script
    (pkgs.writeScriptBin "hyprmusic" ''
      #!/bin/sh
      set -euo pipefail
      case "''${1:-}" in
        next) MEMBER=Next ;;
        previous) MEMBER=Previous ;;
        play) MEMBER=Play ;;
        pause) MEMBER=Pause ;;
        play-pause) MEMBER=PlayPause ;;
        *) echo "Usage: $0 next|previous|play|pause|play-pause"; exit 1 ;;
      esac
      exec dbus-send \
        --print-reply \
        --dest="org.mpris.MediaPlayer2.$(${lib.getExe pkgs.playerctl} -l | head -n 1)" \
        /org/mpris/MediaPlayer2 \
        "org.mpris.MediaPlayer2.Player.$MEMBER"
    '')
    # hypr-fix script (Reload Hyprland config)
    (pkgs.writeShellScriptBin "hypr-fix" ''
      set -euo pipefail
      ${lib.getExe pkgs.libnotify} "System Fix" "Reloading Hyprland config..."
      hyprctl reload
      sleep 0.3
      # Restart quickshell to reconnect Wayland protocols after hypr reload
      systemctl --user restart quickshell.service > /dev/null 2>&1 || true
      ${lib.getExe pkgs.libnotify} "System Fix" "Done."
    '')
    # hypr-reload script
    (pkgs.writeShellScriptBin "hypr-reload" ''
      set -euo pipefail
      # Reload Hyprland config (ignore failure to avoid spurious errors)
      hyprctl reload > /dev/null 2>&1 || true
      # Give Hypr a brief moment to settle before restarting quickshell
      sleep 0.3
      # Restart quickshell to reconnect Wayland protocols after hypr reload
      systemctl --user restart quickshell.service > /dev/null 2>&1 || true
    '')
    # hypr-start script (fixes race conditions)
    (pkgs.writeShellScriptBin "hypr-start" ''
      set -euo pipefail
      LOG="/tmp/hypr-start.log"
      echo "Starting hypr-start at $(date)" > "$LOG"

      # Wait a moment for Hyprland to fully initialize sockets
      sleep 1

      # Import environment
      echo "Importing environment..." >> "$LOG"
      dbus-update-activation-environment --systemd --all
      systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_XDG_DESKTOP_PORTAL

      # Stop any stale portals or session targets to force clean state
      echo "Cleaning stale session state..." >> "$LOG"
      systemctl --user stop xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprland-session.target || true
      systemctl --user reset-failed

      # Start session
      echo "Starting hyprland-session.target..." >> "$LOG"
      systemctl --user start hyprland-session.target
      echo "Done." >> "$LOG"
    '')
    (pkgs.writers.writePython3Bin "hypr-rearrange" {
      flakeIgnore = [
        "E203"
        "E501"
        "W503"
      ];
    } (builtins.readFile ../scripts/hypr/hypr-rearrange.py))
  ];

  systemdTargets = {
    hyprland-session = {
      unitConfig = {
        Description = "Hyprland compositor session";
        Documentation = [ "man:systemd.special(7)" ];
        BindsTo = [ "graphical-session.target" ];
        Wants = [ "graphical-session-pre.target" ];
        After = [ "graphical-session-pre.target" ];
      };
    };
  };

  systemdServices = {
    # Hyprscratch daemon (scratchpad manager)
    # bindsTo ensures hyprscratch stops when the session target stops.
    # After hyprland reload/suspend the IPC socket changes, so
    # hyprland.lua restarts this service on hyprland.start (below).
    hyprscratch = {
      description = "Hyprscratch - improved scratchpad functionality for Hyprland";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.hyprscratch} init spotless";
        Restart = "always";
        RestartSec = "2";
      };
    };

    # Hypridle — idle daemon (locks to a fading black screen after 2 min; no DPMS off)
    hypridle = {
      description = "Hyprland idle daemon";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.hypridle}";
        Restart = "on-failure";
        RestartSec = "2";
      };
    };

    # Lock screen before system sleep (lid close / systemctl suspend)
    hyprlock-sleep = {
      description = "Lock screen before sleep";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe' pkgs.hyprlock "hyprlock"} --immediate";
        Environment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
    };

    # Hyprland Polkit Agent
    hyprpolkitagent = {
      description = "Hyprland Polkit Agent";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"; # Polkit authentication agent written in QT/QML
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
          "XDG_CURRENT_DESKTOP=Hyprland"
        ];
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
