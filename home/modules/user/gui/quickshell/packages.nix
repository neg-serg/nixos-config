{
  lib,
  pkgs,
  config,
  rsmetrxProvider ? null,
  ...
}:
with lib;
  mkIf (config.features.gui.enable && (config.features.gui.qt.enable or false) && (! (config.features.devSpeed.enable or false))) {
    home.packages = config.lib.neg.pkgsList (
      lib.optionals (rsmetrxProvider != null) [(rsmetrxProvider pkgs)]
    );
  }
