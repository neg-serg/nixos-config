##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of user profile state.
# Trigger: enabled for workstation role (desktop-first environments).
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.roles.workstation.enable or false;
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      # -- CLI --
      pkgs.alsa-utils # amixer/alsamixer fallback when PipeWire fails
      pkgs.pw-volume # minimal PipeWire volume controller for scripts

      # -- RME HDSPe --
      pkgs.hdspeconf # HDSPe matrix mixer & config (for snd-hdspe driver)
      pkgs.alsa-tools # hdspmixer, hdsploader (RME HDSPe userland tools)

      # -- GUI Patchbays --
      pkgs.coppwr # PipeWire CLI to copy/paste complex graphs
    ];

    services.udev.extraRules = ''
      KERNEL=="rtc0", GROUP="audio"
      KERNEL=="hpet", GROUP="audio"
    '';
  };
}
