{
  lib,
  config,
  xdg,
  ...
}:
lib.mkIf config.features.cli.icedteaWeb.enable
  (xdg.mkXdgSource "icedtea-web" {source = ./icedtea-web-conf;})
