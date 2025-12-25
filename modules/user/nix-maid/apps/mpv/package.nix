{
  pkgs,
  lib,
  config,
  ...
}: let
  # --- Scripts & Package ---
  scriptPkgs = [
    pkgs.mpvScripts.cutter
    pkgs.mpvScripts.mpris
    pkgs.mpvScripts.quality-menu
    pkgs.mpvScripts.sponsorblock
    pkgs.mpvScripts.thumbfast
    pkgs.mpvScripts.uosc
  ];

  mpvPackage = pkgs.mpv.override {
    scripts = scriptPkgs;
    mpv = pkgs.mpv-unwrapped.override {
      vapoursynthSupport = true;
    };
  };
in {
  config = lib.mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      # Install Package
      users.users.neg.packages = [mpvPackage];
    }
  ]);
}
