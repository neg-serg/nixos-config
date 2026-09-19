{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Hyprland window list via vicinae (moved here from the old user-session
  # Hyprland module)
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

  # Scratchpad geometry persistence daemon (python)
  scratchpadGeometry = pkgs.writers.writePython3Bin "scratchpad-geometry" {
    flakeIgnore = [
      "E203"
      "E501"
      "W503"
    ];
    # hyprctl (from pkgs.hyprland) must be on PATH: systemd user services
    # run with a minimal PATH, so the daemon could never call hyprctl.
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (pkgs.lib.makeBinPath [ pkgs.hyprland ])
    ];
  } (builtins.readFile (inputs.self + "/packages/scratchpad-geometry/scratchpad-geometry.py"));
in
{
  packages = [
    pkgs.hypridle # idle daemon (locks to a fading black screen)
    # pkgs.hyprlock — temporarily removed (2026-08-31); re-add to restore the lock screen
    pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
    pkgs.wayvnc # VNC server for wlroots-based Wayland compositors
    pkgs.wayback-x11 # X11 compatibility layer for wlroots/Xwayland
    pkgs.wl-clipboard # Command-line copy/paste utilities for Wayland

    pkgs.hyprcursor # modern cursor theme format for Hyprland
    pkgs.hyprpicker # color picker for Wayland/Hyprland
    pkgs.hyprprop # Hyprland property helper
    pkgs.hyprutils # assorted Hyprland utilities
    inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system} # run-or-raise for Hyprland
    hyprWinList # Hyprland window list via vicinae

    pkgs.hyprscratch # sashetophizika/hyprscratch with event-listener keep-alive fix

    scratchpadGeometry # persist scratchpad geometry across show/hide cycles
    pkgs.neg.niri-screen-time # screen time tracker: per class/window-title time daemon + report CLI

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
    # Glass scratchpad terminal. hyprglass frosts what is behind a window, so the
    # terminal itself has to be translucent for the backdrop to read through:
    # kitty's 0.88 default is nearly opaque and showed no glass at all. 0.65 black
    # keeps it glassy while staying visibly darker than the media card (0.45).
    # Used by the scratchpad binds in files/gui/hypr/hyprland.lua.
    (pkgs.writeShellScriptBin "kitty-glass" ''
      exec ${lib.getExe pkgs.kitty} -o background_opacity=0.65 "$@"
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
    # quickshell-restart script (clean panel restart; waits for the service to come up)
    (pkgs.writeShellScriptBin "quickshell-restart" ''
      set -euo pipefail
      ${lib.getExe pkgs.libnotify} "Quickshell" "Restarting panel..."
      systemctl --user restart quickshell.service
      # Wait until the service is active again (up to ~15s), then report.
      for i in $(seq 1 30); do
        state=$(systemctl --user is-active quickshell.service 2>/dev/null || true)
        [ "$state" = "active" ] && break
        sleep 0.5
      done
      if [ "$(systemctl --user is-active quickshell.service 2>/dev/null)" = "active" ]; then
        ${lib.getExe pkgs.libnotify} "Quickshell" "Panel restarted."
      else
        ${lib.getExe pkgs.libnotify} -u critical "Quickshell" "Restart failed — check 'systemctl --user status quickshell'."
      fi
    '')
    # hypr-start script (fixes race conditions)
    (pkgs.writeShellScriptBin "hypr-start" (builtins.readFile ./hypr-start.sh))
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

    # Scratchpad geometry persistence: saves window geometry on move/resize
    # (via event stream + poll) and reapplies it when a special workspace shows.
    # Exits when the IPC socket dies; Restart=always brings it back.
    scratchpad-geometry = {
      description = "Persist Hyprland scratchpad geometry across show/hide cycles";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe scratchpadGeometry}";
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

    # hyprlock-sleep service temporarily disabled (2026-08-31): no lock before sleep.
    # Restore together with the hyprlock package: oneshot ExecStart hyprlock --immediate on sleep.target.

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

    # Screen time tracker: polls `hyprctl activewindow` every 200 ms and writes
    # per class/window-title time into ~/.local/share/niri-screen-time/db.db.
    # Read it back with `niri-screen-time [-from=YYYY-MM-DD -to=YYYY-MM-DD]`.
    niri-screen-time = {
      description = "Screen time tracker (per window class / title)";
      wantedBy = [ "hyprland-session.target" ];
      bindsTo = [ "hyprland-session.target" ];
      after = [ "hyprland-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.neg.niri-screen-time} -daemon";
        Environment = [
          # The binary selects its compositor backend from XDG_CURRENT_DESKTOP
          # and panics on an unknown value; the systemd user environment does
          # not carry the session's value.
          "XDG_CURRENT_DESKTOP=Hyprland"
          "XDG_SESSION_TYPE=wayland"
        ];
        Restart = "always";
        RestartSec = "2";
      };
    };
  };
}
