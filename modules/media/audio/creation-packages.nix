##
# Module: media/audio/creation-packages
# Purpose: Provide the creative audio stack (DAWs, synths, editors) system-wide for workstation hosts.
{lib, config, pkgs, ...}: let
  enabled = config.roles.workstation.enable or false;
  packages = [
    pkgs.bespokesynth
    pkgs.glicol-cli
    pkgs.dexed
    pkgs.noisetorch
    pkgs.ocenaudio
    pkgs.reaper
    pkgs.rnnoise
    pkgs.stochas
    pkgs.vcv-rack
    pkgs.vital
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
