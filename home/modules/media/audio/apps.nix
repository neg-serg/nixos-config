{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.media.audio.apps.enable {
  home.packages = config.lib.neg.pkgsList [
    # codecs / ripping / players
    pkgs.ape # Monkey's Audio codec/tools
    pkgs.cdparanoia # secure CD audio ripper
    pkgs.cider # Apple Music client
    # analysis
    pkgs.dr14_tmeter # dynamic range (DR14) meter
    pkgs.essentia-extractor # extract audio features (Essentia)
    pkgs.opensoundmeter # real-time audio analyzer
    pkgs.sonic-visualiser # audio analysis/annotation tool
    pkgs.roomeqwizard # Room EQ Wizard (acoustics)
    # tagging
    pkgs.id3v2 # edit MP3 ID3v2 tags
    pkgs.picard # MusicBrainz tagger
    pkgs.unflac # decompress FLAC to WAV/AIFF
    # cli
    pkgs.ncpamixer # TUI mixer for PulseAudio/PipeWire
    pkgs.sox # Swiss-army knife of audio
    # net
    pkgs.nicotine-plus # Soulseek client
    pkgs.scdl # SoundCloud downloader
    pkgs.streamlink # stream to media players
    # misc
    pkgs.screenkey # display pressed keys on screen
  ];
}
