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
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
  packages = [
    # -- Analysis --
    (onDemand {
      name = "dr14_tmeter";
      attr = "dr14_tmeter";
    }) # DR14 dynamic-range meter, built on first use
    pkgs.essentia-extractor # bulk audio feature extractor (HQ descriptors)
    (onDemand {
      name = "sonic-visualiser";
      attr = "sonic-visualiser";
    }) # annotate spectra/sonograms, built on first use
    # Its desktop file lives inside the on-demand root; recreate the menu entry.
    # The icon name only resolves inside that root, so the menu shows the theme
    # fallback until the icon is shipped separately.
    (pkgs.makeDesktopItem {
      name = "sonic-visualiser";
      desktopName = "Sonic Visualiser";
      comment = "View and analyse the contents of music audio files";
      exec = "sonic-visualiser %U";
      icon = "sonic-visualiser";
      categories = [
        "AudioVideo"
        "Audio"
        "Graphics"
      ];
      mimeTypes = [ "audio/x-wav" ];
    })
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
    # SoundCloud downloader: occasional by nature, so the launcher builds it on
    # first call instead of carrying it through every switch.
    (onDemand {
      name = "scdl";
      attr = "scdl";
    })

    # -- Tagging --
    pkgs.id3v2 # low-level ID3 tag editor

    # -- Recording --
  ];
in
{
  environment.systemPackages = lib.mkAfter packages;
}
