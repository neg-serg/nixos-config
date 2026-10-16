{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
let
  systemdUser = neg.systemdUser lib;

  # Crash-loop scanner: every 5 minutes walks running services in BOTH systemd
  # managers (system and the user manager — listenbrainz-mpd and friends),
  # finds units that auto-restart (Restart=always/on-failure/on-abnormal) and
  # whose NRestarts counter jumped by >= CRASH_THRESHOLD since the previous
  # run, then posts one Telegram alert per affected unit with a per-unit
  # cooldown so it can never spam. Delivery goes through the shared sender in
  # hosts/trantor/telegram.nix (socks-proxy retry lives there).
  crashLoopScript = pkgs.replaceVars ./notify/telegram-crashloop.py {
    sender = config.trantor.telegram.sender;
  };
in
{
  # Telegram crash-loop scanner for systemd services. Gated on
  # config.trantor.telegram.enable (see hosts/trantor/telegram.nix).
  config = lib.mkIf config.trantor.telegram.enable (
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
