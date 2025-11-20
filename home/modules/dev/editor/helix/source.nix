{
  lib,
  config,
  xdg,
  ...
}: let
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  lib.mkIf (config.features.dev.enable or false)
  (xdg.mkXdgSource "helix/languages.toml" {
    source = filesRoot + "/helix/languages.toml";
  })
