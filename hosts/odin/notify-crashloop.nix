{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  # Crash-loop scanner: every 5 minutes walks running services, finds units
  # that auto-restart (Restart=always/on-failure/on-abnormal) and whose
  # NRestarts counter jumped by >= CRASH_THRESHOLD since the previous run,
  # then posts one Telegram alert per affected unit with a per-unit cooldown
  # so it can never spam. api.telegram.org is only reachable through the user
  # sing-box socks proxy (127.0.0.1:10808), which starts at login, so a send
  # retries 5s x SEND_ATTEMPTS (matches the telegramSendScript convention).
  crashLoopScript = pkgs.writeText "telegram-crashloop.py" ''
    import json
    import pathlib
    import subprocess
    import sys
    import time

    STATE_DIR = pathlib.Path("/var/lib/telegram-crashloop")
    STATE_FILE = STATE_DIR / "state.json"
    TOKEN_FILE = "${config.sops.secrets."telegram/bot-token".path}"
    CHAT_ID_FILE = "${config.sops.secrets."telegram/chat-id".path}"
    CURL = "/run/current-system/sw/bin/curl"
    PROXY = "socks5h://127.0.0.1:10808"
    API = "https://api.telegram.org/bot{0}/sendMessage"

    # A unit is deemed to be crash-looping when NRestarts grew by at least
    # this many within one ~5 min scan window, which is well above any
    # expected single blip (RestartSec below 5s => up to ~60 restarts/5min).
    CRASH_THRESHOLD = 6
    # Do not re-alert the same unit more than once per hour.
    COOLDOWN_SECONDS = 60 * 60
    SEND_ATTEMPTS = 12

    # Focus only on units systemd is configured to auto-restart: a unit with
    # Restart=no can never accumulate NRestarts while crash-looping.
    AUTO_RESTART = {"always", "on-failure", "on-abnormal", "on-abort", "on-success"}


    def running_units():
        # First column of `systemctl list-units --type=service` is the unit name.
        proc = subprocess.run(
            [
                "/run/current-system/sw/bin/systemctl",
                "list-units",
                "--type=service",
                "--state=running",
                "--no-legend",
                "--plain",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        names = []
        for line in (proc.stdout or "").splitlines():
            col = line.split(None, 1)
            if col:
                names.append(col[0])
        return names


    def restart_state(unit):
        # Returns (restart_policy, nrestarts) or (None, None) if unreadable.
        proc = subprocess.run(
            [
                "/run/current-system/sw/bin/systemctl",
                "show",
                unit,
                "-p",
                "Restart",
                "-p",
                "NRestarts",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        policy = None
        nrestarts = None
        for line in (proc.stdout or "").splitlines():
            if line.startswith("Restart="):
                policy = line.split("=", 1)[1]
            elif line.startswith("NRestarts="):
                try:
                    nrestarts = int(line.split("=", 1)[1])
                except ValueError:
                    nrestarts = None
        return policy, nrestarts


    def load_state():
        try:
            with open(STATE_FILE, "r") as fh:
                return json.load(fh)
        except (FileNotFoundError, ValueError):
            return {}


    def send_alert(text):
        # Retry loop 5s x SEND_ATTEMPTS through the socks proxy. Returns True
        # only on an actual successful delivery.
        try:
            token = open(TOKEN_FILE).read().strip()
            chat_id = open(CHAT_ID_FILE).read().strip()
        except OSError as exc:
            print("crashloop: cannot read telegram secrets: {0}".format(exc), file=sys.stderr)
            return False
        for _ in range(SEND_ATTEMPTS):
            try:
                proc = subprocess.run(
                    [
                        CURL,
                        "-s",
                        "-o",
                        "/dev/null",
                        "--proxy",
                        PROXY,
                        "--data-urlencode",
                        "chat_id={0}".format(chat_id),
                        "--data-urlencode",
                        "text={0}".format(text),
                        API.format(token),
                    ],
                    check=False,
                )
            except OSError as exc:
                print("crashloop: curl error: {0}".format(exc), file=sys.stderr)
                return False
            if proc.returncode == 0:
                return True
            time.sleep(5)
        print("crashloop: could not deliver alert after {0} attempts".format(SEND_ATTEMPTS), file=sys.stderr)
        return False


    def main():
        now = time.time()
        state = load_state()
        units = state.setdefault("units", {})
        changed = False
        alerted = []

        for unit in running_units():
            policy, nrestarts = restart_state(unit)
            if policy not in AUTO_RESTART or nrestarts is None:
                continue

            entry = units.get(unit)
            if entry is None:
                # First observation: just baseline it, never alert on the very
                # first sight of an already-restarted unit.
                units[unit] = {"last": nrestarts, "next_allowed": 0}
                changed = True
                continue

            last = entry.get("last", 0)
            # Counter reset (unit stopped/reloaded/rebooted => NRestarts 0):
            # adopt the lower value as the new baseline, no alert, so real
            # restarts are never missed across a reset.
            if nrestarts <= last:
                if nrestarts != last:
                    entry["last"] = nrestarts
                    changed = True
                continue

            delta = nrestarts - last
            if delta >= CRASH_THRESHOLD and now >= entry.get("next_allowed", 0):
                text = "🔄 crash-loop: {0}: {1} рестартов за 5 мин (всего {2})".format(
                    unit, delta, nrestarts
                )
                print("crashloop: alert {0}".format(text))
                if send_alert(text):
                    # Successful send arms the per-unit cooldown and resets the
                    # baseline so we never re-alert this burst again.
                    entry["next_allowed"] = now + COOLDOWN_SECONDS
                    entry["last"] = nrestarts
                    alerted.append(unit)
                    changed = True
                else:
                    # Delivery failed: keep the old baseline so the next run
                    # retries the alert; never mark it as handled.
                    print("crashloop: send failed for {0}, will retry next scan".format(unit), file=sys.stderr)
            else:
                # Either below threshold or still inside the cooldown window.
                # Adopt the new counter so a sustained crash-loop re-alerts
                # (with a fresh delta) once the cooldown expires, but never
                # accumulates into a giant stale number.
                entry["last"] = nrestarts
                changed = True

        if alerted:
            changed = True

        if changed:
            # Writes are atomic: crash mid-write cannot corrupt the snapshot.
            tmp = STATE_FILE.with_suffix(".tmp")
            tmp.write_text(json.dumps(state, indent=2))
            tmp.rename(STATE_FILE)

        sys.exit(0)


    if __name__ == "__main__":
        main()
  '';
in
{
  # Telegram crash-loop scanner for systemd services. Gated on the telegram
  # secret existing, exactly like the rest of the telegram stack in services.nix.
  config = lib.mkIf (builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml")) {
    sops.secrets."telegram/bot-token" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "bot-token";
      owner = "root";
      mode = "0400";
    };
    sops.secrets."telegram/chat-id" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "chat-id";
      owner = "root";
      mode = "0400";
    };

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
