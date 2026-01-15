{
  pkgs,
  lib,
  config,
  ...
}:
let
  # --- Scripts & Package ---
  scriptPkgs = [
    pkgs.mpvScripts.cutter # cut/extract video segments from mpv
    pkgs.mpvScripts.mpris # MPRIS integration for media keys
    pkgs.mpvScripts.quality-menu # quality/stream switcher menu
    pkgs.mpvScripts.sponsorblock # skip sponsors on YouTube videos
    pkgs.mpvScripts.thumbfast # instant thumbnails in seek bar
    pkgs.mpvScripts.uosc # modern minimalist UI with controls
  ];

  mpvPackage = pkgs.mpv.override {
    # General-purpose media player, fork of MPlayer and mplayer2
    scripts = scriptPkgs;
    mpv = pkgs.mpv-unwrapped.override {
      # General-purpose media player, fork of MPlayer and mplayer2
      vapoursynthSupport = true;
    };
  };
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    lib.mkMerge [
      {
        # Install Package
        users.users.neg.packages = [ mpvPackage ];
      }
    ]
  );
}
