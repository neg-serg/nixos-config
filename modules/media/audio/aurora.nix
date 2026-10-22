##
# Module: media/audio/aurora
# Purpose: aurora — the local MPD player with its own Vulkan UI. One package,
# two binaries (aurora, aurora-probe); it talks to the MPD daemon that
# modules/servers/mpd already configures and serves MPRIS on the session bus.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.aurora";
  # mod4+f toggles the player the way the scratchpad keys do: the first press starts aurora, the
  # next one parks it out of sight, the one after that brings it back.
  #
  # The window class is `player`, not `aurora`: the crate sets that Wayland app_id itself
  # (~/src/aurora, with_name("player", "player")) and the Hyprland rules in
  # files/gui/hypr/hyprland.lua match `^(player)$`. Matching the binary name here focused
  # nothing, so every press fell through to starting another copy.
  #
  # Hyprland has no "hide this window" dispatcher, and the moves that would emulate one act on the
  # *focused* window only — the legacy `focuswindow`/`movetoworkspacesilent` string dispatchers are
  # not wired in 0.56 at all, so there is no reliable "move that window over there" from a script.
  # The player therefore lives on its own special workspace from the moment it maps (the
  # `workspace = "special:aurora silent"` window rule in files/gui/hypr/hyprland.lua parks it
  # there without yanking the view), and the key simply toggles that workspace: shown = the player
  # is up, hidden = parked. First press starts the player and reveals the workspace once its
  # window actually exists, so a failed launch never leaves an empty special workspace on screen.
  playerClass = "player";
  playerWorkspace = "aurora";
  aurora-focus = pkgs.writeShellScriptBin "aurora-focus" ''
    set -eu
    hyprctl=${pkgs.hyprland}/bin/hyprctl
    jq=${pkgs.jq}/bin/jq
    up() { $hyprctl clients -j 2>/dev/null | $jq -e --arg c ${lib.escapeShellArg playerClass} 'any(.[]; .class == $c)' > /dev/null; }

    if ! up; then
      # Start detached, so the launcher does not hold the window.
      setsid ${pkgs.neg.aurora}/bin/aurora "$@" > /dev/null 2>&1 < /dev/null &
      # Wait for the window to map (the rule parks it on the workspace, it is not shown yet).
      i=0
      while [ "$i" -lt 150 ] && ! up; do
        sleep 0.2
        i=$((i + 1))
      done
      up || exit 1
    fi
    exec $hyprctl dispatch ${lib.escapeShellArg ''hl.dsp.workspace.toggle_special("${playerWorkspace}")''}
  '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.neg.aurora # aurora: MPD player with a Vulkan UI (winit + ash + cosmic-text)
      aurora-focus # what mod4+f runs: focus the player, or start it if it is not up
    ];

    # The player asks the compositor for a translucent window: the swapchain uses a
    # premultiplied alpha mode and the frame's own ground carries the alpha, so what is behind
    # the window survives. Blurring that backdrop is the compositor's half, and it is what makes
    # the window read as glass instead of as a see-through hole.
    environment.sessionVariables.AURORA_WINDOW_OPACITY = "0.92";
  };
}
