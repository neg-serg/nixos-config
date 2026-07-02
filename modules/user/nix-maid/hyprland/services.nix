{
  lib,
  pkgs,
  ...
}:
{
  packages =
    pyprlandConfig:
    [
      pkgs.hyprlock # Hyprland's GPU-accelerated screen locking utility
      pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
      pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
      pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland

      pkgs.pyprland # Python plugin system for Hyprland
      pkgs.hyprscratch # Rust scratchpad manager for Hyprland
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
      # hypr-scratch-toggle script
      (pkgs.writeShellScriptBin "hypr-scratch-toggle" ''
        set -euo pipefail
        name="$1"
        case "$name" in
          im)       exec hyprscratch im "telegram-desktop" shiny ;;
          music)    exec hyprscratch music "kitty --class music -e rmpc" persist ;;
          torrment) exec hyprscratch torrment "kitty --class torrment -e rustmission" ;;
          teardown) exec hyprscratch teardown "kitty --class teardown -e btop" persist shiny ;;
          mixer)    exec hyprscratch mixer "kitty --class mixer -e ncpamixer" shiny ;;
          vpn)      exec hyprscratch vpn "kitty --class vpn -e sing-box tun" shiny ;;
          *)        echo "Unknown scratchpad: $name"; exit 1 ;;
        esac
      '')
      # hypr-fix script (Reset Pyprland and Hyprland state)
      (pkgs.writeShellScriptBin "hypr-fix" ''
        set -euo pipefail
        ${lib.getExe pkgs.libnotify} "System Fix" "Restarting Pyprland and reloading config..."
        systemctl --user restart pyprland.service
        hyprctl reload
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
        systemctl --user stop "xdg-desktop-portal*" hyprland-session.target || true
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
      (pkgs.writeShellScriptBin "hyde-selector" (
        builtins.readFile ../../../../files/scripts/hyde-selector.sh
      ))
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
        ];
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    # Pyprland service
    pyprland = {
      description = "Pyprland - Hyprland plugin system";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.pyprland}";
        Restart = "always";
        RestartSec = "1";
      };
    };
  };
}
