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
    (pkgs.stdenv.mkDerivation {
      pname = "mpv-hdr-auto-switch";
      version = "0.1.0";
      src = ../../../../../files/mpv/hdr-auto-switch.lua;
      scriptName = "hdr-auto-switch.lua"; # auto-switch Hyprland cm to HDR on HDR content
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/mpv/scripts
        cp $src $out/share/mpv/scripts/$scriptName
      '';
    })
  ];

  mpvUnwrapped =
    (pkgs.mpv-unwrapped.override {
      vapoursynthSupport = true;
    }).overrideAttrs
      (old: {
        env.NIX_CFLAGS_COMPILE =
          toString (old.env.NIX_CFLAGS_COMPILE or "")
          + " -O3 -ftree-parallelize-loops=8 -floop-parallelize-all";
      });

  mpvPackage = pkgs.mpv.override {
    mpv-unwrapped = mpvUnwrapped;
    scripts = scriptPkgs;
  };
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        # Install Package
        users.users.neg.packages = [ mpvPackage ];
      }
    ]
  );
}
