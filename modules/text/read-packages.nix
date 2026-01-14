##
# Module: text/read-packages
# Purpose: Provide reading/preview/OCR utilities system-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.text.read.enable or false;
  packages = [
    pkgs.amfora # Gemini/Gopher terminal client
    pkgs.antiword # convert MS Word documents
    pkgs.epr # CLI EPUB reader
    pkgs.glow # markdown viewer
    pkgs.lowdown # markdown cat
    pkgs.sioyek # Qt document viewer
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
