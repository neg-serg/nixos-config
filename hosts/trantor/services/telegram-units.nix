{
  lib,
  neg,
  config,
  pkgs,
  ...
}:
let
  systemdUser = neg.systemdUser lib;

  # Alertmanager Telegram webhook bridge: an HTTP server on 127.0.0.1:9094 that
  # forwards every Alertmanager webhook notification to the Telegram chat, one
  # emoji-prefixed line per alert. Rust (pkgs.neg.telegram-notify); the two
  # secret paths come from the environment the wrapper exports, and are re-read
  # per request so a chat-id change needs no restart.
  telegramBridgeScript = pkgs.writeShellScript "telegram-alert-bridge" ''
    export BRIDGE_TOKEN_PATH=${config.trantor.telegram.botTokenPath}
    export BRIDGE_CHAT_ID_PATH=${config.trantor.telegram.chatIdPath}
    exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-alert-bridge"} "$@"
  '';

  # Sends the "trantor booted" notice exactly once per real boot. The unit is
  # wanted by multi-user.target, and nixos-rebuild switch re-runs it every
  # time, so a marker in /run (tmpfs, cleared on reboot) guards the send.
  telegramBootNotifyScript = pkgs.writeShellApplication {
    name = "telegram-notify-boot";
    runtimeInputs = [ pkgs.coreutils ]; # test/touch of the /run marker
    text = ''
      set -euo pipefail

      MARKER="/run/telegram-notify-boot.sent"
      [ -e "$MARKER" ] && exit 0

      ${lib.getExe config.trantor.telegram.sender} "🚀 trantor: booted"
      touch "$MARKER"
    '';
  };

  # Pleamar pill panel state (user neg): the panel pill capsule writes this
  # state and the calendar event; the Telegram reminder and pill bot mirror
  # marks in both directions (panel <-> chat).
  #
  # The state used to live under ~/.local/state/quickshell/ (the Quickshell
  # service's own directory). It moved with the shell's name; both scripts
  # below fall back to the legacy file while the new one does not exist yet, so
  # a mark recorded before the rename is not lost on the first boot.
  pillPanelStateFile = "/home/neg/.local/state/pleamar/pill-tracker.json";
  pillPanelStateDir = "/home/neg/.local/state/pleamar";
  pillPanelLegacyStateFile = "/home/neg/.local/state/quickshell/pill-tracker.json";
  pillPanelIcsDir = "/home/neg/.config/vdirsyncer/calendars/pills";
  pillPanelUser = "neg";

  # Daily 12:00 pill reminder: sends a Telegram message with an inline
  # "Mark taken" button; telegram-pill-bot turns a press into confirmation.
  # The message is skipped when the panel already recorded today's dose,
  # and its id is remembered so the bot can edit the very same message
  # when the dose gets marked (or unmarked) from the panel.
  # Rust reminder (pkgs.neg.telegram-notify); the paths it needs — the panel
  # state, the two decrypted secrets and its own state dir — come from the
  # environment the wrapper exports, so the binary carries no substitution.
  pillReminderScript = pkgs.writeShellScript "telegram-pill-reminder" ''
    export PILL_PANEL_STATE=${pillPanelStateFile}
    export PILL_PANEL_LEGACY_STATE=${pillPanelLegacyStateFile}
    export PILL_BOT_TOKEN_PATH=${config.trantor.telegram.botTokenPath}
    export PILL_CHAT_ID_PATH=${config.trantor.telegram.chatIdPath}
    export PILL_STATE_DIR=/var/lib/telegram-pill-reminder
    exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-pill-reminder"} "$@"
  '';

  # Pill bot: long-polls getUpdates and turns presses of the "pill_taken"
  # button into a confirmation edit plus a dated line in the state log.
  # It is also the panel <-> Telegram bridge: a Telegram press marks the
  # panel's pill state (capsule + vdirsyncer calendar event), and a
  # panel-side mark/unmark edits the same Telegram reminder message, so
  # the pill can be confirmed from either source.
  # Rust bridge (pkgs.neg.telegram-notify): it takes the two secrets, the panel
  # paths and the owning user from the environment, which the wrapper exports.
  pillBotScript = pkgs.writeShellScript "telegram-pill-bot" ''
    export PILL_BOT_TOKEN_PATH=${config.trantor.telegram.botTokenPath}
    export PILL_BOT_CHAT_ID_PATH=${config.trantor.telegram.chatIdPath}
    export PILL_BOT_PANEL_STATE=${pillPanelStateFile}
    export PILL_BOT_PANEL_STATE_LEGACY=${pillPanelLegacyStateFile}
    export PILL_BOT_ICS_DIR=${pillPanelIcsDir}
    export PILL_BOT_OWNER=${pillPanelUser}
    export PILL_BOT_STATE_DIR=/var/lib/telegram-pill-bot
    export PILL_BOT_LAST_MESSAGE=/var/lib/telegram-pill-reminder/last-message.json
    exec ${lib.getExe' pkgs.neg.telegram-notify "telegram-pill-bot"} "$@"
  '';

  # Telegram alert scanner: Rust binary (pkgs.neg.telegram-notify) run by a
  # systemd timer every minute.
  # Posts into Alertmanager (wire format: array of
  # {labels: {alertname, severity}, annotations: {summary}, startsAt}):
  #   1. newly failed systemd units (diff against a persisted snapshot);
  #   2. OOM kills from the kernel journal (forward-only journal cursor);
  #   3. sshd brute-force attempts (>3 per scan window -> one alert).
  telegramAlertScannerScript = lib.getExe' pkgs.neg.telegram-notify "telegram-alert-scanner";

  # Sandbox the bridge and the pill bot share: both read the two SOPS secrets
  # (root, 0400 under /run/secrets), answer on loopback and shell out to curl.
  # The per-service blocks below add only what differs (ProtectHome, the
  # writable panel paths, the capability set).
  commonHardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectKernelTunables = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    RemoveIPC = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
      "AF_NETLINK"
    ];
    SystemCallFilter = [ "@system-service" ];
    SystemCallArchitectures = "native";
  };
