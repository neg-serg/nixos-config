{
  config,
  lib,
  pkgs,
  neg,
  ...
}:
let
  n = neg;
  cfg = config.features.games.nethack;
in
{
  config = lib.mkIf (cfg.enable or false) (
    n.mkHomeFiles {
      ".nethackrc".text = ''
        OPTIONS=windowtype:curses
        OPTIONS=popup_dialog
        OPTIONS=splash_screen
        OPTIONS=guicolor
        OPTIONS=perm_invent
      '';
    }
    // {
      environment.systemPackages = [ pkgs.nethack ]; # Rogue-like game
    }
  );
}
