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
    shown() { $hyprctl monitors -j 2>/dev/null | $jq -e --arg w "special:${playerWorkspace}" 'any(.[]; .specialWorkspace.name == $w)' > /dev/null; }

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
    # The key owns both halves: the same press shows and hides the player.
    $hyprctl dispatch ${lib.escapeShellArg ''hl.dsp.workspace.toggle_special("${playerWorkspace}")''}
    # Hiding parks the player, and the press is finished: the pointer stays where the user left it.
    # Showing hands the screen to the player, so the pointer goes with the screen — to the middle of
    # the window, read out of the client list because nothing else lives on this workspace.
    # `cursor:warp_on_change_workspace` does not do this for a special workspace (measured on
    # 0.56.2: the toggle leaves the pointer where it was), so the move is explicit.
    shown || exit 0
    pos=$($hyprctl clients -j 2>/dev/null | $jq -r --arg c ${lib.escapeShellArg playerClass} \
      '[.[] | select(.class == $c)][0] | "\(.at[0] + ((.size[0] / 2) | floor)) \(.at[1] + ((.size[1] / 2) | floor))"')
    [ -n "$pos" ] || exit 0
    x=''${pos% *}
    y=''${pos#* }
    $hyprctl dispatch "hl.dsp.cursor.move({ x = $x, y = $y })"
  '';
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.neg.aurora # aurora: MPD player with a Vulkan UI (winit + ash + cosmic-text)
      pkgs.neg.aurora-tools # headphones: the model catalogue CLI (apply/import/export)
      aurora-focus # what mod4+f runs: focus the player, or start it if it is not up
    ];

    # The player asks the compositor for a translucent window: the swapchain uses a
    # premultiplied alpha mode and the frame's own ground carries the alpha, so what is behind
    # the window survives. Blurring that backdrop is the compositor's half, and it is what makes
    # the window read as glass instead of as a see-through hole.
    environment.sessionVariables.AURORA_WINDOW_OPACITY = "0.92";
  };
}
