{
  lib,
  config,
  pkgs,
  ...
}:
let
  # Crash-loop scanner: every 5 minutes walks running services, finds units
  # that auto-restart (Restart=always/on-failure/on-abnormal) and whose
  # NRestarts counter jumped by >= CRASH_THRESHOLD since the previous run,
  # then posts one Telegram alert per affected unit with a per-unit cooldown
  # so it can never spam. Delivery goes through the shared sender in
  # hosts/odin/telegram.nix (socks-proxy retry lives there).
  crashLoopScript = pkgs.replaceVars ./notify/telegram-crashloop.py {
    sender = config.odin.telegram.sender;
  };
in
{
  # Telegram crash-loop scanner for systemd services. Gated on
  # config.odin.telegram.enable (see hosts/odin/telegram.nix).
  config = lib.mkIf config.odin.telegram.enable {
    systemd.services."telegram-crashloop-scan" = {
      description = "Scan for crash-looping systemd services and alert on Telegram";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${crashLoopScript}";
        # Root owns the per-unit restart state snapshot.
        StateDirectory = "telegram-crashloop";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    # No Persistent=true (same convention as the pill reminder): a late boot
    # catch-up must not fire stale scans / repeated alerts.
    systemd.timers."telegram-crashloop-scan" = {
      description = "Run the crash-loop Telegram scanner every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:0/5:00";
        Unit = "telegram-crashloop-scan.service";
      };
    };
  };
}
