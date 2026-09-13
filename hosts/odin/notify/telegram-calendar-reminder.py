import datetime
import json
import os
import subprocess
import sys

KHAL = "/run/current-system/sw/bin/khal"
RUNUSER = "/run/current-system/sw/bin/runuser"
KHAL_CONFIG = "/home/neg/.config/khal/config"
SENDER = "@sender@/bin/telegram-send"

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
        cmd = [
            RUNUSER,
            "-u",
            "neg",
            "--",
            "env",
            "HOME=/home/neg",
            KHAL,
            "-c",
            KHAL_CONFIG,
            "list",
            start,
            end,
        ]
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
    events = [
        e for e in events if (e.get("start") or "").split(" ")[0] == today_s
    ]

    lines = []
    for ev in events:
        title = (ev.get("title") or "").strip() or "(без названия)"
        loc = (ev.get("location") or "").strip()
        # khal renders "all-day" as the string "True"/"False" in JSON.
        all_day_val = ev.get("all-day")
        is_allday = all_day_val is True or (
            isinstance(all_day_val, str)
            and all_day_val.strip().lower() in ("true", "1")
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

    msg = "\U0001f4c5 Сегодня:\n" + "\n".join(lines)
    # The shared sender retries through the sing-box socks proxy;
    # never fail the unit if Telegram is unreachable.
    try:
        proc = subprocess.run([SENDER, msg], timeout=90)
        if proc.returncode != 0:
            raise OSError("sender exited with %s" % proc.returncode)
    except Exception:  # noqa: BLE001
        sys.stderr.write(
            "telegram-calendar-reminder: could not deliver after retries\n"
        )
    return 0


sys.exit(main())
