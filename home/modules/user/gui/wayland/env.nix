{
  lib,
  config,
  ...
}:
with lib;
  mkIf config.features.gui.enable {
    # Reserved for Wayland-specific session variables if needed
    home.sessionVariables = {};
  }
