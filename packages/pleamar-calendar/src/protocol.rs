//! The §7 protocol: handshake, command lines, acknowledgements, sample lines.
//!
//! The shell's lines are frozen; this module reproduces them byte for byte.
//! Command parsing repeats the shell's jq round trip
//! (`[.cmd // "", .topic // "", (.interval_ms // "" | tostring), .month // ""]
//! | join("|")` followed by `IFS='|' read -r cmd topic interval month`), which
//! is also why a `|` inside a field shifts the rest — that quirk is kept
//! because a scene could observe the reply.
//!
//! Month navigation is the domain argument the script adds to §7: a `month`
//! field on any command is applied first (and reschedules the topic), so
//! `sample`/`set`/`subscribe` with `month` answer and then emit the new month.

use std::io::{self, Write};

use crate::date::Month;
use crate::json;

pub const WORKER: &str = "calendar";
pub const TOPIC: &str = "calendar";
pub const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"calendar\",\"version\":1,\"topics\":[\"calendar\"]}";

const MIN_INTERVAL_MS: u128 = 100;
const MAX_INTERVAL_MS: u128 = 3_600_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Control {
    Continue,
    Stop,
}

/// One topic's subscription; the worker knows exactly one topic, so the
/// shell's associative arrays collapse to two fields.
#[derive(Clone, Copy, Debug)]
struct Subscription {
    interval_ms: u64,
    next_ms: u64,
}

pub struct Session {
    default_interval_ms: u64,
    subscription: Option<Subscription>,
    month: Month,
}

impl Session {
    /// The shell subscribed `calendar` before the handshake with `next=0`, so
    /// the first sample is due on the first loop pass (not one interval in).
    pub fn new(interval_ms: u64, month: Month) -> Self {
        Self {
            default_interval_ms: interval_ms,
            subscription: Some(Subscription {
                interval_ms,
                next_ms: 0,
            }),
            month,
        }
    }

    pub fn month(&self) -> &Month {
        &self.month
    }

    pub fn handle_line<W: Write>(&mut self, line: &str, out: &mut W) -> io::Result<Control> {
        let fields = match parse_fields(line) {
            Ok(fields) => fields,
            Err(()) => {
                write_error(out, "bad command line")?;
                return Ok(Control::Continue);
            }
        };

        // A month in the command navigates before anything else answers.
        if !fields.month.is_empty() {
            match Month::parse(&fields.month) {
                Some(month) => {
                    self.month = month;
                    if let Some(subscription) = &mut self.subscription {
                        subscription.next_ms = 0;
                    }
                }
                None => {
                    write_error(out, &format!("bad month: {}", fields.month))?;
                    return Ok(Control::Continue);
                }
            }
        }

        match fields.cmd.as_str() {
            "subscribe" => {
                if fields.topic != TOPIC {
                    write_error(out, &format!("unknown topic: {}", fields.topic))?;
                    return Ok(Control::Continue);
                }
                let interval_text = if fields.interval.is_empty() {
                    self.subscription
                        .map_or(self.default_interval_ms, |subscription| {
                            subscription.interval_ms
                        })
                        .to_string()
                } else {
                    fields.interval.clone()
                };
                let Some(interval_ms) = parse_interval(&interval_text) else {
                    write_error(out, &interval_error(&interval_text))?;
                    return Ok(Control::Continue);
                };
                self.subscription = Some(Subscription {
                    interval_ms,
                    next_ms: 0,
                });
                write_ack(out, "subscribe")?;
            }
            "unsubscribe" => {
                if fields.topic != TOPIC {
                    write_error(out, &format!("unknown topic: {}", fields.topic))?;
                    return Ok(Control::Continue);
                }
                self.subscription = None;
                write_ack(out, "unsubscribe")?;
            }
            "set" => {
                if !fields.interval.is_empty() {
                    let Some(interval_ms) = parse_interval(&fields.interval) else {
                        write_error(out, &interval_error(&fields.interval))?;
                        return Ok(Control::Continue);
                    };
                    // `set` changes the cadence only; `next` stays where it was.
                    if let Some(subscription) = &mut self.subscription {
                        subscription.interval_ms = interval_ms;
                    }
                } else if fields.month.is_empty() {
                    write_error(out, "set needs interval_ms or month")?;
                    return Ok(Control::Continue);
                }
                write_ack(out, "set")?;
            }
            "sample" => {
                // The shell zeroed every `SUB_NEXT` before the ack; the main
                // loop then emitted the due topic.
                if let Some(subscription) = &mut self.subscription {
                    subscription.next_ms = 0;
                }
                write_ack(out, "sample")?;
            }
            "stop" => {
                write_ack(out, "stop")?;
                return Ok(Control::Stop);
            }
            _ => {
                write_error(out, &format!("unknown cmd: {}", fields.cmd))?;
            }
        }
        Ok(Control::Continue)
    }

