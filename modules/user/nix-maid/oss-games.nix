{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    superTux # 2D platformer
    superTuxKart # arcade kart racer
    wesnoth # turn-based strategy with campaigns
    xonotic # arena FPS
    zeroad # RTS set in ancient warfare
  ];
}
