{pkgs, ...}: {
  home.packages = with pkgs; [
    superTuxKart # arcade kart racer
    superTux # 2D platformer
    zeroad # RTS set in ancient warfare
    wesnoth # turn-based strategy with campaigns
    xonotic # arena FPS
  ];
}
