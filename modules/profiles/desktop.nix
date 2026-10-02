{ lib, config, ... }:
lib.mkIf (builtins.elem "desktop" (config.features.profiles or [ ])) {
  features = {
    gui.enable = lib.mkDefault true;
    web.enable = lib.mkDefault true;
    mail.enable = lib.mkDefault true;
    dev.enable = lib.mkDefault true;
    fun.enable = lib.mkDefault true;
    torrent.enable = lib.mkDefault true;
    media.audio = {
      core.enable = lib.mkDefault true;
      apps.enable = lib.mkDefault true;
      creation.enable = lib.mkDefault true;
      mpd.enable = lib.mkDefault true;
    };
    dev.ai.enable = lib.mkDefault true;
    gui.vicinae.enable = lib.mkDefault true;
  };
}
