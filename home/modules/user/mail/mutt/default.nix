{
  lib,
  config,
  xdg,
  ...
}:
with lib;
  mkIf config.features.mail.enable (
    lib.mkMerge [
      (xdg.mkXdgSource "mutt" {source = ./conf;})
    ]
  )
