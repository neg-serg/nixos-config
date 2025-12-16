{
  #  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.games.dosemu;
  filesRoot = ../../../home/files;
in
  lib.mkIf (cfg.enable or false) {
    # environment.systemPackages = [pkgs.dosemu2];

    users.users.neg.maid.file.home = {
      ".dosemu/disclaimer".source = "${filesRoot}/dosemu/disclaimer";
      ".dosemu/boot.log".source = "${filesRoot}/dosemu/boot.log";
      ".dosemu/drive_c/autoexec.bat".source = "${filesRoot}/dosemu/drive_c/autoexec.bat";
      ".dosemu/drive_c/config.sys".source = "${filesRoot}/dosemu/drive_c/config.sys";
    };
  }
