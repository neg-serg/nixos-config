{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.finance.tws.enable or false;
  package = pkgs.neg.tws or pkgs.tws;
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [package];
  };
}
