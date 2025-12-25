{
  config,
  lib,
  pkgs,
  ...
}: let
  guiEnabled = config.features.gui.enable or false;
  localBinPackages = [
    pkgs.alsa-utils # alsamixer/amixer fallback; direct ALSA control when PipeWire drifts
    pkgs.essentia-extractor # Essentia CLI; pro audio descriptors far beyond ffmpeg
    pkgs.imagemagick # convert/mogrify workhorse; handles odd formats better than feh
    pkgs.neg.albumdetails # TagLib album metadata CLI; richer dump than mediainfo
    pkgs.neg.bpf_host_latency # BCC DNS latency tracer; deeper insight than dig/tcpdump
    pkgs.neg.music_clap # LAION-CLAP embeddings CLI; offline tagging faster than cloud AI
    pkgs.wireplumber # Lua PipeWire session mgr; more tweakable than media-session
  ];
in {
  environment.systemPackages =
    [
      # -- Audio --
      pkgs.cava # console audio visualizer for quickshell HUD
      pkgs.mpc # MPD CLI helper for local scripts
      pkgs.playerctl # MPRIS media controller for bindings
    ]
    ++ lib.optionals guiEnabled localBinPackages;
}
