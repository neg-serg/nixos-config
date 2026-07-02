{
  lib,
  pkgs,
  ...
}:
{
  packages = [
      pkgs.hyprlock # Hyprland's GPU-accelerated screen locking utility
      pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
      pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
      pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland

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
      # hypr-scratch-toggle script (native Hyprland special workspaces)
      (pkgs.writeShellScriptBin "hypr-scratch-toggle" ''
        set -euo pipefail
        name="$1"
        has_window() { hyprctl clients -j 2>/dev/null | ${lib.getExe pkgs.python3} -c "import json,sys; clients=json.load(sys.stdin); sys.exit(0 if any(c['class']=='"$1"' for c in clients) else 1)"; }
        toggle() { hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$1\")" 2>/dev/null; }
        launch() { hyprctl dispatch "hl.dsp.exec_cmd(\"$1\")" 2>/dev/null; sleep 0.6; }
        move_to_special() {
          addr=$(hyprctl clients -j 2>/dev/null | ${lib.getExe pkgs.python3} -c "import json,sys; clients=json.load(sys.stdin); print(next((c['address'] for c in clients if c['class']=='"$1"'), ''))")
          [ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.move({ window = \"$addr\", workspace = \"special:$2\" })" 2>/dev/null
        }
        case "$name" in
          im)
            class="org.telegram.desktop"
            if has_window "$class"; then toggle im; else launch "Telegram" && move_to_special "$class" im && toggle im; fi ;;
          music)
            class="music"
            if has_window "$class"; then toggle music; else launch "kitty --class music -e rmpc" && move_to_special "$class" music && toggle music; fi ;;
          torrment)
            class="torrment"
            if has_window "$class"; then toggle torrment; else launch "kitty --class torrment -e rustmission" && move_to_special "$class" torrment && toggle torrment; fi ;;
          teardown)
            class="teardown"
            if has_window "$class"; then toggle teardown; else launch "kitty --class teardown -e btop" && move_to_special "$class" teardown && toggle teardown; fi ;;
          mixer)
            class="mixer"
            if has_window "$class"; then toggle mixer; else launch "kitty --class mixer -e ncpamixer" && move_to_special "$class" mixer && toggle mixer; fi ;;
          vpn)
            class="vpn"
            if has_window "$class"; then toggle vpn; else launch "kitty --class vpn -e sing-box tun" && move_to_special "$class" vpn && toggle vpn; fi ;;
          *) echo "Unknown scratchpad: $name"; exit 1 ;;
        esac
      '')
      # hypr-fix script (Reload Hyprland config)
      (pkgs.writeShellScriptBin "hypr-fix" ''
        set -euo pipefail
        ${lib.getExe pkgs.libnotify} "System Fix" "Reloading Hyprland config..."
        hyprctl reload
        sleep 1
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
  };
}
