{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.media.audio.creation.enable {
  # Packages moved to modules/media/audio/creation-packages.nix for system-wide installation.
}
