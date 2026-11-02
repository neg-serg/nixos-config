//! Alert scanner: failed systemd units, OOM kills and sshd brute force into
//! Alertmanager.
//!
//! Every run posts an array of alerts to the local Alertmanager in its wire
//! format (`{labels: {alertname, severity}, annotations: {summary}, startsAt}`),
//! which routes them on to Telegram:
//!
//! 1. newly failed systemd units, diffed against a persisted snapshot;
//! 2. OOM kills from the kernel journal, read forward from a journal cursor;
//! 3. sshd brute-force attempts, above a per-window threshold.
//!
//! Alertmanager may be starting up, so a delivery problem is reported and
//! swallowed — the scan itself never fails.
//!
//! Paths and the URL come from the environment (the unit sets them):
//!   SCANNER_STATE_DIR         snapshot and cursor files
//!   SCANNER_SYSTEMCTL         systemctl binary
//!   SCANNER_JOURNALCTL        journalctl binary
//!   SCANNER_ALERTMANAGER_URL  where the alerts are posted
//!   SCANNER_NOW               override the `startsAt` timestamp (tests only)

#[path = "lib.rs"]
mod shared;

use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const DEFAULT_STATE_DIR: &str = "/var/lib/telegram-alert-scanner";
const DEFAULT_SYSTEMCTL: &str = "/run/current-system/sw/bin/systemctl";
const DEFAULT_JOURNALCTL: &str = "/run/current-system/sw/bin/journalctl";
/// v1 was removed in alertmanager 0.27+.
const DEFAULT_ALERTMANAGER_URL: &str = "http://127.0.0.1:9093/api/v2/alerts";
const SSH_FAIL_THRESHOLD: usize = 3;

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn state_dir() -> PathBuf {
    PathBuf::from(env_or("SCANNER_STATE_DIR", DEFAULT_STATE_DIR))
}

/// `2026-11-02T06:00:00Z`, or whatever `SCANNER_NOW` says.
fn now_iso() -> String {
    if let Ok(value) = std::env::var("SCANNER_NOW") {
        let value = value.trim().to_string();
        if !value.is_empty() {
            return value;
        }
    }
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs() as i64)
        .unwrap_or(0);
    let (year, month, day) = shared::civil_from_days(seconds.div_euclid(86_400));
    let remainder = seconds.rem_euclid(86_400);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        remainder / 3600,
        (remainder % 3600) / 60,
        remainder % 60
    )
}

fn run_cmd(program: &str, args: &[&str]) -> String {
    match Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .output()
    {
        Ok(output) => String::from_utf8_lossy(&output.stdout).to_string(),
        Err(exc) => {
            eprintln!("scanner: cannot run {program}: {exc}");
            String::new()
        }
    }
}

/// One Alertmanager alert.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Alert {
    pub alertname: String,
    pub severity: String,
    pub summary: String,
    /// Extra labels, sorted so the payload is stable.
    pub labels: Vec<(String, String)>,
}

impl Alert {
    pub fn new(
        alertname: &str,
        severity: &str,
        summary: String,
        labels: &[(&str, String)],
    ) -> Alert {
        // Keep the caller's order: Alertmanager keys off the label names, and
        // Python's `dict({"alertname", "severity"}, **labels)` did the same.
        let labels: Vec<(String, String)> = labels
            .iter()
            .map(|(name, value)| (name.to_string(), value.clone()))
            .collect();
        Alert {
            alertname: alertname.to_string(),
            severity: severity.to_string(),
            summary,
            labels,
        }
    }

    fn to_json(&self, starts_at: &str) -> String {
        let mut labels = vec![
            ("alertname".to_string(), self.alertname.clone()),
            ("severity".to_string(), self.severity.clone()),
        ];
        labels.extend(self.labels.iter().cloned());
        let labels: Vec<String> = labels
            .iter()
            .map(|(name, value)| format!("{:?}: {:?}", name, value))
            .collect();
        format!(
            "{{\"labels\": {{{}}}, \"annotations\": {{\"summary\": {:?}}}, \"startsAt\": {:?}}}",
            labels.join(", "),
            self.summary,
            starts_at
        )
    }
}

/// POST the alerts; delivery problems are reported and swallowed.
pub fn post(alerts: &[Alert], url: &str, starts_at: &str) -> bool {
    if alerts.is_empty() {
        return true;
    }
    let body = format!(
        "[{}]",
        alerts
            .iter()
            .map(|alert| alert.to_json(starts_at))
            .collect::<Vec<_>>()
            .join(", ")
    );
    let Some((host, port, path)) = parse_url(url) else {
        eprintln!("scanner: cannot deliver alerts: bad url {url}");
        return false;
    };
    let mut stream = match TcpStream::connect((host.as_str(), port)) {
        Ok(stream) => stream,
        Err(exc) => {
            eprintln!("scanner: cannot deliver alerts: {exc}");
            return false;
        }
    };
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    if let Err(exc) = stream.write_all(request.as_bytes()) {
        eprintln!("scanner: cannot deliver alerts: {exc}");
        return false;
    }
    let mut sink = Vec::new();
    let _ = stream.read_to_end(&mut sink);
    true
}

