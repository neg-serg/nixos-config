{ pkgs, ... }:
{
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.material-symbols # Material Design icon font for panels/quickshell
    pkgs.nerd-fonts.fira-code # FiraCode Nerd Font for terminal symbols
    pkgs.noto-fonts # Google Noto multilingual fonts
    pkgs.noto-fonts-cjk-sans # CJK sans-serif fonts
    pkgs.noto-fonts-color-emoji # Color emoji fonts
    pkgs.ttf-code2000 # Code2000 shareware Unicode font (broad BMP script coverage)
    pkgs.ttf-code2001 # Code2001 freeware font: Plane 1 ancient/historic scripts (Linear B, Gothic, ...)
    pkgs.ttf-code2002 # Code2002 freeware font: Plane 2 rare CJK ideographs (Ext B-I)
    pkgs.ttf-code20x3 # Code20X3 freeware font: Plane 3 CJK Extensions G/H
  ];
}
