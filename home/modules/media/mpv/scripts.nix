{
  config,
  lib,
  pkgs,
  ...
}:
let
  scriptPkgs = with pkgs.mpvScripts; [
    cutter # cut and automatically concat videos
    mpris # MPRIS plugin
    quality-menu # ytdl-format quality menu
    seekTo # seek to specific pos.
    sponsorblock # skip sponsored segments
    thumbfast # on-the-fly thumbnailer
    uosc # proximity UI
  ];
in
  lib.mkIf (config.features.gui.enable or false) {
    programs.mpv.package = pkgs.mpv.override {scripts = scriptPkgs;};
  }
