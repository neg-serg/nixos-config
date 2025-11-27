##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of Home Manager state.
# Trigger: enabled for workstation role (desktop-first environments).
{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.roles.workstation.enable or false;
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.alsa-utils # amixer/alsamixer fallback when PipeWire fails
      pkgs.coppwr # PipeWire CLI to copy/paste complex graphs
      pkgs.pw-volume # minimal PipeWire volume controller for scripts
      pkgs.pwvucontrol # PipeWire patchbay GUI (JACK-like)
      pkgs.helvum # GTK patchbay for PipeWire nodes
      pkgs.qpwgraph # Qt patchbay, best for big graphs
      pkgs.open-music-kontrollers.patchmatrix # advanced patch matrix for LV2/JACK bridging
    ];
  };
}
