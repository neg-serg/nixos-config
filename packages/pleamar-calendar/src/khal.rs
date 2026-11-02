//! `khal list`, its retry and the pipe-separated event lines.
//!
//! The shell ran
//!
//! ```text
//! khal list --format '{start-date}|{start-time}|{title}|{calendar}' FIRST LAST
//! ```
//!
//! in ISO first and retried with dd.mm.yyyy when khal exited non-zero or wrote
//! `critical`/`Traceback` to stderr (this host's khal parses CLI dates with the
//! `dateformat` from its own config). khal stays a subprocess: it owns the
//! user's calendars and config, and the shell's failure text is part of what a
//! scene can see, so the invocation, retry and error wording are unchanged.

use std::path::Path;
use std::process::Command;

use crate::date::{normalize_date, Month};

pub const FORMAT: &str = "{start-date}|{start-time}|{title}|{calendar}";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Event {
    pub date: String,
    pub time: String,
    pub title: String,
    pub calendar: String,
}

impl Event {
    /// The shell's `{date: .[0], time: .[1], title: .[2], calendar: .[3]}`
    /// object order.
    pub fn to_json(&self) -> String {
        format!(
            "{{\"date\":{},\"time\":{},\"title\":{},\"calendar\":{}}}",
            crate::json::string(&self.date),
            crate::json::string(&self.time),
            crate::json::string(&self.title),
            crate::json::string(&self.calendar),
        )
    }
}

/// `command -v khal`: an executable file on PATH is a start requirement, and a
/// missing khal is the one start error the Rust worker still has.
pub fn installed() -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|directory| executable(&directory.join("khal")))
}