in
{
  config = lib.mkIf config.trantor.telegram.enable (
    lib.mkMerge [
      { monitoring.alertmanager.enable = true; }

      (systemdUser.mkOneshotTimer {
        name = "telegram-alert-scanner";
        description = "Scan failed units, OOM kills and sshd brute-force attempts into Alertmanager";
        timerDescription = "Run the Telegram alert scanner every minute";
        script = telegramAlertScannerScript;
        onCalendar = "*-*-* *:*:00";
        networkOnline = false;
        after = [ "alertmanager.service" ];
        wantedBy = [ "multi-user.target" ];
        restartSec = 10;
        # Journal access requires root; keeps the snapshot/cursor files under
        # /var/lib/telegram-alert-scanner.
        stateDirectory = "telegram-alert-scanner";
      })

      # Telegram "trantor booted" notice. The socks proxy is a user unit that
      # starts at login, so keep retrying for a while after network is up.
      # The /run marker (see telegramBootNotifyScript) makes it fire once per
      # real boot instead of on every nixos-rebuild switch.
      #
      # Deliberately NOT wantedBy multi-user.target: the sender blocks until the
      # user-session socks proxy (127.0.0.1:10808) answers, which cannot happen
      # before login. As a target dependency it held multi-user.target (and thus
      # graphical.target) for 20-45s on every boot (journal 2026-09-16:
      # "Started" ~8.5s, multi-user reached only at 33.7s). The timer fires it
      # off the boot critical path; the sender's own retry loop (12 x 5s) covers
      # the proxy coming up after login.
      (systemdUser.mkOneshotTimer {
        name = "telegram-notify-boot";
        description = "Send a Telegram message that trantor has booted";
        timerDescription = "Fire the boot notice shortly after boot, off the boot critical path";
        script = lib.getExe telegramBootNotifyScript;
        onBootSec = "20s";
        restartSec = 300;
      })

      # Telegram pill reminder: daily at 12:00 with a confirm button that
      # telegram-pill-bot turns into a "taken" confirmation. The script itself
      # guards "at most one send per day".
      (systemdUser.mkOneshotTimer {
        name = "telegram-pill-reminder";
        description = "Send the daily 12:00 pill reminder to Telegram";
        timerDescription = "Daily 12:00 pill reminder";
        script = "${pillReminderScript}";
        onCalendar = "*-*-* 12:00:00";
        restart = null;
        stateDirectory = "telegram-pill-reminder";
      })

      {
        # The panel state directory the pill bot writes as root: the panel owns
        # the file, the directory itself is declared here so the bot has
        # somewhere to create it (it does not exist on a fresh session).
        systemd.tmpfiles.rules = [
          "d ${pillPanelStateDir} 0755 ${pillPanelUser} ${pillPanelUser} - -"
        ];

        systemd.services."telegram-alert-bridge" = systemdUser.mkSystemService {
          description = "Alertmanager Telegram webhook bridge";
          documentation = [
            "https://prometheus.io/docs/alerting/latest/configuration/#webhook_config"
          ];
          presets = [ "restartOnFailure" ];
          after = [
            "network-online.target"
            "alertmanager.service"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          # The bridge only reads the two SOPS secrets (root, 0400 under
          # /run/secrets), answers on 127.0.0.1:9094 and shells out to curl;
          # everything it writes goes to the journal. None of that needs a
          # capability or a writable path, so the sandbox can be this tight.
          serviceConfig = commonHardening // {
            ExecStart = "${telegramBridgeScript}";
            RestartSec = 5;
            ProtectHome = true;
            CapabilityBoundingSet = "";
            AmbientCapabilities = [ ];
          };
        };

        # Telegram pill bot: long-polls callback queries for the reminder button.
        systemd.services."telegram-pill-bot" = {
          description = "Telegram pill confirm button handler";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          # Same sandbox as the bridge, except that this one legitimately
          # writes into the panel: it rewrites the panel's pill state and
          # the vdirsyncer .ics (read-only home plus those two paths). It
          # runs as root and chown()s those files to neg, so the capability
          # set is left at systemd's default here — narrowing it is the next
          # step, once a real button press has been traced.
          serviceConfig = commonHardening // {
            ExecStart = "${pillBotScript}";
            Restart = "always";
            RestartSec = 5;
            StateDirectory = "telegram-pill-bot";
            ProtectHome = "read-only";
            # The state directory, not the file: on the first boot after the
            # rename the file does not exist yet and `-` would leave the whole
            # directory read-only, so the bot could not write its own state.
            ReadWritePaths = [
              "-${pillPanelStateDir}"
              "-${pillPanelIcsDir}"
            ];
          };
        };
      }
    ]
  );
}
