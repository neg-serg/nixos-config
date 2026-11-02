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
  # Rust scanner (pkgs.neg.telegram-notify); it takes the sender, the user
  # manager and the optional BBS mirror from the environment, so the wrapper
  # below carries what the old build-time substitution used to bake in.
  crashLoopScript = pkgs.writeShellScript "telegram-crashloop-scan" ''
    export CRASHLOOP_SENDER=${lib.getExe config.trantor.telegram.sender}
    # The scanner is a system service (root), so the user scope needs the
    # target manager spelled out (`systemctl --user --machine neg@.host`).
    export CRASHLOOP_USER_MANAGER=${config.lib.neg.mainUser}@.host
    # Local BBS mirror; empty when servicesProfiles.minibbs is off.
    export CRASHLOOP_MINIBBS=${
      let
        post = config.servicesProfiles.minibbs.postCommand or null;
      in
      if post == null then "" else lib.getExe post
    }
    exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-crashloop"} "$@"
  '';
in
{
  # Telegram crash-loop scanner for systemd services. Gated on
  # config.trantor.telegram.enable (see hosts/trantor/telegram.nix).
  config = lib.mkIf config.trantor.telegram.enable (
    systemdUser.mkOneshotTimer {
      name = "telegram-crashloop-scan";
      description = "Scan for crash-looping systemd services and alert on Telegram";
      timerDescription = "Run the crash-loop Telegram scanner every 5 minutes";
      script = "${crashLoopScript}";
      onCalendar = "*-*-* *:0/5:00";
      restartSec = 10;
      # Root owns the per-unit restart state snapshot.
      stateDirectory = "telegram-crashloop";
    }
  );
}
