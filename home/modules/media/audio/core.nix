{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf config.features.media.audio.core.enable {
  # Packages moved to modules/media/audio/core-packages.nix (system-wide installation).
}
