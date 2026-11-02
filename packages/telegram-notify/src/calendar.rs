//! Daily calendar digest for Telegram.
//!
//! Asks khal for today's events (run under the user that owns the calendars,
//! `neg`), formats one line per event and hands the message to the shared
//! `telegram-send` wrapper, which owns the socks-proxy retry policy. Delivery
//! problems must never fail the unit, so anything that goes wrong exits 0 —
//! the same contract the Python script had.
//!
//! The khal invocation can be replaced through `KHAL_CMD_OVERRIDE` (a command
//! line, first word is the executable), which is what the tests use.

#[path = "lib.rs"]
mod shared;

use std::process::{Command, Stdio};

const RUNUSER: &str = "/run/current-system/sw/bin/runuser";
const KHAL: &str = "/run/current-system/sw/bin/khal";
const KHAL_CONFIG: &str = "/home/neg/.config/khal/config";
const KHAL_TIMEOUT_SECONDS: u64 = 120;
const SENDER_TIMEOUT_SECONDS: u64 = 90;

/// `khal list <start> <end> --json …`, returning the events that started today.
fn khal_events(start: &str, end: &str, today: &str) -> Vec<shared::json::Value> {
    let fields = ["start", "end", "title", "location", "all-day"];
    let override_cmd = std::env::var("KHAL_CMD_OVERRIDE")
        .ok()
        .filter(|value| !value.is_empty());
    let mut command = match &override_cmd {
        Some(line) => {
            let mut words = line.split_whitespace();
            let mut command = Command::new(words.next().unwrap_or("khal"));
            command.args(words);
            command
        }
        None => {
            let mut command = Command::new(RUNUSER);
            command.args([
                "-u",
                "neg",
                "--",
                "env",
                "HOME=/home/neg",
                KHAL,
                "-c",
                KHAL_CONFIG,
            ]);
            command
        }
    };
    command.args(["list", start, end]);
    for field in fields {
        command.args(["--json", field]);
    }
    command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .stdin(Stdio::null());
    let Ok(mut child) = command.spawn() else {
        eprintln!("khal invocation failed: cannot spawn");
        return Vec::new();
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(KHAL_TIMEOUT_SECONDS);
    let output = loop {
        match child.try_wait() {
            Ok(Some(_)) => break child.wait_with_output().ok(),
            Ok(None) if std::time::Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                eprintln!("khal invocation failed: timeout");
                return Vec::new();
            }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(50)),
            Err(_) => return Vec::new(),
        }
    };
    let Some(output) = output else {
        return Vec::new();
    };
    // One JSON array per calendar day chunk; anything else on stdout is skipped,
    // and a non-zero exit still keeps whatever parsed (never fail the unit).
    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut events = Vec::new();
    for line in stdout.lines() {
        let line = line.trim();
        if !line.starts_with('[') {
            continue;
        }
        if let Some(shared::json::Value::Array(items)) = shared::json::parse(line) {
            events.extend(items);
        }
    }
    // Keep only events that start today: khal prints `DD.MM.YYYY` or
    // `DD.MM.YYYY HH:MM`, and the range reaches tomorrow 00:00.
    events.retain(|event| {
        event
            .get("start")
            .and_then(shared::json::Value::as_str)
            .unwrap_or("")
            .split(' ')
            .next()
            .unwrap_or("")
            == today
    });
    events
}

fn text_field(event: &shared::json::Value, name: &str) -> String {
    event
        .get(name)
        .and_then(shared::json::Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string()
}

fn is_all_day(event: &shared::json::Value) -> bool {
    match event.get("all-day") {
        Some(shared::json::Value::Bool(flag)) => *flag,
        Some(shared::json::Value::Str(text)) => {
            matches!(text.trim().to_lowercase().as_str(), "true" | "1")
        }
        _ => false,
    }
}

/// One bullet per event, without duplicates.
pub fn format_events(events: &[shared::json::Value]) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for event in events {
        let mut title = text_field(event, "title");
        if title.is_empty() {
            title = "(untitled)".to_string();
        }
        let location = text_field(event, "location");
        let line = if is_all_day(event) {
            format!("• {title}")
        } else {
            let start = text_field(event, "start");
            let end = text_field(event, "end");
            let start_time = start.split_once(' ').map(|(_, time)| time).unwrap_or("");
            let end_time = end.split_once(' ').map(|(_, time)| time).unwrap_or("");
            let mut line = format!("• {start_time}–{end_time} {title}");
            if !location.is_empty() {
                line.push_str(&format!(" ({location})"));
            }
            line
        };
        if !lines.contains(&line) {
            lines.push(line);
        }
    }
    lines
}

fn main() -> std::process::ExitCode {
    let today_iso = shared::local_today();
    let today = shared::khal_date(&today_iso);
    let tomorrow = shared::khal_date(&shared::tomorrow(&today_iso));
    let events = khal_events(&today, &tomorrow, &today);
    let lines = format_events(&events);
    if lines.is_empty() {
        return std::process::ExitCode::SUCCESS; // nothing today: do nothing
    }
    let message = format!("📅 Today:\n{}", lines.join("\n"));
    let sender = std::env::var("TELEGRAM_SENDER")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "telegram-send".to_string());
    if !shared::send_via_sender(&sender, &message, SENDER_TIMEOUT_SECONDS) {
        eprintln!("telegram-calendar-reminder: could not deliver after retries");
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;
    use shared::json;

    fn event(text: &str) -> json::Value {
        json::parse(text).expect("event")
    }

    #[test]
    fn timed_events_carry_times_and_location() {
        let events = vec![event(
            r#"{"start": "02.11.2026 09:00", "end": "02.11.2026 10:30",
                "title": "Standup", "location": "Room 1", "all-day": "False"}"#,
        )];
        assert_eq!(
            format_events(&events),
            vec!["• 09:00–10:30 Standup (Room 1)"]
        );
    }

    #[test]
    fn all_day_events_are_one_bullet() {
        let events = vec![event(
            r#"{"start": "02.11.2026", "end": "03.11.2026",
                "title": "Holiday", "location": "", "all-day": true}"#,
        )];
        assert_eq!(format_events(&events), vec!["• Holiday"]);
    }

    #[test]
    fn untitled_and_duplicate_events_collapse() {
        let events = vec![
            event(
                r#"{"start": "02.11.2026 12:00", "end": "02.11.2026 13:00", "title": "", "all-day": false}"#,
            ),
            event(
                r#"{"start": "02.11.2026 12:00", "end": "02.11.2026 13:00", "title": "", "all-day": false}"#,
            ),
        ];
        assert_eq!(format_events(&events), vec!["• 12:00–13:00 (untitled)"]);
    }
}
