##
# Module: media/audio/apps-packages
# Purpose: Install audio application helpers (players, analyzers, tagging tools) at the system level.
# Trigger: Enabled automatically for workstation role hosts.
{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.roles.workstation.enable or false;
  packages = [
    # codecs / ripping / players
    pkgs.ape # Monkey's Audio encoder/decoder for archival rips
    pkgs.cdparanoia # secure CD ripper w/ jitter correction
    pkgs.cider # Apple Music client w/ Discord presence and EQ
    pkgs."yandex-music" # Yandex Music desktop client
    # analysis
    pkgs.dr14_tmeter # measure dynamic range DR14 style
    pkgs.essentia-extractor # bulk audio feature extractor (HQ descriptors)
    pkgs.opensoundmeter # FFT/RT60 analysis for calibration
    pkgs.sonic-visualiser # annotate spectra/sonograms
    pkgs.roomeqwizard # REW acoustic measurement suite
    # tagging
    pkgs.id3v2 # low-level ID3 tag editor
    pkgs.picard # MusicBrainz tagging GUI
    pkgs.unflac # convert FLAC cuesheets quickly
    # cli
    pkgs.ncpamixer # ncurses PulseAudio mixer (fallback)
    pkgs.sox # swiss-army audio CLI for conversions/effects
    # net
    pkgs.nicotine-plus # Soulseek client
    pkgs.slskd # Soulseek daemon with web UI
    pkgs.scdl # SoundCloud downloader
    pkgs.streamlink # stream extractor (Twitch/YT) for mpv feeding
    # misc
    pkgs.screenkey # show keystrokes when recording tutorials
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