fn parse_url(url: &str) -> Option<(String, u16, String)> {
    let rest = url.strip_prefix("http://")?;
    let (authority, path) = match rest.find('/') {
        Some(index) => (&rest[..index], &rest[index..]),
        None => (rest, "/"),
    };
    match authority.rsplit_once(':') {
        Some((host, port)) => Some((host.to_string(), port.parse().ok()?, path.to_string())),
        None => Some((authority.to_string(), 80, path.to_string())),
    }
}

/// Newly failed units; the snapshot forgets recovered ones.
pub fn scan_failed_units(dir: &Path) -> Vec<Alert> {
    let systemctl = env_or("SCANNER_SYSTEMCTL", DEFAULT_SYSTEMCTL);
    let output = run_cmd(
        &systemctl,
        &[
            "list-units",
            "--failed",
            "--no-legend",
            "--plain",
            "--no-pager",
        ],
    );
    let current: Vec<String> = output
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .map(str::to_string)
        .collect();
    let snapshot_file = dir.join("failed-units.json");
    let previous = std::fs::read_to_string(&snapshot_file)
        .ok()
        .and_then(|text| shared::json::parse(&text))
        .and_then(|value| value.as_array().map(|items| items.to_vec()))
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let mut sorted_current = current.clone();
    sorted_current.sort();
    sorted_current.dedup();
    let mut sorted_previous = previous.clone();
    sorted_previous.sort();
    if sorted_current != sorted_previous {
        let body = format!(
            "[{}]",
            sorted_current
                .iter()
                .map(|unit| format!("{unit:?}"))
                .collect::<Vec<_>>()
                .join(", ")
        );
        if let Err(exc) = std::fs::write(&snapshot_file, body) {
            eprintln!("scanner: cannot save failed-unit snapshot: {exc}");
        }
    }
    sorted_current
        .into_iter()
        .filter(|unit| !sorted_previous.contains(unit))
        .map(|unit| {
            Alert::new(
                "systemd-failed-unit",
                "error",
                format!("Systemd unit failed: {unit}"),
                &[("unit", unit)],
            )
        })
        .collect()
}

