{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf (config.features.gui.enable or false) {
  programs.mpv.scripts = [
    pkgs.mpvScripts.cutter # cut and automatically concat videos
    pkgs.mpvScripts.mpris # MPRIS plugin
    pkgs.mpvScripts.quality-menu # ytdl-format quality menu
    pkgs.mpvScripts.seekTo # seek to specific pos.
    pkgs.mpvScripts.sponsorblock # skip sponsored segments
    pkgs.mpvScripts.thumbfast # on-the-fly thumbnailer
    pkgs.mpvScripts.uosc # proximity UI
  ];
}
