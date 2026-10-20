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
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.neg.aurora # aurora: MPD player with a Vulkan UI (winit + ash + cosmic-text)
    ];

    # The player asks the compositor for a translucent window: the swapchain uses a
    # premultiplied alpha mode and the frame's own ground carries the alpha, so what is behind
    # the window survives. Blurring that backdrop is the compositor's half, and it is what makes
    # the window read as glass instead of as a see-through hole.
    environment.sessionVariables.AURORA_WINDOW_OPACITY = "0.92";
  };
}
