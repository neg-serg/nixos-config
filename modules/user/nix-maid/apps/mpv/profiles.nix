{
  config,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    n.mkHomeFiles {
      ".config/mpv/profiles.conf".source = n.linkImpure ../../../../../files/mpv/profiles.conf;
    }
  );
}
