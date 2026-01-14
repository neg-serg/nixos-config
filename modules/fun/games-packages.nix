##
# Module: fun/games-packages
# Purpose: Provide casual/retro games that used to be installed in other configs.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.fun.enable or false;
  packages = [
    pkgs.abuse # classic side-scrolling shooter customizable with LISP
    pkgs.airshipper # Veloren voxel client/launcher
    pkgs.angband # roguelike
    pkgs.brogue-ce # roguelike (community edition)
    pkgs.crawl # roguelike
    pkgs.crawlTiles # roguelike tiles build
    pkgs.endless-sky # space exploration game
    pkgs.fheroes2 # free Heroes 2 implementation
    pkgs.flare # fantasy action RPG using the FLARE engine
    pkgs.gnuchess # GNU chess engine
    pkgs.gzdoom # open-source Doom engine
    pkgs.jazz2 # open source Jazz Jackrabbit 2
    pkgs.nethack # roguelike

    pkgs.shattered-pixel-dungeon # roguelike
    pkgs.xaos # interactive fractal explorer
  ];
in
{
  config = lib.mkMerge [
    (lib.mkIf enabled {
      environment.systemPackages = lib.mkAfter packages;
    })
    (lib.mkIf config.features.games.openmw.enable {
      environment.systemPackages = [ pkgs.openmw ];
    })
  ];
}
