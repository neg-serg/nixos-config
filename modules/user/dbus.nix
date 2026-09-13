{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkForce;

  # All packages that provide D-Bus configuration/service files
  dbusPkgs = config.services.dbus.packages;

  # Consolidate all D-Bus directories into a single Nix store path.
  # Instead of 18 servicedirs + 36 includedirs (54 directory scans!),
  # we generate one flat directory with symlinks to the original files.
  # dbus-broker then needs only 1 servicedir + 2 includedirs.
  consolidated = pkgs.runCommand "dbus-consolidated" {
    nativeBuildInputs = [ pkgs.coreutils ];
    # Keep GC alive references to all source packages
    inherit dbusPkgs;
  } (builtins.readFile ./dbus/consolidate.sh);

  # Custom D-Bus config pointing only to the consolidated directory
  customConfigDir = pkgs.makeDBusConf.override {
    inherit (config.services.dbus) apparmor;
    dbus = config.services.dbus.dbusPackage;
    suidHelper = "${config.security.wrapperDir}/dbus-daemon-launch-helper";
    serviceDirectories = [ consolidated ];
  };
in
{
  services.dbus = {
    enable = true;
    implementation = "broker";
    apparmor = "enabled";
  };

  # Override the D-Bus config to use consolidated directories.
  # mkForce because the NixOS dbus module already sets this.
  environment.etc."dbus-1".source = mkForce customConfigDir;
}
