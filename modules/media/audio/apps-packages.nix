##
# Module: media/audio/apps-packages
# Purpose: Install audio application helpers (players, analyzers, tagging tools) at the system level.
# Trigger: Enabled automatically for workstation role hosts.
{lib, config, pkgs, ...}: let
  enabled = config.roles.workstation.enable or false;
  packages = [
    # codecs / ripping / players
    pkgs.ape
    pkgs.cdparanoia
    pkgs.cider
    # analysis
    pkgs.dr14_tmeter
    pkgs.essentia-extractor
    pkgs.opensoundmeter
    pkgs.sonic-visualiser
    pkgs.roomeqwizard
    # tagging
    pkgs.id3v2
    pkgs.picard
    pkgs.unflac
    # cli
    pkgs.ncpamixer
    pkgs.sox
    # net
    pkgs.nicotine-plus
    pkgs.scdl
    pkgs.streamlink
    # misc
    pkgs.screenkey
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
