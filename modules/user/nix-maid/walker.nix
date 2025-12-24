{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
  cfg = config.features.gui.walker;
  walkerRoot = ../../../files/walker;
in
  lib.mkIf (cfg.enable or false) (lib.mkMerge [
    {
      environment.systemPackages = [pkgs.walker]; # Wayland-native application runner
    }

    (n.mkHomeFiles {
      ".config/walker/config.toml".source = n.linkImpure (walkerRoot + /config.toml);
      ".config/walker/themes".source = n.linkImpure (walkerRoot + /themes);
    })
  ])
