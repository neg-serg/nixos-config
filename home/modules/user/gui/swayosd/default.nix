{
  lib,
  config,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) {
    services.swayosd.enable = true;
  }
