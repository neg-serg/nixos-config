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
  enabled = config.lib.neg.enabled "text.read";
  packages = [
    pkgs.antiword # convert MS Word documents to text, PostScript and XML
    pkgs.epr # CLI Epub reader
    pkgs.lowdown # simple markdown translator
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
