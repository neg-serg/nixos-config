##
# Module: media/multimedia-packages
# Purpose: Provide general multimedia tooling (FFmpeg, metadata helpers, mpvc) system-wide.
{lib, config, pkgs, ...}: let
  enabled = config.features.media.audio.apps.enable or false;
  packages = [
    pkgs.ffmpeg-full
    pkgs.ffmpegthumbnailer
    pkgs.gmic
    pkgs.imagemagick
    pkgs.mediainfo
    pkgs.media-player-info
    pkgs.neg.mkvcleaner
    pkgs.mpvc
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