    pub fn due(&self, now_ms: u64) -> bool {
        self.subscription
            .is_some_and(|subscription| subscription.next_ms <= now_ms)
    }

    /// The shell scheduled `now + interval` before emitting.
    pub fn advance(&mut self, now_ms: u64) {
        if let Some(subscription) = &mut self.subscription {
            subscription.next_ms = now_ms.saturating_add(subscription.interval_ms);
        }
    }
}

/// The line a worker that cannot start prints before exiting 1. The only such
/// condition left is a missing `khal` (jq is compiled in).
pub fn start_error(message: &str) -> String {
    format!(
        "{{\"ok\":false,\"worker\":\"{WORKER}\",\"err\":{}}}",
        json::string(message)
    )
}

pub fn write_handshake<W: Write>(out: &mut W) -> io::Result<()> {
    writeln!(out, "{HANDSHAKE}")
}

pub fn write_ack<W: Write>(out: &mut W, ack: &str) -> io::Result<()> {
    writeln!(out, "{{\"ok\":true,\"ack\":\"{ack}\"}}")
}

pub fn write_error<W: Write>(out: &mut W, message: &str) -> io::Result<()> {
    writeln!(out, "{{\"ok\":false,\"err\":{}}}", json::string(message))
}

pub fn write_sample<W: Write>(out: &mut W, t: u64, data: &str) -> io::Result<()> {
    writeln!(
        out,
        "{{\"ok\":true,\"worker\":\"{WORKER}\",\"topic\":\"{TOPIC}\",\"t\":{t},\"data\":{data}}}"
    )
}

pub fn write_sample_error<W: Write>(out: &mut W, t: u64, message: &str) -> io::Result<()> {
    writeln!(
        out,
        "{{\"ok\":false,\"worker\":\"{WORKER}\",\"err\":{},\"t\":{t}}}",
        json::string(message)
    )
}

/// jq's jq-stream + `join("|")` + bash's `read`: four fields, and a `|` in one
/// of them shifts the later ones exactly as bash's `read` did.
struct Fields {
    cmd: String,
    topic: String,
    interval: String,
    month: String,
}

fn parse_fields(line: &str) -> Result<Fields, ()> {
    let Some(value) = parse_first_value(line)? else {
        return Ok(Fields {
            cmd: String::new(),
            topic: String::new(),
            interval: String::new(),
            month: String::new(),
        });
    };
    let map = match &value {
        serde_json::Value::Object(map) => Some(map),
        serde_json::Value::Null => None,
        _ => return Err(()),
    };
    let (cmd, topic, interval, month) = match map {
        Some(map) => (
            scalar_field(map.get("cmd"))?,
            scalar_field(map.get("topic"))?,
            interval_field(map.get("interval_ms")),
            scalar_field(map.get("month"))?,
        ),
        None => (String::new(), String::new(), String::new(), String::new()),
    };
    let joined = format!("{cmd}|{topic}|{interval}|{month}");
    let (cmd, topic, interval, month) = bash_read_four(&joined);
    Ok(Fields {
        cmd,
        topic,
        interval,
        month,
    })
}

