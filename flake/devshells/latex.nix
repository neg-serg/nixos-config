{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.rubber # Wrapper for LaTeX and friends
    (pkgs.texlive.combined.scheme-full.withPackages (ps: [
      ps.cyrillic
      ps.cyrillic-bin
      ps.collection-langcyrillic
      ps.context-cyrillicnumbers
    ]))
    pkgs.sioyek # PDF viewer designed for research papers and technical books
  ];
}
