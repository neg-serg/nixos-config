{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.dev;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.tig ]; # Text-mode interface for git
      }
      (n.mkHomeFiles {
        ".config/tig/config".source = n.linkImpure ../../../../files/tig/config;
      })
    ]
  );
}
