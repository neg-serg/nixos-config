{
  pkgs,
  lib,
  ...
}: let
  here = ./.;
  entries = builtins.readDir here;
  importables =
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
        then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix")
        then path
        else null
    )
    entries;
  imports = lib.filter (p: p != null) importables;
in {
  inherit imports;

  # Journald: keep logs across reboots to inspect boot output
  services.journald.extraConfig = ''
    Storage=persistent
    # Limit log write bursts to reduce IO spikes
    RateLimitIntervalSec=30s
    RateLimitBurst=2000
    # Keep total journal size reasonable
    SystemMaxFileSize=300M
    SystemMaxFiles=50
  '';

  services.logind.settings.Login = {
    IdleAction = "ignore";
  };

  systemd = {
    coredump.enable = true;
    settings = {
      Manager = {
        RebootWatchdogSec = "10s";
      };
    };
    # Favor user responsiveness; de-prioritize nix-daemon slightly
    slices."user.slice".sliceConfig = {
      CPUWeight = 10000;
      IOWeight = 10000;
    };
    services.nix-daemon.serviceConfig = {
      CPUWeight = 200;
      IOWeight = 200;
    };
    packages = [pkgs.packagekit];
  };
}
