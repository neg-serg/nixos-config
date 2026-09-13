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
    text = ''
            set -euo pipefail

            TELEGRAM_BOT_TOKEN_FILE="${config.odin.telegram.botTokenPath}"
            TELEGRAM_CHAT_ID_FILE="${config.odin.telegram.chatIdPath}"
            # Re-read the secrets on every request so a chat-id change takes
            # effect without restarting the bridge.
            export TELEGRAM_BOT_TOKEN_FILE TELEGRAM_CHAT_ID_FILE

            exec python3 -c '
      import json
      import os
      from http.server import BaseHTTPRequestHandler, HTTPServer
      import subprocess

      def creds():
          token = open(os.environ["TELEGRAM_BOT_TOKEN_FILE"]).read().strip()
          chat_id = open(os.environ["TELEGRAM_CHAT_ID_FILE"]).read().strip()
          return token, chat_id


      class Handler(BaseHTTPRequestHandler):
          def do_POST(self):
              length = int(self.headers.get("Content-Length", 0))
              data = json.loads(self.rfile.read(length))
              for alert in data.get("alerts", []):
                  status = str(alert.get("status", "UNKNOWN")).upper()
                  labels = alert.get("labels", {})
                  annotations = alert.get("annotations", {})
                  name = labels.get("alertname", "Unknown")
                  severity = labels.get("severity", "unknown")
                  summary = annotations.get("summary", "No summary")
                  msg = "[{0}] [{1}] {2}: {3}".format(status, severity, name, summary)
                  token, chat_id = creds()
                  api_url = "https://api.telegram.org/bot{0}/sendMessage".format(token)
                  # api.telegram.org is unreachable from this host without the
                  # sing-box socks proxy (socks5h://127.0.0.1:10808).
                  subprocess.run(
                      [
                          "/run/current-system/sw/bin/curl",
                          "-s", "-o", "/dev/null",
                          "--proxy", "socks5h://127.0.0.1:10808",
                          "--data-urlencode", "chat_id={0}".format(chat_id),
                          "--data-urlencode", "text={0}".format(msg),
                          api_url,
                      ],
                      check=False,
                  )
              self.send_response(200)
              self.end_headers()
              self.wfile.write(b"OK")

          def log_message(self, format, *args):
              pass


      HTTPServer(("127.0.0.1", 9094), Handler).serve_forever()
      '
    '';
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
    text = ''
      set -euo pipefail

      STATE_FILE="/var/lib/telegram-notify/windows-ready.sent"

      ok=0
      for _ in 1 2; do
        if (exec 3<>/dev/tcp/127.0.0.1/3389) 2>/dev/null; then
          ok=1
        else
          ok=0
          break
        fi
        sleep 5
      done

      if [ "$ok" != 1 ]; then
        rm -f "$STATE_FILE"
        exit 0
      fi
      [ -e "$STATE_FILE" ] && exit 0

      ${lib.getExe config.odin.telegram.sender} "таз загрузился" "Windows-VM доступна по RDP (127.0.0.1:3389)"
      touch "$STATE_FILE"
    '';
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
  pillReminderScript = pkgs.writeText "telegram-pill-reminder.py" ''
    import json
    import pathlib
    import subprocess
    import sys
    import time

    # Shared with the Quickshell PillTracker (panel pill capsule).
    PANEL_STATE_FILE = pathlib.Path("${pillPanelStateFile}")

    # Idempotency guard: on this VM snapshot restores / late boot catch-ups can
    # fire the timer more than once a day. Stamp the date on every successful
    # send and skip if we already reminded today, so it is at most once/24h.
    STATE_DIR = pathlib.Path("/var/lib/telegram-pill-reminder")
    MARKER = STATE_DIR / "last-sent.txt"
    LAST_MSG_FILE = STATE_DIR / "last-message.json"
    TODAY = time.strftime("%Y-%m-%d")

    def already_taken_today():
        try:
            state = json.loads(PANEL_STATE_FILE.read_text())
        except (OSError, ValueError):
            return False
        return state.get("todayDate") == TODAY and bool(state.get("taken"))

    if already_taken_today():
        print("pill-reminder: pill already taken today, skipping")
        sys.exit(0)

    try:
        if MARKER.read_text().strip() == TODAY:
            print("pill-reminder: already sent today, skipping")
            sys.exit(0)
    except FileNotFoundError:
        pass

    TOKEN = open("${config.odin.telegram.botTokenPath}").read().strip()
    CHAT_ID = open("${config.odin.telegram.chatIdPath}").read().strip()
    CURL = "/run/current-system/sw/bin/curl"
    API = "https://api.telegram.org/bot{0}/sendMessage".format(TOKEN)
    MARKUP = json.dumps(
        {"inline_keyboard": [[{"text": "Отметить ✅", "callback_data": "pill_taken"}]]}
    )
    TEXT = "💊 12:00 — пора принять таблетку. Нажми «Отметить», когда принял."

    for attempt in range(12):
        proc = subprocess.run(
            [
                CURL,
                "-s",
                "--proxy",
                "socks5h://127.0.0.1:10808",
                "--data-urlencode",
                "chat_id={0}".format(CHAT_ID),
                "--data-urlencode",
                "text={0}".format(TEXT),
                "--data-urlencode",
                "reply_markup={0}".format(MARKUP),
                API,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            MARKER.parent.mkdir(parents=True, exist_ok=True)
            MARKER.write_text(TODAY)
            # Remember the sent message so a later panel-side "taken" can edit
            # the same message and keep panel and chat confirmations in sync.
            try:
                sent = json.loads(proc.stdout or "{}")
                message_id = sent.get("result", {}).get("message_id")
                if message_id:
                    LAST_MSG_FILE.write_text(
                        json.dumps(
                            {
                                "date": TODAY,
                                "chat_id": CHAT_ID,
                                "message_id": message_id,
                                "confirmed": False,
                            }
                        )
                    )
            except (OSError, ValueError):
                print("pill-reminder: could not record sent message id", file=sys.stderr)
            sys.exit(0)
        time.sleep(5)
    print("pill-reminder: could not deliver after 12 attempts", file=sys.stderr)
    sys.exit(1)
  '';

  # Pill bot: long-polls getUpdates and turns presses of the "pill_taken"
  # button into a confirmation edit plus a dated line in the state log.
  # It is also the panel <-> Telegram bridge: a Telegram press marks the
  # Quickshell PillTracker (capsule + vdirsyncer calendar event), and a
  # panel-side mark/unmark edits the same Telegram reminder message, so
  # the pill can be confirmed from either source.
  pillBotScript = pkgs.writeText "telegram-pill-bot.py" ''
    import json
    import os
    import pathlib
    import pwd
    import subprocess
    import sys
    import time

    TOKEN_FILE = "${config.odin.telegram.botTokenPath}"
    CHAT_ID_FILE = "${config.odin.telegram.chatIdPath}"
    CURL = "/run/current-system/sw/bin/curl"
    PROXY = "socks5h://127.0.0.1:10808"
    STATE_DIR = pathlib.Path("/var/lib/telegram-pill-bot")
    OFFSET_FILE = STATE_DIR / "offset"
    LOG_FILE = STATE_DIR / "pill-log.txt"
    LAST_MSG_FILE = pathlib.Path("/var/lib/telegram-pill-reminder/last-message.json")

    # Quickshell PillTracker files owned by the desktop user's panel.
    PANEL_STATE_FILE = pathlib.Path("${pillPanelStateFile}")
    PANEL_ICS_DIR = pathlib.Path("${pillPanelIcsDir}")
    PILL_OWNER = "${pillPanelUser}"

    # Must match telegram-pill-reminder.py: used to restore the reminder
    # message (with its button) when the panel mark is reverted.
    REMINDER_TEXT = "💊 12:00 — пора принять таблетку. Нажми «Отметить», когда принял."
    REMINDER_MARKUP = json.dumps(
        {"inline_keyboard": [[{"text": "Отметить ✅", "callback_data": "pill_taken"}]]}
    )
    CONFIRMED_TEXT = "💊 Принято ✅ ({0})"

    def read_secrets():
        token = open(TOKEN_FILE).read().strip()
        chat_id = open(CHAT_ID_FILE).read().strip()
        return token, chat_id

    def api_call(method, params, token):
        cmd = [CURL, "-s", "--proxy", PROXY, "--max-time", "70"]
        for key, value in params.items():
            cmd += ["--data-urlencode", "{0}={1}".format(key, value)]
        cmd.append("https://api.telegram.org/bot{0}/{1}".format(token, method))
        return subprocess.run(cmd, capture_output=True, text=True, check=False)

    def stamp_now():
        return time.strftime("%Y-%m-%d %H:%M %Z")

    def owner_ids():
        pw = pwd.getpwnam(PILL_OWNER)
        return pw.pw_uid, pw.pw_gid

    def read_panel_state():
        try:
            return json.loads(PANEL_STATE_FILE.read_text())
        except (OSError, ValueError):
            return {}

    def write_panel_state(state):
        uid, gid = owner_ids()
        PANEL_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        PANEL_STATE_FILE.write_text(json.dumps(state, indent=4) + "\n")
        os.chown(PANEL_STATE_FILE, uid, gid)
        os.chmod(PANEL_STATE_FILE, 0o644)

    def write_panel_ics(today, taken_at):
        uid, gid = owner_ids()
        PANEL_ICS_DIR.mkdir(parents=True, exist_ok=True)
        path = PANEL_ICS_DIR / ("pill-" + today + ".ics")
        dtstart = today.replace("-", "")
        ics = "\r\n".join([
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Neg//PillTracker//EN",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:" + dtstart,
            "DTEND;VALUE=DATE:" + dtstart,
            "SUMMARY:Pill \u2705",
            "DESCRIPTION:Taken at " + taken_at,
            "CATEGORIES:Health",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ])
        path.write_text(ics)
        os.chown(path, uid, gid)
        os.chmod(path, 0o644)
        # The collection dir may have been created above as root; hand it
        # back to the desktop user so vdirsyncer stays writable.
        st = os.stat(PANEL_ICS_DIR)
        if (st.st_uid, st.st_gid) != (uid, gid):
            os.chown(PANEL_ICS_DIR, uid, gid)

    def remove_panel_ics(today):
        (PANEL_ICS_DIR / ("pill-" + today + ".ics")).unlink(missing_ok=True)

    def mark_panel_taken(today, taken_at):
        state = read_panel_state()
        state["todayDate"] = today
        state["taken"] = True
        state["takenAt"] = taken_at
        if not isinstance(state.get("history"), list):
            state["history"] = []
        write_panel_state(state)
        write_panel_ics(today, taken_at)

    def last_message(today):
        try:
            data = json.loads(LAST_MSG_FILE.read_text())
        except (OSError, ValueError):
            return None
        if not isinstance(data, dict) or data.get("date") != today:
            return None
        data.setdefault("confirmed", False)
        return data

    def save_last_message(data):
        LAST_MSG_FILE.parent.mkdir(parents=True, exist_ok=True)
        LAST_MSG_FILE.write_text(json.dumps(data))

    def log_line(text):
        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with LOG_FILE.open("a") as fh:
            fh.write(text + "\n")

    def edit_message(msg, text, token, reply_markup=None):
        params = {
            "chat_id": str(msg["chat_id"]),
            "message_id": str(msg["message_id"]),
            "text": text,
        }
        if reply_markup is not None:
            params["reply_markup"] = reply_markup
        return api_call("editMessageText", params, token)

    def sync_from_panel(today, token):
        """Converge the day's Telegram reminder message on the panel state."""
        msg = last_message(today)
        if not msg:
            return
        state = read_panel_state()
        taken = state.get("todayDate") == today and bool(state.get("taken"))
        if msg.get("confirmed") == taken:
            return
        if taken:
            taken_at = state.get("takenAt") or time.strftime("%H:%M")
            resp = edit_message(msg, CONFIRMED_TEXT.format(today + " " + taken_at), token)
        else:
            resp = edit_message(msg, REMINDER_TEXT, token, REMINDER_MARKUP)
        if resp.returncode == 0:
            msg["confirmed"] = taken
            save_last_message(msg)
            if taken:
                log_line(stamp_now())

    offset = 0
    if OFFSET_FILE.exists():
        try:
            offset = int(OFFSET_FILE.read_text().strip())
        except ValueError:
            offset = 0

    while True:
        try:
            token, chat_id = read_secrets()
            today = time.strftime("%Y-%m-%d")

            # Bridge: panel-side marks edit the Telegram reminder message and
            # Telegram-side marks update the panel capsule/calendar. Converging
            # on the recorded confirmation also heals any half-applied state.
            sync_from_panel(today, token)

            resp = api_call(
                "getUpdates", {"offset": str(offset + 1), "timeout": "25"}, token
            )
            if resp.returncode != 0:
                time.sleep(5)
                continue
            data = json.loads(resp.stdout or "{}")
            if not data.get("ok"):
                time.sleep(5)
                continue
            for update in data.get("result", []):
                offset = max(offset, update.get("update_id", 0))
                callback = update.get("callback_query")
                message = update.get("message") or {}
                if not callback and message:
                    # Log who talks to the bot so the owner id can be captured.
                    sender = message.get("from", {})
                    chat = message.get("chat", {})
                    print(
                        "pill-bot: message from {0} in chat {1} (type {2})".format(
                            sender.get("id"), chat.get("id"), chat.get("type")
                        ),
                        file=sys.stderr,
                    )
                if not callback:
                    continue
                # Private-chat bot: only presses from the owner count. In a
                # 1:1 chat both chat.id and from.id equal the user id, which
                # is the chat id the reminders go to; ignore anything else.
                cb_message = callback.get("message", {})
                cb_chat = cb_message.get("chat", {})
                chat_id_n = cb_chat.get("id")
                from_id = callback.get("from", {}).get("id")
                if str(chat_id_n) != chat_id or str(from_id) != chat_id:
                    continue
                query_id = callback.get("id", "")
                data_field = callback.get("data", "")
                api_call(
                    "answerCallbackQuery",
                    {"callback_query_id": query_id},
                    token,
                )
                if data_field == "pill_taken":
                    message_id = cb_message.get("message_id")
                    if message_id:
                        taken_at = stamp_now()
                        # Record in the panel first: the capsule lights up and
                        # the day is marked in the vdirsyncer calendar. If the
                        # Telegram-side edit below fails, sync_from_panel heals
                        # it on the next pass.
                        mark_panel_taken(today, time.strftime("%H:%M"))
                        api_call(
                            "editMessageText",
                            {
                                "chat_id": chat_id_n,
                                "message_id": message_id,
                                "text": CONFIRMED_TEXT.format(taken_at),
                            },
                            token,
                        )
                        # Remember the message so later panel-side changes can
                        # edit it back (button restore on unmark).
                        msg = last_message(today)
                        if not msg:
                            msg = {
                                "date": today,
                                "chat_id": chat_id_n,
                                "message_id": message_id,
                            }
                        if msg.get("message_id") == message_id:
                            msg["confirmed"] = True
                            save_last_message(msg)
                        LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
                        with LOG_FILE.open("a") as fh:
                            fh.write(taken_at + "\n")
            OFFSET_FILE.write_text(str(offset))
        except Exception as exc:
            print("pill-bot: {0}".format(exc), file=sys.stderr)
            time.sleep(5)
  '';
  # Telegram alert scanner: python script run by a systemd timer every minute.
  # Posts into Alertmanager (wire format: array of
  # {labels: {alertname, severity}, annotations: {summary}, startsAt}):
  #   1. newly failed systemd units (diff against a persisted snapshot);
  #   2. OOM kills from the kernel journal (forward-only journal cursor);
  #   3. sshd brute-force attempts (>3 per scan window -> one alert).
  telegramAlertScannerScript = pkgs.writeText "telegram-alert-scanner.py" ''
    import datetime as dt
    import json
    import pathlib
    import re
    import subprocess
    import sys
    import urllib.error
    import urllib.request

    STATE_DIR = pathlib.Path("/var/lib/telegram-alert-scanner")
    FAILED_UNITS_FILE = STATE_DIR / "failed-units.json"
    OOM_CURSOR_FILE = STATE_DIR / "oom-journal-cursor"
    ALERTMANAGER_URL = "http://127.0.0.1:9093/api/v2/alerts" # v1 API removed in alertmanager 0.27+

    OOM_RE = re.compile(r"Out of memory: Killed process (\d+) \((\S+)\)")
    SSHD_FAIL_RE = re.compile(r"(Failed password|Invalid user)")
    SSH_FAIL_THRESHOLD = 3
    SSH_IP_RE = re.compile(r"\bfrom (\S+) port \d+")


    def now_iso():
        return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


    def run_cmd(args):
        try:
            proc = subprocess.run(args, capture_output=True, text=True, check=False)
            return proc.stdout or ""
        except OSError as exc:
            print("scanner: cannot run {}: {}".format(" ".join(args), exc), file=sys.stderr)
            return ""


    def post(alerts):
        if not alerts:
            return
        payload = json.dumps(alerts).encode("utf-8")
        req = urllib.request.Request(
            ALERTMANAGER_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                resp.read()
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
            # Alertmanager may be starting; never fail the whole scan over this.
            print("scanner: cannot deliver alerts: {}".format(exc), file=sys.stderr)


    def make_alert(alertname, severity, summary, **labels):
        return {
            "labels": dict({"alertname": alertname, "severity": severity}, **labels),
            "annotations": {"summary": summary},
            "startsAt": now_iso(),
        }


    def scan_failed_units():
        """Newly failed systemd units; the snapshot forgets recovered units."""
        out = run_cmd(
            [
                "/run/current-system/sw/bin/systemctl",
                "list-units",
                "--failed",
                "--no-legend",
                "--plain",
                "--no-pager",
            ]
        )
        failed = {line.split()[0] for line in out.splitlines() if line.split()}
        previous = set()
        if FAILED_UNITS_FILE.exists():
            try:
                previous = set(json.loads(FAILED_UNITS_FILE.read_text()))
            except (ValueError, OSError) as exc:
                print("scanner: bad failed-unit snapshot: {}".format(exc), file=sys.stderr)
        if failed != previous:
            try:
                FAILED_UNITS_FILE.write_text(json.dumps(sorted(failed)))
            except OSError as exc:
                print("scanner: cannot save failed-unit snapshot: {}".format(exc), file=sys.stderr)
        return [
            make_alert(
                "systemd-failed-unit", "error", "Systemd unit failed: {}".format(unit), unit=unit
            )
            for unit in sorted(failed - previous)
        ]


    def journal_cursor(cursor_file):
        if cursor_file.exists():
            return cursor_file.read_text().strip()
        return None


    def advance_journal_cursor(output, cursor_file):
        """Persist the trailing '-- cursor:' marker if journalctl printed one."""
        m = re.search(r"(?m)^-- cursor: (\S+)$", output)
        if m:
            try:
                cursor_file.write_text(m.group(1))
            except OSError as exc:
                print("scanner: cannot save journal cursor: {}".format(exc), file=sys.stderr)


    def seed_journal_cursor(cursor_file):
        if journal_cursor(cursor_file):
            return
        output = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "-n",
                "0",
                "--show-cursor",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        advance_journal_cursor(output, cursor_file)


    def scan_oom_kills():
        """One aggregate alert for every OOM kill seen since the last scan."""
        seed_journal_cursor(OOM_CURSOR_FILE)
        cursor = journal_cursor(OOM_CURSOR_FILE)
        if not cursor:
            return []
        output = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "--after-cursor=" + cursor,
                "--show-cursor",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        advance_journal_cursor(output, OOM_CURSOR_FILE)
        kills = []
        for line in output.splitlines():
            m = OOM_RE.search(line)
            if m:
                kills.append(m.group(2))
        if not kills:
            return []
        summary = "{} OOM kill(s): {}".format(len(kills), ", ".join(sorted(set(kills))[:10]))
        return [make_alert("oom-kill", "error", summary, count=str(len(kills)))]


    def scan_sshd_bruteforce():
        """One alert per window when more than the threshold of failed logins occurs."""
        out = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "-u",
                "sshd.service",
                "--since=-60s",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        count = 0
        ips = set()
        for line in out.splitlines():
            if SSHD_FAIL_RE.search(line):
                count += 1
                m = SSH_IP_RE.search(line)
                if m:
                    ips.add(m.group(1))
        if count <= SSH_FAIL_THRESHOLD:
            return []
        summary = "{} failed sshd logins in the last minute from {} IP(s)".format(
            count, len(ips)
        )
        return [
            make_alert(
                "ssh-brute-force",
                "warning",
                summary,
                count=str(count),
                sources=", ".join(sorted(ips))[:200],
            )
        ]


    if __name__ == "__main__":
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        alerts = []
        alerts += scan_failed_units()
        alerts += scan_oom_kills()
        alerts += scan_sshd_bruteforce()
        post(alerts)
  '';
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
