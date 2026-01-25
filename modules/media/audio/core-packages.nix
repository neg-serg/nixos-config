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

      # -- GUI Patchbays --
      pkgs.coppwr # PipeWire CLI to copy/paste complex graphs
      pkgs.helvum # GTK patchbay for PipeWire nodes
      pkgs.open-music-kontrollers.patchmatrix # advanced patch matrix for LV2/JACK bridging
      pkgs.qpwgraph # Qt patchbay, best for big graphs
    ];

    services.udev.extraRules = ''
      KERNEL=="rtc0", GROUP="audio"
      KERNEL=="hpet", GROUP="audio"
    '';
  };
}
