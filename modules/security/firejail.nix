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
        executable = "${lib.getBin pkgs.mpv}/bin/mpv";
        profile = "${pkgs.firejail}/etc/firejail/mpv.profile";
      };
      zathura = {
        executable = "${lib.getBin pkgs.zathura}/bin/zathura";
        profile = "${pkgs.firejail}/etc/firejail/zathura.profile";
      };
      telegram-desktop = {
        executable = "${lib.getBin pkgs.telegram-desktop}/bin/telegram-desktop";
        profile = "${pkgs.firejail}/etc/firejail/telegram-desktop.profile";
      };
      qutebrowser = {
        executable = "${lib.getBin pkgs.qutebrowser}/bin/qutebrowser";
        profile = "${pkgs.firejail}/etc/firejail/qutebrowser.profile";
      };
      thunar = {
        executable = "${lib.getBin pkgs.xfce.thunar}/bin/thunar";
        profile = "${pkgs.firejail}/etc/firejail/thunar.profile";
      };
    };
  };
}
