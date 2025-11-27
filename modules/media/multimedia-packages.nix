##
# Module: media/multimedia-packages
# Purpose: Provide general multimedia tooling (FFmpeg, metadata helpers, mpvc) system-wide.
{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.media.audio.apps.enable or false;
  packages = [
    pkgs.ffmpeg-full # everything-enabled ffmpeg build for transcoding
    pkgs.ffmpegthumbnailer # generate thumbnails for videos (runners/rofi)
    pkgs.gmic # advanced image filters/CLI for batch work
    pkgs.imagemagick # fallback convert/mogrify for pipelines
    pkgs.mediainfo # inspect video/audio metadata quickly
    pkgs.media-player-info # udev HW database for player IDs
    pkgs.neg.mkvcleaner # custom Matroska cleanup tool
    pkgs.mpvc # mpv TUI controller
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
