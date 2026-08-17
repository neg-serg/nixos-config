##
# Module: media/multimedia-packages
# Purpose: Provide general multimedia tooling (FFmpeg, metadata helpers, mpvc) system-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.apps";
  packages = [
    pkgs.ffmpeg # basic ffmpeg for playback
    pkgs.ffmpegthumbnailer # generate video thumbnails for previews
    pkgs.imagemagick # fallback convert/mogrify for pipelines
    pkgs.media-player-info # udev HW database for player IDs
    pkgs.mediainfo # inspect video/audio metadata quickly
    pkgs.mpvc # mpv TUI controller
  ];
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      environment.systemPackages = lib.mkAfter packages;
    })
    (lib.mkIf (config.lib.neg.enabled "media.webcam") {

      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];
    })
  ];
}
