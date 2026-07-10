{
  pkgs,
  lib,
  config,
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
    # Console forwarding is now handled by modules/system/log-ttys.nix (8 per-category TTY viewers)
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

  # Verbose boot logging for crash diagnostics (only when quietBoot is disabled)
  boot.kernelParams = lib.mkIf (!config.profiles.performance.quietBoot or false) [
    # Show systemd unit status on console during boot
    "systemd.show_status=true"
    # Increase systemd's internal log level for debug info
    "systemd.log_level=info"
  ];

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

      # Emergency debug shell on tty9 (Ctrl+Alt+F9) — enabled as early as possible
      "debug-shell".enable = true;
    };
    packages = [ pkgs.packagekit ]; # System to facilitate installing and updating packages
    timers.nixindex.enable = lib.mkForce false;
  };
}
