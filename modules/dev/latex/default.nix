{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable = (config.lib.neg.enabled "dev") && (config.lib.neg.enabled "dev.latex");
  # Same TeX Live set as the `latex` devshell (flake/devshells/latex.nix).
  texlive = pkgs.texlive.combined.scheme-full.withPackages (ps: [
    ps.cyrillic
    ps.cyrillic-bin
    ps.collection-langcyrillic
    ps.context-cyrillicnumbers
  ]);
in
lib.mkIf enable {
  environment.systemPackages = [
    texlive # TeX Live 2025: pdflatex/xelatex/lualatex, tikz, Cyrillic
  ];
}