/// `IFS='|' read -r cmd topic interval month <<< "$joined"`.
///
/// Bash assigns the first three fields and gives the last variable the rest,
/// but a single trailing `|` that ends a one-field remainder is a field
/// terminator and not part of the value (`a|b|c|d|` reads `d`), while two or
/// more separators in the remainder stay (`a|b|c|d||` reads `d||`). Fuzzing
/// this against bash for all strings over `ab|` up to length 6 found no
/// difference.
fn bash_read_four(joined: &str) -> (String, String, String, String) {
    let mut rest = joined;
    let mut fields = Vec::with_capacity(4);
    for _ in 0..3 {
        match rest.find('|') {
            Some(index) => {
                fields.push(rest[..index].to_string());
                rest = &rest[index + 1..];
            }
            None => {
                fields.push(rest.to_string());
                rest = "";
            }
        }
    }
    let mut last = rest.to_string();
    if last.ends_with('|') && !last[..last.len() - 1].contains('|') {
        last.pop();
    }
    let mut fields = fields.into_iter();
    (
        fields.next().unwrap_or_default(),
        fields.next().unwrap_or_default(),
        fields.next().unwrap_or_default(),
        last,
    )
}

/// jq reads a stream of values and stops at the first bad one; the shell's
/// `read` then used the first output line. Parsing the whole stream keeps both
/// behaviours.
fn parse_first_value(line: &str) -> Result<Option<serde_json::Value>, ()> {
    let mut stream = serde_json::Deserializer::from_str(line).into_iter::<serde_json::Value>();
    let Some(first) = stream.next() else {
        return Ok(None);
    };
    let first = first.map_err(|_| ())?;
    for value in stream {
        value.map_err(|_| ())?;
    }
    Ok(Some(first))
}

/// `// ""` treats null and false as missing; an object or array as
/// `cmd`/`topic`/`month` made jq's `join` fail, which was a bad command line.
fn scalar_field(value: Option<&serde_json::Value>) -> Result<String, ()> {
    match value {
        None | Some(serde_json::Value::Null) | Some(serde_json::Value::Bool(false)) => {
            Ok(String::new())
        }
        Some(serde_json::Value::Bool(true)) => Ok("true".to_string()),
        Some(serde_json::Value::String(string)) => Ok(string.clone()),
        Some(serde_json::Value::Number(number)) => Ok(number_text(number)),
        Some(_) => Err(()),
    }
}

/// `(.interval_ms // "" | tostring)`: any JSON value became text, so an object
/// or array became its compact JSON form and then failed the digit check.
fn interval_field(value: Option<&serde_json::Value>) -> String {
    match value {
        None | Some(serde_json::Value::Null) | Some(serde_json::Value::Bool(false)) => {
            String::new()
        }
        Some(serde_json::Value::Bool(true)) => "true".to_string(),
        Some(serde_json::Value::String(string)) => string.clone(),
        Some(serde_json::Value::Number(number)) => number_text(number),
        Some(other) => serde_json::to_string(other).unwrap_or_default(),
    }
}

/// jq renders integers without a fraction and keeps a decimal point for floats
/// (`100.0` stays `100.0`), which makes a float fail the shell's digit check.
fn number_text(number: &serde_json::Number) -> String {
    if let Some(integer) = number.as_i64() {
        integer.to_string()
    } else if let Some(unsigned) = number.as_u64() {
        unsigned.to_string()
    } else {
        number.to_string()
    }
}

/// The shell's `case '' | *[!0-9]*)` for a non-empty value plus the
/// `100..3600000` range. The u128 parse cannot overflow into a false range
/// error: anything too large for it is above 3.6 million anyway.
fn parse_interval(value: &str) -> Option<u64> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    match value.parse::<u128>() {
        Ok(interval) if (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&interval) => {
            Some(interval as u64)
        }
        _ => None,
    }
}

