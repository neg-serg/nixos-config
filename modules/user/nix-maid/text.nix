{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.features.text.tex.enable or false) {
  environment.systemPackages = with pkgs; [
    rubber # Automated system for building LaTeX documents
    (texlive.combined.scheme-full.withPackages (ps: [
      ps.cyrillic # Cyrillic fonts for LaTeX
      ps.cyrillic-bin # Cyrillic binaries for LaTeX
      ps.collection-langcyrillic # Cyrillic language collection
      ps.context-cyrillicnumbers # Cyrillic numbers for Context
    ])) # Full TeX Live distribution with Cyrillic support
  ];
}
