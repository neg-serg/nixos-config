##
# Module: fun/launchers-packages
# Purpose: Ship Proton/Wine helper utilities system-wide for game launchers.
{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled =
    (config.features.fun.enable or false)
    && (config.features.gui.enable or false);
  packages = [
    pkgs.protonplus # Proton/Wine prefix manager
    pkgs.protontricks # Winetricks wrapper for Proton
    pkgs.protonup-ng # install/update Proton-GE builds
    pkgs.vkbasalt # Vulkan post-processing layer
    pkgs.vkbasalt-cli # CLI for vkBasalt configuration
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