/// The shell had one message for a non-integer value and one for the range;
/// `parse_interval` returning `None` needs the digit test again to pick it.
fn interval_error(value: &str) -> String {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        "interval_ms must be an integer".to_string()
    } else {
        "interval_ms must be 100..3600000".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session() -> Session {
        Session::new(300_000, Month::parse("2026-11").expect("month"))
    }

    fn run(session: &mut Session, lines: &[&str], now_ms: u64) -> (Vec<String>, Control) {
        let mut output = Vec::new();
        let mut control = Control::Continue;
        for line in lines {
            control = session
                .handle_line(line, &mut output)
                .expect("write to vec");
            if control == Control::Stop {
                break;
            }
            if session.due(now_ms) {
                session.advance(now_ms);
            }
        }
        let text = String::from_utf8(output).expect("utf8");
        (text.lines().map(|line| line.to_string()).collect(), control)
    }

    #[test]
    fn handshake_is_the_frozen_line() {
        assert_eq!(
            HANDSHAKE,
            "{\"ok\":true,\"worker\":\"calendar\",\"version\":1,\"topics\":[\"calendar\"]}"
        );
    }

    #[test]
    fn bad_lines_are_errors_like_the_shell() {
        let mut session = session();
        let (lines, control) = run(
            &mut session,
            &[
                "not json",
                "   ",
                "{}",
                "{} {}",
                "{",
                "null",
                "[]",
                "123",
                "\"text\"",
                r#"{"cmd":"bogus"}"#,
                r#"{"cmd":0}"#,
                r#"{"cmd":false}"#,
            ],
            1_000,
        );
        assert_eq!(control, Control::Continue);
        assert_eq!(
            lines,
            vec![
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: bogus"}"#,
                r#"{"ok":false,"err":"unknown cmd: 0"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
            ]
        );
    }

    #[test]
    fn subscribe_errors_match_the_shell_exactly() {
        let mut session = session();
        let (lines, _) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"calendar2"}"#,
                r#"{"cmd":"unsubscribe","topic":"calendar2"}"#,
                r#"{"cmd":"subscribe","topic":"calendar","interval_ms":50}"#,
                r#"{"cmd":"subscribe","topic":"calendar","interval_ms":3600001}"#,
                r#"{"cmd":"subscribe","topic":"calendar","interval_ms":"x"}"#,
                r#"{"cmd":"subscribe","topic":"calendar","interval_ms":100.0}"#,
                r#"{"cmd":"set"}"#,
                r#"{"cmd":"set","interval_ms":"x"}"#,
                r#"{"cmd":"set","interval_ms":50}"#,
                r#"{"cmd":"set","interval_ms":null}"#,
            ],
            1_000,
        );
        assert_eq!(
            lines,
            vec![
                r#"{"ok":false,"err":"unknown topic: calendar2"}"#,
                r#"{"ok":false,"err":"unknown topic: calendar2"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"set needs interval_ms or month"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"set needs interval_ms or month"}"#,
            ]
        );
    }

    #[test]
    fn a_pipe_in_a_field_shifts_the_shell_fields() {
        // jq joins the fields with `|`; bash's read then sees
        // `subscribe|calendar|x||`, where `x` lands in interval and the
        // trailing separator is a terminator. The shell answered exactly this.
        let mut session = session();
        let (lines, _) = run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"calendar|x"}"#],
            1_000,
        );
        assert_eq!(
            lines,
            vec![r#"{"ok":false,"err":"interval_ms must be an integer"}"#]
        );
    }

    #[test]
    fn bash_read_four_matches_the_observed_read() {
        for (joined, expected) in [
            ("subscribe|calendar|x||", ("subscribe", "calendar", "x", "")),
            ("a|b|c|d", ("a", "b", "c", "d")),
            ("a|b|c|d|", ("a", "b", "c", "d")),
            ("a|b|c|d||", ("a", "b", "c", "d||")),
            ("a|b|c||", ("a", "b", "c", "")),
            ("a|b|c|||", ("a", "b", "c", "||")),
            ("a|b|c||d", ("a", "b", "c", "|d")),
            ("|a|b|c", ("", "a", "b", "c")),
            ("", ("", "", "", "")),
            ("a|b", ("a", "b", "", "")),
        ] {
            let (a, b, c, d) = bash_read_four(joined);
            assert_eq!(
                (a.as_str(), b.as_str(), c.as_str(), d.as_str()),
                expected,
                "{joined}"
            );
        }
    }

    #[test]
    fn month_navigation_applies_first_and_reschedules() {
        let mut session = session();
        let (lines, _) = run(
            &mut session,
            &[
                r#"{"cmd":"sample","month":"2026-12"}"#,
                r#"{"cmd":"bogus","month":"2026-10"}"#,
                r#"{"cmd":"sample","month":"2026-13"}"#,
                r#"{"cmd":"sample","month":"2026-11-15"}"#,
            ],
            1_000,
        );
        assert_eq!(
            lines,
            vec![
                r#"{"ok":true,"ack":"sample"}"#,
                r#"{"ok":false,"err":"unknown cmd: bogus"}"#,
                r#"{"ok":false,"err":"bad month: 2026-13"}"#,
                r#"{"ok":true,"ack":"sample"}"#,
            ]
        );
        assert_eq!(session.month().name(), "2026-11");
        // The last valid month zeroed the schedule, and this test's helper
        // advanced it again; the failed month in between never touched it.
        assert!(!session.due(1_000));
        assert!(session.due(301_000));
    }

    #[test]
    fn set_with_only_a_month_acks() {
        let mut session = session();
        let (lines, _) = run(&mut session, &[r#"{"cmd":"set","month":"2026-10"}"#], 1_000);
        assert_eq!(lines, vec![r#"{"ok":true,"ack":"set"}"#]);
        assert_eq!(session.month().name(), "2026-10");
    }

    #[test]
    fn subscribe_uses_the_current_or_default_cadence() {
        let mut session = session();
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"calendar","interval_ms":250}"#],
            1_000,
        );
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"calendar"}"#],
            1_000,
        );
        assert_eq!(session.subscription.expect("subscribed").interval_ms, 250);
        run(
            &mut session,
            &[r#"{"cmd":"unsubscribe","topic":"calendar"}"#],
            1_000,
        );
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"calendar"}"#],
            1_000,
        );
        assert_eq!(
            session.subscription.expect("subscribed").interval_ms,
            300_000
        );
    }

    #[test]
    fn set_does_not_reschedule_but_sample_does() {
        let mut session = session();
        session.advance(1_000); // next = 301_000
        run(&mut session, &[r#"{"cmd":"set","interval_ms":100}"#], 2_000);
        assert!(!session.due(2_000), "set leaves next alone");
        assert!(session.due(301_000));
        let mut output = Vec::new();
        session
            .handle_line(r#"{"cmd":"sample"}"#, &mut output)
            .expect("sample");
        assert!(session.due(3_000), "sample makes the topic due now");
    }

    #[test]
    fn stop_acks_and_stops() {
        let mut session = session();
        let (lines, control) = run(
            &mut session,
            &[r#"{"cmd":"stop"}"#, r#"{"cmd":"sample"}"#],
            1_000,
        );
        assert_eq!(control, Control::Stop);
        assert_eq!(lines, vec![r#"{"ok":true,"ack":"stop"}"#]);
    }

    #[test]
    fn the_start_error_shape_is_the_frozen_one() {
        assert_eq!(
            start_error("khal not installed"),
            r#"{"ok":false,"worker":"calendar","err":"khal not installed"}"#
        );
    }

    #[test]
    fn sample_lines_have_the_shell_shape() {
        let mut output = Vec::new();
        write_sample(&mut output, 1_730_000_000_123, r#"{"month":"2026-11"}"#).expect("sample");
        write_sample_error(&mut output, 1_730_000_000_123, "boom \"quoted\"").expect("error");
        let text = String::from_utf8(output).expect("utf8");
        assert_eq!(
            text,
            concat!(
                "{\"ok\":true,\"worker\":\"calendar\",\"topic\":\"calendar\",",
                "\"t\":1730000000123,\"data\":{\"month\":\"2026-11\"}}\n",
                "{\"ok\":false,\"worker\":\"calendar\",\"err\":\"boom \\\"quoted\\\"\",",
                "\"t\":1730000000123}\n",
            )
        );
    }

    #[test]
    fn number_fields_render_like_jq_tostring() {
        assert_eq!(interval_field(Some(&serde_json::json!(100))), "100");
        assert_eq!(interval_field(Some(&serde_json::json!(100.0))), "100.0");
        assert_eq!(interval_field(Some(&serde_json::json!(true))), "true");
        assert_eq!(
            interval_field(Some(&serde_json::json!({"a": 1}))),
            "{\"a\":1}"
        );
        assert_eq!(interval_field(None), "");
    }
}
