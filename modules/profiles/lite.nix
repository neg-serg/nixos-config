{ lib, config, ... }:
with lib;
mkIf (builtins.elem "lite" (config.features.profiles or [ ])) {
  features = {
    torrent.enable = mkDefault false;
    gui.enable = mkDefault false;
    mail.enable = mkDefault false;
    hack.enable = mkDefault false;
    dev = {
      enable = mkDefault false;
      ai.enable = mkDefault false;
    };
    dev.unreal.enable = mkForce false;
    media.audio = {
      core.enable = mkDefault false;
      apps.enable = mkDefault false;
      creation.enable = mkDefault false;
      mpd.enable = mkDefault false;
    };
    web = {
      enable = mkDefault false;
      tools.enable = mkDefault false;
      prefs.fastfox.enable = mkDefault false;
    };
    emulators.retroarch.full = mkDefault false;
    fun.enable = mkDefault false;
  };
}
