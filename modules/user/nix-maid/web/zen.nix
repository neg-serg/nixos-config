{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.features.web.zen;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;
in
{
  config = lib.mkIf (webEnabled && guiEnabled && (cfg.enable or false)) {
    environment.systemPackages = [
      inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default # Zen Browser (Firefox-based; profile migrated manually to ~/.config/zen)
    ];

    environment.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1";
    };
  };
}
