{ lib, config, ... }:
with lib;
mkIf (builtins.elem "desktop" (config.features.profiles or [ ])) {
  features = {
    gui.enable = mkDefault true;
    web.enable = mkDefault true;
    mail.enable = mkDefault true;
    dev.enable = mkDefault true;
    hack.enable = mkDefault true;
    fun.enable = mkDefault true;
    torrent.enable = mkDefault true;
    media.audio = {
      core.enable = mkDefault true;
      apps.enable = mkDefault true;
      creation.enable = mkDefault true;
      mpd.enable = mkDefault true;
    };
    emulators.retroarch.full = mkDefault true;
    dev.ai.enable = mkDefault true;
  };
}
