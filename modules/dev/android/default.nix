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

  environment.systemPackages =
    [
      pkgs.adbfs-rootless # FUSE filesystem for Android (rootless devices)
      pkgs.adbtuifm # TUI file manager over ADB
      pkgs.android-tools # adb/fastboot utilities
      pkgs.scrcpy # remote display/control
    ]
    ++ lib.optionals (pkgs ? fuse3) [pkgs.fuse3]; # fuse helper for adbfs
}
