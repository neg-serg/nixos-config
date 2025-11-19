{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf (config.features.media.audio.apps.enable or false) {
  # Packages moved to modules/media/multimedia-packages.nix for system-wide installation.
}
