{
  lib,
  config,
  ...
}:
lib.mkIf (config.features.flatpak.enable or true) {
  services.flatpak.enable = true; # Flatpak Integration
}
