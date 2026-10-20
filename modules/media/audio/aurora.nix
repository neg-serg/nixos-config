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
  # mod4+f runs this: the player is a normal window, so the key has to both start it and, on a
  # second press, bring it to the front instead of starting a twin.
  aurora-focus = pkgs.writeShellScriptBin "aurora-focus" ''
    set -eu
    if ${pkgs.jq}/bin/jq -e 'any(.[]; .class == "aurora")' \
      < <(${pkgs.hyprland}/bin/hyprctl clients -j 2>/dev/null || echo '[]') > /dev/null; then
      exec ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow class:aurora
    fi
    # Not running: start detached, so the launcher does not hold the window.
    exec setsid ${pkgs.neg.aurora}/bin/aurora "$@" > /dev/null 2>&1 < /dev/null
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
