{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.cli.broot;
  brootRoot = ../../../files/shell/broot;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [pkgs.broot]; # terminal file manager for visualizing and navigating directory trees

    users.users.neg.maid.file.home = {
      ".config/broot/conf.hjson".source = "${brootRoot}/conf.hjson";
      ".config/broot/conf.toml".source = "${brootRoot}/conf.toml";
      ".config/broot/to_stdout.hjson".source = "${brootRoot}/to_stdout.hjson";
      ".config/broot/launcher".source = "${brootRoot}/launcher";
    };
  }
