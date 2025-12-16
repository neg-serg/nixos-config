{
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.features.distros.distrobox.enable or true) {
  # Distrobox
  environment.systemPackages = [pkgs.distrobox];
}
