##
# Module: media/audio/core-packages
# Purpose: Provide core PipeWire/ALSA helper tools at the system level so they are available regardless of Home Manager state.
# Trigger: enabled for workstation role (desktop-first environments).
{lib, config, pkgs, ...}: let
  enabled = config.roles.workstation.enable or false;
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.alsa-utils
      pkgs.coppwr
      pkgs.pw-volume
      pkgs.pwvucontrol
      pkgs.helvum
      pkgs.qpwgraph
      pkgs.open-music-kontrollers.patchmatrix
    ];
  };
}
