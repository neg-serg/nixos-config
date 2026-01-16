##
# Module: media/audio/apps-packages
# Purpose: Install audio application helpers (players, analyzers, tagging tools) at the system level.
# Trigger: Enabled automatically for workstation role hosts.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.roles.workstation.enable or false;
  packages = [
    # -- Analysis --
    pkgs.dr14_tmeter # measure dynamic range DR14 style
    pkgs.essentia-extractor # bulk audio feature extractor (HQ descriptors)
    pkgs.sonic-visualiser # annotate spectra/sonograms
  ]
  ++ (lib.optionals (config.features.media.audio.proAudio.enable or false) [
    pkgs.neg.rtcqs # real-time audio latency checklist (rtirq/CPU settings)
    pkgs.opensoundmeter # FFT/RT60 analysis for calibration
    pkgs.roomeqwizard # REW acoustic measurement suite
  ])
  ++ [

    # -- CLI --
    pkgs.sox # swiss-army audio CLI for conversions/effects

    # -- Codecs / Ripping / Players --
    pkgs.ape # Monkey's Audio encoder/decoder for archival rips
    pkgs.cdparanoia # secure CD ripper w/ jitter correction
    pkgs.unflac # convert FLAC cuesheets quickly
  ]
  ++ (lib.optional (config.features.media.audio.cider.enable or false) pkgs.cider) # New look into listening and enjoying Apple Music in style...
  ++ (lib.optional (config.features.media.audio.yandexMusic.enable or false) pkgs."yandex-music")
  ++ [

    # -- Network --
    pkgs.nicotine-plus # Soulseek client
    pkgs.scdl # SoundCloud downloader

    # -- Tagging --
    pkgs.id3v2 # low-level ID3 tag editor
    pkgs.picard # MusicBrainz tagging GUI

    # -- Recording --
    pkgs.screenkey # show keystrokes when recording tutorials
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
