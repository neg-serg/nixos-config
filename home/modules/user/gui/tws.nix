{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.finance.tws.enable or false;
  package = pkgs.neg.tws or pkgs.tws;
in
  lib.mkIf enabled {
    home.packages = config.lib.neg.pkgsList [package];
  }