fn executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    match std::fs::metadata(path) {
        Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// Run khal for the month; ISO dates first, dd.mm.yyyy second. `Err` carries
/// `khal list failed: …`, the shell's `ERR_MSG`.
pub fn list_month(month: &Month) -> Result<String, String> {
    let first = run(&month.first, &month.last)?;
    if !failed(&first) {
        return Ok(first.stdout);
    }
    let second = run(&month.first_eu, &month.last_eu)?;
    if !failed(&second) {
        return Ok(second.stdout);
    }
    let error = second
        .stderr
        .split('\n')
        .next()
        .unwrap_or_default()
        .to_string();
    let error = if error.is_empty() {
        format!("khal exited {}", second.code)
    } else {
        error
    };
    Err(format!("khal list failed: {error}"))
}

struct Attempt {
    stdout: String,
    stderr: String,
    code: i32,
}

fn failed(attempt: &Attempt) -> bool {
    if attempt.code != 0 {
        return true;
    }
    attempt.stderr.contains("critical") || attempt.stderr.contains("Traceback")
}

fn run(first: &str, last: &str) -> Result<Attempt, String> {
    use std::os::unix::process::ExitStatusExt;
    let output = Command::new("khal")
        .args(["list", "--format", FORMAT, first, last])
        .output()
        .map_err(|error| format!("khal list failed: {error}"))?;
    let code = output
        .status
        .code()
        .unwrap_or_else(|| 128 + output.status.signal().unwrap_or(0));
    Ok(Attempt {
        // jq decoded the shell's text; the dates and titles are UTF-8.
        stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        code,
    })
}

/// `parse_events`: strip SGR sequences, keep lines with three pipes, split
/// date/time/title/calendar, trim, normalise the date, then jq's tab split.
///
/// `sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'` only recognises that family, so other
/// escapes stay in the text exactly as the shell left them.
pub fn parse_events(text: &str) -> Vec<Event> {
    let mut events = Vec::new();
    for raw_line in text.split('\n') {
        let line = strip_ansi(raw_line);
        if line.matches('|').count() < 3 {
            continue;
        }
        let mut parts = line.splitn(3, '|');
        // The count check above guarantees three separators; the last field is
        // the rest, which keeps pipes inside the title.
        let raw_date = parts.next().unwrap_or_default().trim();
        let raw_time = parts.next().unwrap_or_default().trim();
        let rest = parts.next().unwrap_or_default();
        let (title, calendar) = match rest.rsplit_once('|') {
            Some((title, calendar)) => (title.trim(), calendar.trim()),
            None => continue,
        };
        let entry = Event {
            date: normalize_date(raw_date),
            time: raw_time.to_string(),
            title: title.to_string(),
            calendar: calendar.to_string(),
        };
        // The shell joined the fields with tabs and let jq split on them, so a
        // tab inside the title moved the calendar value; reproduce that by
        // rebuilding the same row and taking the first four cells.
        let pressed = format!(
            "{}\t{}\t{}\t{}",
            entry.date, entry.time, entry.title, entry.calendar
        );
        let cells: Vec<&str> = pressed.split('\t').collect();
        events.push(Event {
            date: cells.first().copied().unwrap_or_default().to_string(),
            time: cells.get(1).copied().unwrap_or_default().to_string(),
            title: cells.get(2).copied().unwrap_or_default().to_string(),
            calendar: cells.get(3).copied().unwrap_or_default().to_string(),
        });
    }
    events
}

/// `sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'`, byte for byte.
fn strip_ansi(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut kept = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == 0x1b && bytes.get(index + 1) == Some(&b'[') {
            let mut end = index + 2;
            while end < bytes.len() && (bytes[end].is_ascii_digit() || bytes[end] == b';') {
                end += 1;
            }
            if end < bytes.len() && bytes[end].is_ascii_alphabetic() {
                index = end + 1;
                continue;
            }
        }
        kept.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&kept).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_are_split_trimmed_and_normalised() {
        let text = concat!(
            "Today, 2026-11-05\n",
            "2026-11-05|09:00|Standup|Work\n",
            "2026-11-06| 18:30 |Concert|a|b|Personal\n",
            "05.11.2026|10:00|EU date|Cal\n",
            "no pipes here\n",
            "2026-11-07|11:00|only three|pipes\n",
        );
        let events = parse_events(text);
        assert_eq!(
            events,
            vec![
                Event {
                    date: "2026-11-05".into(),
                    time: "09:00".into(),
                    title: "Standup".into(),
                    calendar: "Work".into(),
                },
                Event {
                    date: "2026-11-06".into(),
                    time: "18:30".into(),
                    title: "Concert|a|b".into(),
                    calendar: "Personal".into(),
                },
                Event {
                    date: "2026-11-05".into(),
                    time: "10:00".into(),
                    title: "EU date".into(),
                    calendar: "Cal".into(),
                },
                Event {
                    date: "2026-11-07".into(),
                    time: "11:00".into(),
                    title: "only three".into(),
                    calendar: "pipes".into(),
                },
            ]
        );
    }

    #[test]
    fn an_unknown_date_is_kept_and_ansi_is_stripped() {
        let events = parse_events("\x1b[31mnext week\x1b[0m|09:00|T\x1b[1;32mitle|Cal\n");
        assert_eq!(events[0].date, "next week");
        assert_eq!(events[0].title, "Title");
        assert_eq!(events[0].calendar, "Cal");
    }

    #[test]
    fn empty_text_has_no_events() {
        assert!(parse_events("").is_empty());
        assert!(parse_events("\n\n").is_empty());
    }

    #[test]
    fn a_tab_in_the_title_moves_the_calendar_like_jq() {
        let events = parse_events("2026-11-05|09:00|A\tB|Cal\n");
        assert_eq!(events[0].title, "A");
        assert_eq!(events[0].calendar, "B");
    }

    #[test]
    fn event_json_has_the_jq_key_order() {
        let event = Event {
            date: "2026-11-05".into(),
            time: "09:00".into(),
            title: "a \"quote\"".into(),
            calendar: "Work".into(),
        };
        assert_eq!(
            event.to_json(),
            r#"{"date":"2026-11-05","time":"09:00","title":"a \"quote\"","calendar":"Work"}"#
        );
    }
}
