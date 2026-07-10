{ config, pkgs, lib, ... }:

let
  inherit (lib) mkForce;

  # All packages that provide D-Bus configuration/service files
  dbusPkgs = config.services.dbus.packages;

  # Consolidate all D-Bus directories into a single Nix store path.
  # Instead of 18 servicedirs + 36 includedirs (54 directory scans!),
  # we generate one flat directory with symlinks to the original files.
  # dbus-broker then needs only 1 servicedir + 2 includedirs.
  consolidated = pkgs.runCommand "dbus-consolidated"
    {
      nativeBuildInputs = [ pkgs.coreutils ];
      # Keep GC alive references to all source packages
      inherit dbusPkgs;
    }
    ''
      shopt -s nullglob

      # Create all standard dbus-1 subdirectories
      for sub in \
        etc/dbus-1/system.d \
        etc/dbus-1/session.d \
        share/dbus-1/system.d \
        share/dbus-1/session.d \
        share/dbus-1/system-services \
        share/dbus-1/services
      do
        mkdir -p "$out/$sub"
      done

      # Merge policy files (*.conf) from system.d and session.d
      for dirset in \
        "etc/dbus-1/system.d:*.conf" \
        "share/dbus-1/system.d:*.conf" \
        "share/dbus-1/session.d:*.conf"
      do
        subdir="''${dirset%%:*}"
        pattern="''${dirset##*:}"
        for pkg in $dbusPkgs; do
          srcdir="$pkg/$subdir"
          if [ -d "$srcdir" ]; then
            for f in "$srcdir"/$pattern; do
              [ -f "$f" ] && ln -sfn "$f" "$out/$subdir/$(basename "$f")"
            done
          fi
        done
      done

      # Merge activation files (*.service) from system-services and services
      for dirset in \
        "share/dbus-1/system-services:*" \
        "share/dbus-1/services:*"
      do
        subdir="''${dirset%%:*}"
        for pkg in $dbusPkgs; do
          srcdir="$pkg/$subdir"
          if [ -d "$srcdir" ]; then
            for f in "$srcdir"/*; do
              [ -f "$f" ] && ln -sfn "$f" "$out/$subdir/$(basename "$f")"
            done
          fi
        done
      done
    '';

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
