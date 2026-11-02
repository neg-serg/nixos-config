{
  lib,
  pkgs,
  inputs,
  neg,
  repoRoot,
  ...
}:
let
  r = neg.rooted repoRoot;

  # Hyprland window picker (Rust): reads the client list and focuses the entry
  # chosen in vicinae's dmenu; the package wrapper puts hyprctl and vicinae on
  # PATH.
  hyprWinList = pkgs.neg.hypr-win-list;

  # Scratchpad geometry persistence daemon (Rust). The package wrapper puts
  # hyprctl on PATH: systemd user services run with a minimal PATH, so the
  # daemon could never call it otherwise.
  scratchpadGeometry = pkgs.neg.scratchpad-geometry;
  # Fallback frost for a scratchpad pane (see kitty-glass-frost.sh): a heavily
  # blurred, darkened slice of the current wallpaper pushed into the pane as kitty's
  # background image. The launcher no longer uses it — the rmpc pane is translucent
  # enough these days for the plugin's own frost to carry it — but it stays
  # installed: one line in the music branch of `kitty-glass` below brings it back.
  kittyGlassFrost = pkgs.writeShellScriptBin "kitty-glass-frost" (
    builtins.replaceStrings
      [ "@hyprctl@" "@kitten@" ]
      [ "${lib.getExe' pkgs.hyprland "hyprctl"}" "${lib.getExe' pkgs.kitty "kitten"}" ]
      (r.readFile "modules/user/nix-maid/hyprland/kitty-glass-frost.sh")
  );

in
{
  # Helper scripts for the themed unit files (./glass.nix, ./scratchpad.nix)
  # and the package list below; the aggregator passes each one where it is used.
  helpers = {
    inherit
      hyprWinList
      scratchpadGeometry
      kittyGlassFrost
      ;
  };

  packages = [
    pkgs.hypridle # idle daemon (locks to a fading black screen)
    # pkgs.hyprlock — temporarily removed (2026-08-31); re-add to restore the lock screen
    pkgs.hyprpolkitagent # Polkit authentication agent for Hyprland
    kittyGlassFrost # fallback pane frost (baked wallpaper slice; unused by the launcher)
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
    # Glass scratchpad terminal. The compositor frosts what is behind a window, so the
    # terminal itself has to be translucent for the backdrop to read through:
    # kitty's 0.88 default is nearly opaque and showed no glass at all. 0.85 black
    # keeps a hint of frost while staying decisively darker than the media card
    # (0.45) — a terminal that faint competes with its own text.
    #
    # The music pane (rmpc) used to sit at the opposite end: it carried the glass
    # plugin's strongest frost preset, so 0.45 black let the backdrop through. With
    # the plugin gone there is no extra frost behind it, and 0.85 puts the pane on
    # the same footing as every other scratchpad, where the text wins over
    # the backdrop. Measured over an opaque 200-grey window: 0.96 -> (6,6,6),
    # 0.92 -> (11,11,11), 0.85 -> (24,24,24), 0.70 -> (49,49,49).
    #
    # The opacity can be tuned without a rebuild: write a number into
    # ~/.config/kitty/glass-opacity (all scratchpads) and reopen the pane — the
    # file is picked up per launch, so a rebuild is only needed to change the
    # per-class default here.
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
        music) opacity=0.85 ;; # rmpc: same footing as the other scratchpads
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
      ${lib.getExe pkgs.libnotify} "System Fix" "Done."
    '')
    # hypr-reload script
    (pkgs.writeShellScriptBin "hypr-reload" ''
      set -euo pipefail
      # Reload Hyprland config (ignore failure to avoid spurious errors)
      hyprctl reload > /dev/null 2>&1 || true
    '')
    # hypr-start script (fixes race conditions)
    (pkgs.writeShellScriptBin "hypr-start" (r.readFile "modules/user/nix-maid/hyprland/hypr-start.sh"))
    pkgs.neg.hypr-rearrange # move windows to the workspaces the config routes them to
  ];
}
