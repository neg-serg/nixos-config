{
  lib,
  config,
  pkgs,
  ...
}: {
  # Prefer native NixOS module for ADB: installs rules + tools and defines 'adbusers'.
  programs.adb.enable = true;

  # Add the primary user to 'adbusers' only when this module is imported.
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter ["adbusers"];
}
