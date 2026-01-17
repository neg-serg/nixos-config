##
# Module: text/manipulate-packages
# Purpose: Provide JSON/HTML/YAML manipulation CLIs system-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.text.manipulate.enable or false;
  packages = [
    pkgs.htmlq # jq-like for HTML
    pkgs.jc # convert command output to JSON/YAML
    pkgs.jq # JSON processor
    pkgs.pup # HTML parser
    pkgs.yq-go # YAML processor
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
