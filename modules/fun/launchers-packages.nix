##
# Module: fun/launchers-packages
# Purpose: Ship Proton/Wine helper utilities system-wide for game launchers.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = (config.lib.neg.enabled "fun") && (config.lib.neg.enabled "gui");
  packages = [
    pkgs.protontricks # Winetricks wrapper for Proton
    pkgs.protonup-ng # install/update Proton-GE builds
    pkgs.vkbasalt # Vulkan post-processing layer
    pkgs.vkbasalt-cli # CLI for vkBasalt configuration
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
