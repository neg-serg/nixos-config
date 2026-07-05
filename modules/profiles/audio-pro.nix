{ lib, config, ... }:
with lib;
mkIf (builtins.elem "audio-pro" (config.features.profiles or [ ])) {
  features = {
    gui.enable = mkDefault true;
    media.audio = {
      core.enable = mkDefault true;
      apps.enable = mkDefault true;
      creation.enable = mkDefault true;
      mpd.enable = mkDefault true;
      proAudio.enable = mkDefault true;
    };
    dev.haskell.enable = mkDefault false;
  };
}
