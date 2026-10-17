##
# Module: user/session/wallpaper-video
# Purpose: animated wallpaper — mpv loops a rendered clip in a full-screen
#          background window, and hyprwinwrap pins that window behind the
#          desktop (the matching declaration lives in
#          files/gui/hypr/hyprwinwrap.lua).
# Clip:    %h/pic/wl/video/waterfall_loop.mp4 — produced from a still image with
#          HunyuanVideo 1.5 I2V in the local ComfyUI stack, cross-faded into a
#          seamless loop (recipe: docs/howto/local-video-ai.md).
# Notes:   --no-config is deliberate: the user's mpv config injects uosc and
#          mpv-mpris, so the wallpaper would draw an OSD and appear in the
#          status bar as a media player.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  systemdUser = config.lib.neg.systemdUser;
in
{
  systemd.user.services.wallpaper-video = systemdUser.mkUserService {
    presets = [
      "graphicalSession"
      "restartOnFailure"
    ];
    description = "Looped video wallpaper (mpv + hyprwinwrap)";
    after = [ "graphical-session.target" ];
    unitConfig = {
      # No clip, no unit: keeps the service out of other users' managers and
      # stops a retry loop when the video has not been rendered yet.
      ConditionPathExists = "%h/pic/wl/video/waterfall_loop.mp4";
    };
    serviceConfig = {
      Type = "simple";
      # --wayland-app-id must match `class` in files/gui/hypr/hyprwinwrap.lua.
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe pkgs.mpv)
        "--no-config"
        "--loop-file=inf"
        "--no-audio"
        "--no-osc"
        "--no-input-default-bindings"
        "--title=waterfall-bg"
        "--wayland-app-id=waterfall-bg"
        "--panscan=1.0"
        "--really-quiet"
        "%h/pic/wl/video/waterfall_loop.mp4"
      ];
      RestartSec = 5;
    };
  };
}
