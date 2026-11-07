{
  lib,
  pkgs,
  config,
  ...
}:
let
  # adb/fastboot are needed occasionally, not in every session: the launcher
  # builds android-tools (272 MiB closure) on first use and GC-roots it under
  # $HOME instead of carrying it in system-path.
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  # nixpkgs 26.05 removed the programs.adb module (see nixpkgs rename.nix);
  # systemd 258 uaccess rules grant Android device access automatically.
  # Extras (adbfs-rootless, adbtuifm) stay in devShells.android.

  # Create adbusers group
  users.groups.adbusers = { };

  # Add the primary user to 'adbusers' only when this module is imported.
  users.users."${config.users.main.name}".extraGroups = lib.mkAfter [ "adbusers" ];
  environment.systemPackages = [
    # Device access itself comes from the adbusers group + systemd 258 uaccess
    # rules, so only the CLI is on demand.
    (onDemand {
      name = "adb";
      attr = "android-tools";
      aliases = [ "fastboot" ];
    }) # adb/fastboot, built on first use
  ];
}
