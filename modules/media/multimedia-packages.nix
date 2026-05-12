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
  enabled = config.features.media.audio.apps.enable or false;
  packages = [
    pkgs.ffmpeg # basic ffmpeg for playback
    pkgs.ffmpegthumbnailer # generate thumbnails for videos (runners/rofi)
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
    (lib.mkIf (config.features.media.webcam.enable or false) {

      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];
    })
  ];
}
