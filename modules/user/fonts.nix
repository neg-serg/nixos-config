{pkgs, ...}: {
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.liberation_ttf # Liberation Fonts, replacements for Times New Roman, Arial, and Courier New
    pkgs.nerd-fonts.fira-code # firacode nerdfont
    pkgs.proggyfonts # yet another fonts for coding
    pkgs.symbola # Basic Latin, Greek, Cyrillic and many Symbol blocks of Unicode
    pkgs.texlivePackages.opensans # The Open Sans font family, and LaTeX support
  ];
}
