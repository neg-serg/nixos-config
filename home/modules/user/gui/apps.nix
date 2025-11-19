{
  lib,
  config,
  ...
}:
with lib;
  mkIf config.features.gui.enable {
    programs.wallust.enable = true;
  }
