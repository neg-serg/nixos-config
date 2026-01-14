{ pkgs, ... }:
{
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.material-symbols # Material Design icon font for panels/quickshell
    pkgs.oldschool-pc-font-pack # Retro PC bitmap/outline set (Px437/PxPlus collection)
    pkgs.px437-ibm-conv-e # Px437 IBM Conv pixel outline font
  ];
}
