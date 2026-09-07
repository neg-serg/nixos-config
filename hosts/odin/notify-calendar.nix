{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
# Morning Telegram calendar reminder. Each day at 07:30 (Europe/Moscow) the
# oneshot unit lists the local user (neg) khal calendar events for "today";
# if there are any, it posts a single "📅 Сегодня:" message to the Telegram
# chat from secrets/telegram.sops.yaml, otherwise it exits silently.
#
# Auto-imported from hosts/odin/*.nix. Self-contained: does not touch the
# shared telegramSendScript in services.nix (re-implements the socks-proxy
# curl sender so this file can be added/removed independently).
#
# Gating (same as the rest of the Telegram alert stack):
#   - khal is only present when features.mail.enable is set (see
#     modules/user/nix-maid/sys/khal.nix);
#   - the whole stack is inert without secrets/telegram.sops.yaml.
let
  mailOn = config.features.mail.enable or false;
  telegramSecrets = builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml");
in
{
  config = lib.mkIf (mailOn && telegramSecrets) (
    let
      # Runs khal as the user that owns the calendars (neg) and posts a
      # Telegram message through the sing-box socks proxy when today has
      # events. Telegram/network hiccups must not fail the unit, so any
      # delivery problem exits 0 after the retry window.
      script = pkgs.writeShellApplication {
        name = "telegram-calendar-reminder";
        runtimeInputs = [
          pkgs.curl # HTTP(S) client for the Telegram Bot API (socks proxy)
          pkgs.python3 # event parsing / JSON handling
          pkgs.coreutils # runuser environment / sleep retries
        ];
        text = ''
          # khal/config discovered config, calendar files and cache live in the
          # neg home; run khal under that uid so it may read/write them.
          exec python3 - <<'PY'
          import datetime
          import json
          import os
          import subprocess
          import sys
          import time

          KHAL = "/run/current-system/sw/bin/khal"
          RUNUSER = "/run/current-system/sw/bin/runuser"
          KHAL_CONFIG = "/home/neg/.config/khal/config"
          BOT_TOKEN_FILE = "${config.sops.secrets."telegram/bot-token".path}"
          CHAT_ID_FILE = "${config.sops.secrets."telegram/chat-id".path}"

          # allow a test harness to substitute the khal invocation (e.g. a
          # scratch config); if unset, root runs khal via runuser as neg.
          override = os.environ.get("KHAL_CMD_OVERRIDE")


          def khal_list(start, end):
              fields = ["start", "end", "title", "location", "all-day"]
              if override:
                  cmd = override.split() + ["list", start, end]
                  for f in fields:
                      cmd += ["--json", f]
              else:
                  cmd = [RUNUSER, "-u", "neg", "--", "env", "HOME=/home/neg", KHAL,
                         "-c", KHAL_CONFIG, "list", start, end]
                  for f in fields:
                      cmd += ["--json", f]
              # stdout carries one JSON array per calendar day chunk; stderr
              # may carry warnings. A non-zero return (calendar unreadable,
              # etc.) is treated as "no events" so we never fail the unit.
              try:
                  proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
              except Exception as exc:  # noqa: BLE001 - treat as empty
                  sys.stderr.write("khal invocation failed: %s\n" % exc)
                  return []
              events = []
              for line in proc.stdout.splitlines():
                  line = line.strip()
                  if not line.startswith("["):
                      continue
                  try:
                      events.extend(json.loads(line))
                  except ValueError:
                      continue
              return events


          def main():
              today = datetime.date.today()
              tomorrow = today + datetime.timedelta(days=1)
              today_s = today.strftime("%d.%m.%Y")
              events = khal_list(today_s, tomorrow.strftime("%d.%m.%Y"))
              # Range reaches tomorrow 00:00; keep only events that start today
              # (khal "start" is "DD.MM.YYYY" or "DD.MM.YYYY HH:MM").
              events = [e for e in events if (e.get("start") or "").split(" ")[0] == today_s]

              lines = []
              for ev in events:
                  title = (ev.get("title") or "").strip() or "(без названия)"
                  loc = (ev.get("location") or "").strip()
                  # khal renders "all-day" as the string "True"/"False" in JSON.
                  all_day_val = ev.get("all-day")
                  is_allday = all_day_val is True or (
                      isinstance(all_day_val, str) and all_day_val.strip().lower() in ("true", "1")
                  )
                  if is_allday:
                      line = "\u2022 " + title
                  else:
                      start = (ev.get("start") or "").strip()
                      end = (ev.get("end") or "").strip()
                      st = start.split(" ", 1)[1] if " " in start else ""
                      en = end.split(" ", 1)[1] if " " in end else ""
                      line = "\u2022 %s\u2013%s %s" % (st, en, title)
                      if loc:
                          line += " (%s)" % loc
                  if line not in lines:
                      lines.append(line)

              if not lines:
                  return 0  # no events today: do nothing

              msg = "\U0001F4C5 Сегодня:\n" + "\n".join(lines)
              token = open(BOT_TOKEN_FILE).read().strip()
              chat_id = open(CHAT_ID_FILE).read().strip()
              api_url = "https://api.telegram.org/bot%s/sendMessage" % token
              # api.telegram.org is only reachable via the sing-box socks proxy
              # (127.0.0.1:10808) that starts at login; retry 5s x 12.
              ok = False
              for _ in range(12):
                  try:
                      proc = subprocess.run(
                          ["/run/current-system/sw/bin/curl", "-sf", "-o", "/dev/null",
                           "--proxy", "socks5h://127.0.0.1:10808",
                           "--data-urlencode", "chat_id=%s" % chat_id,
                           "--data-urlencode", "text=%s" % msg,
                           api_url],
                          timeout=30,
                      )
                      if proc.returncode == 0:
                          ok = True
                          break
                  except Exception:  # noqa: BLE001 - keep retrying
                      pass
                  time.sleep(5)
              if not ok:
                  # Do not fail the unit if Telegram is unreachable.
                  sys.stderr.write(
                      "telegram-calendar-reminder: could not deliver after retries\n")
              return 0


          sys.exit(main())
          PY
        '';
      };
    in
    lib.mkMerge [
      {
        # Telegram credentials, mirroring services.nix so this unit is
        # independent of that file's block.
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
      }
      {
        systemd.services."telegram-calendar-reminder" = {
          description = "Send today's khal calendar events to Telegram in the morning";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe script}";
            Restart = "on-failure";
            RestartSec = 60;
          };
        };
      }
      {
        # No Persistent=true (same reasoning as services.nix: boot catch-ups
        # on snapshot restore would re-send spurious morning reminders).
        systemd.timers."telegram-calendar-reminder" = {
          description = "Daily 07:30 morning calendar reminder";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 07:30:00";
            Unit = "telegram-calendar-reminder.service";
          };
        };
      }
    ]
  );
}
