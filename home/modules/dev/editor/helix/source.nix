{
  lib,
  config,
  ...
}: let
  xdg = import ../../../lib/xdg-helpers.nix {inherit lib;};
  filesRoot = "${config.neg.hmConfigRoot}/files";
in
  lib.mkIf (config.features.dev.enable or false)
  (xdg.mkXdgSource "helix/languages.toml" {
    source = filesRoot + "/helix/languages.toml";
  })
