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
      zathura = {
        executable = "${lib.getBin pkgs.zathura}/bin/zathura"; # Highly customizable and functional PDF viewer
        profile = "${pkgs.firejail}/etc/firejail/zathura.profile"; # Namespace-based sandboxing tool for Linux
      };
      telegram-desktop = {
        executable = "${lib.getBin pkgs.telegram-desktop}/bin/telegram-desktop"; # Telegram Desktop messaging app
        profile = "${pkgs.firejail}/etc/firejail/telegram-desktop.profile"; # Namespace-based sandboxing tool for Linux
      };
    };
  };
}
