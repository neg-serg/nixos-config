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
    pkgs.amfora # a terminal browser for the Gemini protocol
    pkgs.antiword # convert MS Word documents to text, PostScript and XML
    pkgs.epr # CLI Epub reader
    pkgs.glow # terminal based markdown reader
    pkgs.lowdown # simple markdown translator
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
