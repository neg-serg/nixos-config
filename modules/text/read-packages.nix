##
# Module: text/read-packages
# Purpose: Provide reading/preview/OCR utilities system-wide (migrated from Home Manager).
{lib, config, pkgs, ...}: let
  enabled = config.features.text.read.enable or false;
  packages = [
    pkgs.amfora # Gemini/Gopher terminal client
    pkgs.antiword # convert MS Word documents
    pkgs.epr # CLI EPUB reader
    pkgs.glow # markdown viewer
    pkgs.lowdown # markdown cat
    pkgs.recoll # desktop full-text search
    pkgs.sioyek # Qt document viewer
    pkgs.tesseract # OCR helper
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
