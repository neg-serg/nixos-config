{
  pkgs,
  lib,
  ...
}:
let
  imports = [
    ./post-boot.nix
    ./timesyncd
  ];
in
{
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

  # Replace ad-hoc nixindex units with native module

  systemd = {
    coredump.enable = true;
    settings = {
      Manager = {
        RebootWatchdogSec = "10s";
      };
    };
    services = {
      nix-daemon.serviceConfig = {
        CPUWeight = 200;
        IOWeight = 200;
        LimitNOFILE = 1048576;
      };

      # Silence failing ad-hoc nixindex timer/service; prefer proper modules
      nixindex.enable = lib.mkForce false;
    };
    packages = [ pkgs.packagekit ]; # System to facilitate installing and updating packages
    timers.nixindex.enable = lib.mkForce false;
  };
}
