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
  # Push the hyprglass settings into a running session (see hyprglass-apply.sh).
  # The runtime paths are substituted here because systemd user services and the
  # session shell both run with a minimal PATH.
  hyprglassApply = pkgs.writeShellScriptBin "hyprglass-apply" (
    builtins.replaceStrings
      [ "@hyprctl@" "@plugin@" ]
      [ "${lib.getExe' pkgs.hyprland "hyprctl"}" "${pkgs.hyprglass}/lib/hyprglass.so" ]
      (builtins.readFile ./hyprglass-apply.sh)
  );

  # PATH for the units that run it (see the two hyprglass units below): the script
  # needs jq to read the panel's JSON overrides, the usual text tools, and hyprctl
  # — the only way to talk to the plugin. Both units share it: without it the drift
  # watchdog could not even read the overrides and died with "jq is missing" on
  # every timer tick, so nothing repaired the glass after a compositor reload.
  hyprglassPath = lib.makeBinPath [
    pkgs.coreutils # shell plumbing (mkdir, mv, tr, date)
    pkgs.gnused # rewrites the generated lua's numbers
    pkgs.gnugrep # scans the plugin list
    pkgs.gawk # compares the reported values with the wanted ones
    pkgs.jq # reads the Glass panel's JSON overrides
    pkgs.hyprland # hyprctl, the only way to talk to the plugin
  ];
in
{
  packages = [
    pkgs.hypridle # idle daemon (locks to a fading black screen)
    # pkgs.hyprlock — temporarily removed (2026-08-31); re-add to restore the lock screen
    pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
    hyprglassApply # pushes glass settings into the running session (panel, path unit)
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
    # kitty's 0.88 default is nearly opaque and showed no glass at all. 0.85 black
    # keeps a hint of frost while staying decisively darker than the media card
    # (0.45) — a terminal that faint competes with its own text.
    #
    # The music pane (rmpc) is the one exception: it has to read black, so it runs
    # at 0.96 over a black background instead of 0.85 over the album tint. Measured
    # on the pane itself: 0.60 gave (13.4, 16.2, 21.2) and 0.85 gave (10.6, 13.1,
    # 15.4), where 0.96 keeps only ~1/255 of the wallpaper through.
    #
    # ...and then it turned out that is too black to see anything of the desktop
    # through it, which is the point of a glass scratchpad, so the pane sits at
    # 0.75: over a bright surface behind it the fill reads (40,40,41) instead of
    # (6,6,6) at 0.96 (measured against an opaque 200-grey window: 0.96 -> 6,
    # 0.85 -> 24, 0.80 -> 32, 0.75 -> 40, 0.70 -> 49, i.e. 25% of the backdrop
    # now comes through). The frost must stay the black one: the pane is a
    # terminal first, and its tint is what keeps the text readable over it.
    #
    # The opacity can be tuned without a rebuild: write a number into
    # ~/.config/kitty/glass-opacity and reopen the scratchpad (the file is picked
    # up per launch, so a switch is only needed to change the launcher itself).
    # Used by the scratchpad binds in files/gui/hypr/hyprland.lua.
    (pkgs.writeShellScriptBin "kitty-glass" ''
      class=""
      previous=""
      for arg in "$@"; do
        [ "$previous" = "--class" ] && class="$arg"
        previous="$arg"
      done

      # Per-class default; the override file below still wins over both.
      case "$class" in
        music) opacity=0.75 ;; # rmpc: black first, but the desktop shows through
        *) opacity=0.85 ;;
      esac
      override="$HOME/.config/kitty/glass-opacity"
      [ -r "$override" ] && opacity="$(head -n 1 "$override" | tr -d '[:space:]')"
      case "$opacity" in
        [0-9]*|0.*|1) ;;
        *) opacity=0.85 ;;
      esac
      # Colour code by purpose: each scratchpad gets its own dark tint, so the
      # window says what it is before the title is read. Kept close to black —
      # the tint sits under the compositor's glass, it does not replace it.
      # The panel's switch: off means "no tinting at all", i.e. kitty's own
      # background for every scratchpad.
      tint_enabled=1
      if command -v jq >/dev/null 2>&1; then
        setting="$(jq -r 'if has("scratchpadTint") then .scratchpadTint else true end' "$HOME/.config/quickshell/Settings.json" 2>/dev/null)"
        [ "$setting" = "false" ] && tint_enabled=0
      fi

      case "$class" in
        rebuild)  tint="#171008" ;; # warm — the rebuilds it runs
        torrment) tint="#08131a" ;; # cold blue — downloads
        vpn)      tint="#08160f" ;; # green — the tunnel
        music)    tint="#000000" ;; # rmpc: the pane stays black, no cover accent
        mixer)    tint="#181207" ;; # amber — audio
        teardown) tint="#0b0d11" ;; # neutral slate — system overview
        *)        tint="#000000" ;;
      esac

      [ "$tint_enabled" = 1 ] || tint="#000000"

      # A little inset so the TUI does not run into the glass edge; kitty's own
      # config keeps 0 for ordinary terminals.
      exec ${lib.getExe pkgs.kitty} -o background_opacity="$opacity" \
        -o background="$tint" -o window_padding_width=8 "$@"
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
    # Watchdog for the glass settings: the plugin drops its config when the
    # compositor re-initialises it, and nothing else reports that. The timer in
    # sys/user-services.nix runs this every 10 s; it checks first, so a healthy
    # session costs nine `hyprctl getoption` reads and no writes.
    hyprglass-watch = {
      description = "Re-apply hyprglass settings if they drifted";
      serviceConfig = {
        Type = "oneshot";
        # The same PATH as the apply below — see hyprglassPath. This unit was
        # without one, so jq was missing and every tick ended in "jq is missing".
        Environment = [ "PATH=${hyprglassPath}" ];
        ExecStart = "${hyprglassApply}/bin/hyprglass-apply --watch";
      };
    };

    # Triggered by hyprglass-config.path when the glass config is (re)deployed
    # or the panel writes overrides.
    hyprglass-apply = {
      description = "Push hyprglass settings into the running session";
      serviceConfig = {
        Type = "oneshot";
        # Without this the script could not read the panel's JSON (jq) and
        # silently pushed only the defaults, so the panel's values never landed.
        Environment = [ "PATH=${hyprglassPath}" ];
        ExecStart = "${hyprglassApply}/bin/hyprglass-apply";
      };
      unitConfig = {
        # A slider drag rewrites the override file several times per second, and
        # the default StartLimitBurst (5 in 10 s) turned that into
        # "start-limit-hit": the applies stopped and the units went to failed.
        StartLimitIntervalSec = 0;
      };
    };

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
