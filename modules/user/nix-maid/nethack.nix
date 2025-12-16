{
  config,
  lib,
  ...
}: let
  cfg = config.features.games.nethack;
  # filesRoot = ../../../files; # Unused
in
  lib.mkIf (cfg.enable or false) {
    # Ensure package is installed (if not globally enabled by games module)
    # environment.systemPackages = [ pkgs.nethack ]; # User's original module implied this or assumed it.

    users.users.neg.maid.file.home = {
      ".nethackrc".text = ''
        OPTIONS=windowtype:curses
        OPTIONS=popup_dialog
        OPTIONS=splash_screen
        OPTIONS=guicolor
        OPTIONS=perm_invent
      '';
    };
  }
