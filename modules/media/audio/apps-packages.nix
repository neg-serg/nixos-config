##
# Module: media/audio/apps-packages
# Purpose: Install audio application helpers (players, analyzers, tagging tools) at the system level.
# Trigger: always enabled.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  packages = [
    # -- Analysis --
    pkgs.dr14_tmeter # measure dynamic range DR14 style
    pkgs.essentia-extractor # bulk audio feature extractor (HQ descriptors)
    pkgs.sonic-visualiser # annotate spectra/sonograms
  ]
  ++ [

    # -- CLI --
    pkgs.sox # swiss-army audio CLI for conversions/effects
    # -- Codecs / Ripping / Players --
    pkgs.cdparanoia # secure CD ripper w/ jitter correction
    pkgs.unflac # convert FLAC cuesheets quickly
  ]
  ++ (lib.optional (config.lib.neg.enabled "media.audio.cider") pkgs.cider) # New look into listening and enjoying Apple Music in style...
  ++ [

    # -- Network --
    pkgs.nicotine-plus # Soulseek client
    pkgs.waves # keyboard-driven terminal music player with Soulseek/Last.fm
    pkgs.scdl # SoundCloud downloader

    # -- Tagging --
    pkgs.id3v2 # low-level ID3 tag editor

    # -- Recording --
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
