{ pkgs, ... }:
{
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.material-symbols # Material Design icon font for panels/quickshell
    pkgs.nerd-fonts.fira-code # FiraCode Nerd Font for terminal symbols
    pkgs.noto-fonts # Google Noto multilingual fonts
    pkgs.noto-fonts-cjk-sans # CJK sans-serif fonts
    pkgs.noto-fonts-color-emoji # Color emoji fonts
  ];
}
