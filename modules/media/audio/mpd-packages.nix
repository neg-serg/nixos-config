##
# Module: media/audio/mpd-packages
# Purpose: Provide the MPD client/tool stack system-wide when the MPD feature is enabled.
{lib, config, pkgs, ...}: let
  enabled = config.features.media.audio.mpd.enable or false;
  cantataPkg = pkgs.neg.cantata or pkgs.cantata;
  packages = [
    pkgs.rmpc
    cantataPkg
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
