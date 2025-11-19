{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.media.audio.apps.enable {
  # Packages moved to modules/media/audio/apps-packages.nix for system-wide installation.
}
