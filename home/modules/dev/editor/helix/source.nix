{
  lib,
  config,
  ...
}: let
  xdg = import ../../../lib/xdg-helpers.nix {inherit lib;};
in
  lib.mkIf (config.features.dev.enable or false)
  (xdg.mkXdgSource "helix/languages.toml" {
    source = config.lib.file.mkOutOfStoreSymlink "${config.neg.dotfilesRoot}/helix/.config/helix/languages.toml";
  })
