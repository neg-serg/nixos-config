{
  lib,
  config,
  _pkgs,
  ...
}:
{
  # Prefer native NixOS module logic but manual implementation to hide binary from system path.
  # programs.adb.enable = true; <-- installs android-tools to systemPackages

  # Enable udev rules for Android devices
  # Note: android-udev-rules is superseded by systemd built-in rules or handled by programs.adb
  # services.udev.packages = [ pkgs.android-udev-rules ];

  # Create adbusers group
  users.groups.adbusers = { };

  # Add the primary user to 'adbusers' only when this module is imported.
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "adbusers" ];

  # Packages moved to devShells.android
  environment.systemPackages = [ ];
}
