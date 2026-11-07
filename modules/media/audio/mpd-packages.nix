##
# Module: media/audio/mpd-packages
# Purpose: Open the MPD control port when the MPD feature is enabled. The
# clients themselves (mpc, euphonica, playerctl) are installed by the user
# media layer (modules/user/nix-maid/sys/media.nix); nothing here belongs in
# the system closure.
{
  lib,
  config,
  ...
}:
let
  enabled = config.lib.neg.enabled "media.audio.mpd";
in
{
  config = lib.mkIf enabled {
    networking.firewall.allowedTCPPorts = [ 6600 ];
  };
}
