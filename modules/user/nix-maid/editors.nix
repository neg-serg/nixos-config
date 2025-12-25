{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
  devEnabled = config.features.dev.enable or false;

  # Helix Config Source
  helixSrc = ../../../files/helix;
in
  lib.mkIf devEnabled (lib.mkMerge [
    {
      environment.systemPackages = [
        pkgs.helix # A post-modern text editor
      ];
    }
    (n.mkHomeFiles {
      # Helix Configuration
      ".config/helix".source = n.linkImpure helixSrc;
    })
  ])
