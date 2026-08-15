##
# Module: media/audio/mpd-packages
# Purpose: Provide the MPD client/tool stack system-wide when the MPD feature is enabled.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.mpd";
  packages = [
    pkgs.rmpc # minimal MPD CLI used in scripts/notifications
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
    networking.firewall.allowedTCPPorts = [ 6600 ];
  };
}
