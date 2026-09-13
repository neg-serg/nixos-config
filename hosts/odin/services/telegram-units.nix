{
  lib,
  config,
  pkgs,
  ...
}:
let
  # Alertmanager Telegram webhook bridge: HTTPServer on 127.0.0.1:9094 that
  # forwards every Alertmanager webhook notification to a Telegram chat.
  # Restored as a system service from git history
  # (fe1a52307^:modules/user/nix-maid/sys/user-services.nix).
  telegramBridgeScript = pkgs.writeShellApplication {
    name = "telegram-alert-bridge";
    runtimeInputs = [
      pkgs.python3
      pkgs.curl
    ]; # curl: Telegram API is only reachable via the sing-box socks proxy
    text = builtins.readFile (
      pkgs.replaceVars ./telegram/bridge.sh {
        botTokenPath = config.odin.telegram.botTokenPath;
        chatIdPath = config.odin.telegram.chatIdPath;
      }
    );

  };

  # Sends the "odin booted" notice exactly once per real boot. The unit is
  # wanted by multi-user.target, and nixos-rebuild switch re-runs it every
  # time, so a marker in /run (tmpfs, cleared on reboot) guards the send.
  telegramBootNotifyScript = pkgs.writeShellApplication {
    name = "telegram-notify-boot";
    runtimeInputs = [ pkgs.coreutils ]; # test/touch of the /run marker
    text = ''
      set -euo pipefail

      MARKER="/run/telegram-notify-boot.sent"
      [ -e "$MARKER" ] && exit 0

      ${lib.getExe config.odin.telegram.sender} "odin: загрузился"
      touch "$MARKER"
    '';
  };

  # Notifies Telegram on the down->up edge of the dockur Windows VM ("таз"):
  # probes RDP (127.0.0.1:3389) twice 5s apart; when the VM accepts
  # connections and no notification was recorded yet, sends one and marks it.
  # A failed probe clears the marker so the next VM boot re-notifies.
  windowsReadyCheckScript = pkgs.writeShellApplication {
    name = "telegram-notify-windows-ready";
    runtimeInputs = [ pkgs.coreutils ]; # rm/touch of the state marker
    text = builtins.readFile (
      pkgs.replaceVars ./telegram/windows-ready.sh {
        sender = lib.getExe config.odin.telegram.sender;
      }
    );

  };

  # Quickshell PillTracker state files (user neg): the panel pill capsule
  # writes this state and the calendar event; the Telegram reminder and
  # pill bot mirror marks in both directions (panel <-> chat).
  pillPanelStateFile = "/home/neg/.local/state/quickshell/pill-tracker.json";
  pillPanelIcsDir = "/home/neg/.config/vdirsyncer/calendars/pills";
  pillPanelUser = "neg";

  # Daily 12:00 pill reminder: sends a Telegram message with an inline
  # "Отметить" button; telegram-pill-bot turns a press into confirmation.
  # The message is skipped when the panel already recorded today's dose,
  # and its id is remembered so the bot can edit the very same message
  # when the dose gets marked (or unmarked) from the panel.
  pillReminderScript = pkgs.replaceVars ./telegram/telegram-pill-reminder.py {
    panelStateFile = pillPanelStateFile;
    botTokenPath = config.odin.telegram.botTokenPath;
    chatIdPath = config.odin.telegram.chatIdPath;
  };

  # Pill bot: long-polls getUpdates and turns presses of the "pill_taken"
  # button into a confirmation edit plus a dated line in the state log.
  # It is also the panel <-> Telegram bridge: a Telegram press marks the
  # Quickshell PillTracker (capsule + vdirsyncer calendar event), and a
  # panel-side mark/unmark edits the same Telegram reminder message, so
  # the pill can be confirmed from either source.
  pillBotScript = pkgs.replaceVars ./telegram/telegram-pill-bot.py {
    botTokenPath = config.odin.telegram.botTokenPath;
    chatIdPath = config.odin.telegram.chatIdPath;
    panelStateFile = pillPanelStateFile;
    panelIcsDir = pillPanelIcsDir;
    panelUser = pillPanelUser;
  };

  # Telegram alert scanner: python script run by a systemd timer every minute.
  # Posts into Alertmanager (wire format: array of
  # {labels: {alertname, severity}, annotations: {summary}, startsAt}):
  #   1. newly failed systemd units (diff against a persisted snapshot);
  #   2. OOM kills from the kernel journal (forward-only journal cursor);
  #   3. sshd brute-force attempts (>3 per scan window -> one alert).
  telegramAlertScannerScript = ./telegram/telegram-alert-scanner.py;
