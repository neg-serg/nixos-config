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
ALERTMANAGER_URL = "http://127.0.0.1:9093/api/v2/alerts"  # v1 API removed in alertmanager 0.27+

OOM_RE = re.compile(r"Out of memory: Killed process (\d+) \((\S+)\)")
SSHD_FAIL_RE = re.compile(r"(Failed password|Invalid user)")
SSH_FAIL_THRESHOLD = 3
SSH_IP_RE = re.compile(r"\bfrom (\S+) port \d+")


def now_iso():
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_cmd(args):
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, check=False
        )
        return proc.stdout or ""
    except OSError as exc:
        print(
            "scanner: cannot run {}: {}".format(" ".join(args), exc),
            file=sys.stderr,
        )
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
        print(
            "scanner: cannot deliver alerts: {}".format(exc), file=sys.stderr
        )


def make_alert(alertname, severity, summary, **labels):
    return {
        "labels": dict(
            {"alertname": alertname, "severity": severity}, **labels
        ),
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
            print(
                "scanner: bad failed-unit snapshot: {}".format(exc),
                file=sys.stderr,
            )
    if failed != previous:
        try:
            FAILED_UNITS_FILE.write_text(json.dumps(sorted(failed)))
        except OSError as exc:
            print(
                "scanner: cannot save failed-unit snapshot: {}".format(exc),
                file=sys.stderr,
            )
    return [
        make_alert(
            "systemd-failed-unit",
            "error",
            "Systemd unit failed: {}".format(unit),
            unit=unit,
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
            print(
                "scanner: cannot save journal cursor: {}".format(exc),
                file=sys.stderr,
            )


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
    summary = "{} OOM kill(s): {}".format(
        len(kills), ", ".join(sorted(set(kills))[:10])
    )
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
