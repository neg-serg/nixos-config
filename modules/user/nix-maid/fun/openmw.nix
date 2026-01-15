{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.games.openmw;
in
{
  config = lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [ pkgs.openmw ]; # Unofficial open source engine reimplementation of the gam...
  };
}
