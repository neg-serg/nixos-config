{
  lib,
  pkgs,
  ...
}:
{
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      mpv = {
        executable = "${lib.getBin pkgs.mpv}/bin/mpv"; # General-purpose media player, fork of MPlayer and mplayer2
        profile = "${pkgs.firejail}/etc/firejail/mpv.profile"; # Namespace-based sandboxing tool for Linux
      };
    };
  };
}
