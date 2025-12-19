{
  pkgs,
  lib,
  config,
  impurity,
  ...
}: let
  cfg = config.features.gui.walker;
  walkerRoot = ../../../files/walker;
in
  lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [pkgs.walker]; # Wayland-native application runner

    users.users.neg.maid.file.home = {
      ".config/walker/config.toml".source = impurity.link (walkerRoot + /config.toml);
      ".config/walker/themes".source = impurity.link (walkerRoot + /themes);
    };
  }
