{
  lib,
  config,
  ...
}:
lib.mkIf (config.features.flatpak.enable or true) {
  # Flatpak Integration
  services.flatpak.enable = true;
}