in
{
  config = lib.mkIf config.odin.telegram.enable {
    monitoring.alertmanager.enable = true;

    systemd.services."telegram-alert-bridge" = {
      description = "Alertmanager Telegram webhook bridge";
      documentation = [
        "https://prometheus.io/docs/alerting/latest/configuration/#webhook_config"
      ];
      after = [
        "network-online.target"
        "alertmanager.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe telegramBridgeScript}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    systemd.services."telegram-alert-scanner" = {
      description = "Scan failed units, OOM kills and sshd brute-force attempts into Alertmanager";
      after = [ "alertmanager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${telegramAlertScannerScript}";
        Restart = "on-failure";
        RestartSec = 10;
        # Journal access requires root; StateDirectory keeps the
        # snapshot/cursor files under /var/lib/telegram-alert-scanner.
        StateDirectory = "telegram-alert-scanner";
      };
    };

    systemd.timers."telegram-alert-scanner" = {
      description = "Run the Telegram alert scanner every minute";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:*:00";
        Unit = "telegram-alert-scanner.service";
      };
    };

    # Telegram "odin booted" notice. The socks proxy is a user unit that
    # starts at login, so keep retrying for a while after network is up.
    # The /run marker (see telegramBootNotifyScript) makes it fire once per
    # real boot instead of on every nixos-rebuild switch.
    systemd.services."telegram-notify-boot" = {
      description = "Send a Telegram message that odin has booted";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe telegramBootNotifyScript}";
        Restart = "on-failure";
        RestartSec = 300;
      };
    };

    # Telegram "taz is up" notice for the dockur Windows VM (started by
    # hand, so poll RDP instead of depending on a container unit).
    systemd.services."telegram-notify-windows-ready" = {
      description = "Send a Telegram message when the dockur Windows VM accepts RDP";
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "telegram-notify";
        ExecStart = "${lib.getExe windowsReadyCheckScript}";
      };
    };

    systemd.timers."telegram-notify-windows-ready" = {
      description = "Poll the dockur Windows VM RDP port and notify on boot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "60";
        OnUnitActiveSec = "30";
        Unit = "telegram-notify-windows-ready.service";
      };
    };

    # Telegram pill reminder: daily at 12:00 with a confirm button that
    # telegram-pill-bot turns into a "taken" confirmation.
    systemd.services."telegram-pill-reminder" = {
      description = "Send the daily 12:00 pill reminder to Telegram";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "telegram-pill-reminder";
        ExecStart = "${pkgs.python3}/bin/python3 ${pillReminderScript}";
      };
    };

    # No Persistent=true: on this VM snapshot restores / boot catch-ups made
    # systemd re-send "catch-up" reminders at ~midnight, doubling the daily
    # message. The script itself also guards "at most one send per day".
    systemd.timers."telegram-pill-reminder" = {
      description = "Daily 12:00 pill reminder";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 12:00:00";
        Unit = "telegram-pill-reminder.service";
      };
    };

    # Telegram pill bot: long-polls callback queries for the reminder button.
    systemd.services."telegram-pill-bot" = {
      description = "Telegram pill confirm button handler";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${pillBotScript}";
        Restart = "always";
        RestartSec = 5;
        StateDirectory = "telegram-pill-bot";
      };
    };
  };
}
