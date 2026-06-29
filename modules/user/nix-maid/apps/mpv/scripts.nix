{
  lib,
  config,
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
      ".config/mpv/script-opts/osc.conf".source = n.linkImpure ../../../../files/scripts/osc.conf;
      ".config/mpv/script-opts/uosc.conf".source = n.linkImpure ../../../../files/scripts/uosc.conf;
    }
  );
}
