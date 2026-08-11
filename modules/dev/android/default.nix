{
  lib,
  pkgs,
  config,
  ...
}:
{
  # nixpkgs 26.05 removed the programs.adb module (see nixpkgs rename.nix);
  # systemd 258 uaccess rules grant Android device access automatically.
  # Extras (adbfs-rootless, adbtuifm) stay in devShells.android.

  # Create adbusers group
  users.groups.adbusers = { };

  # Add the primary user to 'adbusers' only when this module is imported.
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "adbusers" ];
  environment.systemPackages = [
    pkgs.android-tools # Android ADB and fastboot tools
  ];
}
