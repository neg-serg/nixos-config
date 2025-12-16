{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.gui.walker;
  walkerRoot = ../../../home/files/walker;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [pkgs.walker];

    users.users.neg.maid.file.home = {
      ".config/walker/config.toml".source = "${walkerRoot}/config.toml";
      ".config/walker/themes".source = "${walkerRoot}/themes";
    };
  }
