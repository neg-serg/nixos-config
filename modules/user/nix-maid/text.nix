{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.features.text.tex.enable or false) {
  environment.systemPackages = with pkgs; [
    rubber
    (texlive.combined.scheme-full.withPackages (ps: [
      ps.cyrillic
      ps.cyrillic-bin
      ps.collection-langcyrillic
      ps.context-cyrillicnumbers
    ]))
  ];
}
