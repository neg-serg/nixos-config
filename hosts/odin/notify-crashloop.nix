{
  lib,
  config,
  pkgs,
  ...
}:
let
  systemdUser = import ../../lib/systemd-user.nix { inherit lib; };

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
  config = lib.mkIf config.odin.telegram.enable (
    systemdUser.mkOneshotTimer {
      name = "telegram-crashloop-scan";
      description = "Scan for crash-looping systemd services and alert on Telegram";
      timerDescription = "Run the crash-loop Telegram scanner every 5 minutes";
      script = "${pkgs.python3}/bin/python3 ${crashLoopScript}";
      onCalendar = "*-*-* *:0/5:00";
      restartSec = 10;
      # Root owns the per-unit restart state snapshot.
      stateDirectory = "telegram-crashloop";
    }
  );
}
