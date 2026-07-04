{ pkgs, ... }:
{
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.nerd-fonts.fira-code # FiraCode Nerd Font for terminal symbols
    pkgs.material-symbols # Material Design icon font for panels/quickshell
    pkgs.oldschool-pc-font-pack # Retro PC bitmap/outline set (Px437/PxPlus collection)
    pkgs.sf-pro-display # Apple SF Pro Display (ported from legacy Salt config)
    pkgs.anurati # Geometric display font
    pkgs.alfa-slab-one # Bold slab-serif display font
  ];
}