fn journal_cursor(cursor_file: &Path) -> Option<String> {
    std::fs::read_to_string(cursor_file)
        .ok()
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn advance_journal_cursor(output: &str, cursor_file: &Path) {
    // journalctl prints a trailing `-- cursor: <value>` line.
    for line in output.lines() {
        if let Some(rest) = line.strip_prefix("-- cursor: ") {
            let cursor = rest.trim();
            if !cursor.is_empty() {
                if let Err(exc) = std::fs::write(cursor_file, cursor) {
                    eprintln!("scanner: cannot save journal cursor: {exc}");
                }
            }
            return;
        }
    }
}

fn seed_journal_cursor(cursor_file: &Path) {
    let journalctl = env_or("SCANNER_JOURNALCTL", DEFAULT_JOURNALCTL);
    if journal_cursor(cursor_file).is_some() {
        return;
    }
    let output = run_cmd(
        &journalctl,
        &["-n", "0", "--show-cursor", "--no-pager", "-o", "short"],
    );
    advance_journal_cursor(&output, cursor_file);
}

/// Process names of every OOM kill seen since the last scan.
pub fn scan_oom_kills(dir: &Path) -> Vec<Alert> {
    let journalctl = env_or("SCANNER_JOURNALCTL", DEFAULT_JOURNALCTL);
    let cursor_file = dir.join("oom-journal-cursor");
    seed_journal_cursor(&cursor_file);
    let Some(cursor) = journal_cursor(&cursor_file) else {
        return Vec::new();
    };
    let after = format!("--after-cursor={cursor}");
    let output = run_cmd(
        &journalctl,
        &[after.as_str(), "--show-cursor", "--no-pager", "-o", "short"],
    );
    advance_journal_cursor(&output, &cursor_file);
    let kills = oom_kill_names(&output);
    if kills.is_empty() {
        return Vec::new();
    }
    let mut unique: Vec<String> = kills.iter().cloned().collect();
    unique.sort();
    unique.dedup();
    let summary = format!(
        "{} OOM kill(s): {}",
        kills.len(),
        unique
            .iter()
            .take(10)
            .cloned()
            .collect::<Vec<_>>()
            .join(", ")
    );
    vec![Alert::new(
        "oom-kill",
        "error",
        summary,
        &[("count", kills.len().to_string())],
    )]
}

/// Names from `Out of memory: Killed process 123 (name)`.
pub fn oom_kill_names(output: &str) -> Vec<String> {
    const MARKER: &str = "Out of memory: Killed process ";
    let mut names = Vec::new();
    for line in output.lines() {
        let Some(rest) = line.split(MARKER).nth(1) else {
            continue;
        };
        // "<pid> (<name>)" — the pid is digits up to a space.
        let Some((pid, tail)) = rest.split_once(' ') else {
            continue;
        };
        if pid.is_empty() || !pid.chars().all(|ch| ch.is_ascii_digit()) {
            continue;
        }
        if let Some(name) = tail.strip_prefix('(').and_then(|t| t.split(')').next()) {
            names.push(name.to_string());
        }
    }
    names
}

/// One alert per window when failed logins exceed the threshold.
pub fn scan_sshd_bruteforce() -> Vec<Alert> {
    let journalctl = env_or("SCANNER_JOURNALCTL", DEFAULT_JOURNALCTL);
    let output = run_cmd(
        &journalctl,
        &[
            "-u",
            "sshd.service",
            "--since=-60s",
            "--no-pager",
            "-o",
            "short",
        ],
    );
    let mut count = 0usize;
    let mut sources: Vec<String> = Vec::new();
    for line in output.lines() {
        if !line.contains("Failed password") && !line.contains("Invalid user") {
            continue;
        }
        count += 1;
        if let Some(ip) = sshd_source(line) {
            sources.push(ip);
        }
    }
    if count <= SSH_FAIL_THRESHOLD {
        return Vec::new();
    }
    sources.sort();
    sources.dedup();
    let summary = format!(
        "{count} failed sshd logins in the last minute from {} IP(s)",
        sources.len()
    );
    let joined: String = sources.join(", ").chars().take(200).collect();
    vec![Alert::new(
        "ssh-brute-force",
        "warning",
        summary,
        &[("count", count.to_string()), ("sources", joined)],
    )]
}

/// The `from <ip> port <n>` address of a log line, if it has one.
pub fn sshd_source(line: &str) -> Option<String> {
    let rest = line.split(" from ").nth(1)?;
    let ip = rest.split_whitespace().next()?;
    if ip.is_empty() {
        return None;
    }
    Some(ip.to_string())
}

fn main() -> std::process::ExitCode {
    let dir = state_dir();
    if let Err(exc) = std::fs::create_dir_all(&dir) {
        eprintln!("scanner: cannot create {}: {exc}", dir.display());
        return std::process::ExitCode::from(1);
    }
    let mut alerts = Vec::new();
    alerts.extend(scan_failed_units(&dir));
    alerts.extend(scan_oom_kills(&dir));
    alerts.extend(scan_sshd_bruteforce());
    let url = env_or("SCANNER_ALERTMANAGER_URL", DEFAULT_ALERTMANAGER_URL);
    post(&alerts, &url, &now_iso());
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "scanner-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|delta| delta.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test]
    fn oom_lines_yield_process_names() {
        let output = "\
Nov 02 06:00:00 trantor kernel: Out of memory: Killed process 1234 (firefox) total-vm:1kB
Nov 02 06:00:01 trantor kernel: Out of memory: Killed process 99 (node) total-vm:2kB
noise line without a kill
";
        assert_eq!(oom_kill_names(output), vec!["firefox", "node"]);
        assert!(oom_kill_names("Killed process without marker").is_empty());
    }

    #[test]
    fn sshd_sources_are_extracted() {
        assert_eq!(
            sshd_source("Nov 02 06:00:00 trantor sshd[1]: Failed password for root from 1.2.3.4 port 22 ssh2"),
            Some("1.2.3.4".to_string())
        );
        assert_eq!(sshd_source("no address here"), None);
    }

    #[test]
    fn alert_payload_matches_the_alertmanager_wire_format() {
        let alert = Alert::new(
            "systemd-failed-unit",
            "error",
            "Systemd unit failed: foo.service".to_string(),
            &[("unit", "foo.service".to_string())],
        );
        assert_eq!(
            alert.to_json("2026-11-02T06:00:00Z"),
            "{\"labels\": {\"alertname\": \"systemd-failed-unit\", \"severity\": \"error\", \"unit\": \"foo.service\"}, \"annotations\": {\"summary\": \"Systemd unit failed: foo.service\"}, \"startsAt\": \"2026-11-02T06:00:00Z\"}"
        );
    }

    #[test]
    fn urls_are_split_into_host_port_and_path() {
        assert_eq!(
            parse_url("http://127.0.0.1:9093/api/v2/alerts"),
            Some(("127.0.0.1".to_string(), 9093, "/api/v2/alerts".to_string()))
        );
        assert_eq!(
            parse_url("http://localhost/x"),
            Some(("localhost".to_string(), 80, "/x".to_string()))
        );
        assert_eq!(parse_url("https://x/y"), None);
    }

    #[test]
    fn failed_units_are_diffed_against_the_snapshot() {
        let dir = temp_dir("units");
        // No systemctl in the test environment: the scan sees no units.
        std::env::set_var("SCANNER_SYSTEMCTL", "/bin/true");
        assert!(scan_failed_units(&dir).is_empty());
        std::env::remove_var("SCANNER_SYSTEMCTL");
        std::fs::remove_dir_all(&dir).ok();
    }
}
