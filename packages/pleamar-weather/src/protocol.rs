//! The §7 protocol: handshake, command lines, acknowledgements, sample lines.
//!
//! The shell's lines are frozen; this module reproduces them byte for byte.
//! Command parsing repeats the shell's jq round trip
//! (`[.cmd // "", .topic // "", (.interval_ms // "" | tostring)] | join("|")`
//! followed by `IFS='|' read -r cmd topic interval`), which is also why a `|`
//! inside a topic shifts the fields — that quirk is kept because a scene could
//! observe the reply.

use std::io::{self, Write};

use crate::json;

pub const WORKER: &str = "weather";

pub const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"weather\",\"version\":1,\"topics\":[\"weather\"]}";

pub const TOPIC: &str = "weather";

const MIN_INTERVAL_MS: u64 = 100;
const MAX_INTERVAL_MS: u64 = 3_600_000;

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
}

impl Session {
    /// The shell subscribed `weather` before the handshake with `next=0`, so
    /// the first sample is due on the first loop pass (not one interval in).
    pub fn new(interval_ms: u64) -> Self {
        Self {
            default_interval_ms: interval_ms,
            subscription: Some(Subscription {
                interval_ms,
                next_ms: 0,
            }),
        }
    }

    #[cfg(test)]
    pub fn interval_ms(&self) -> Option<u64> {
        self.subscription
            .map(|subscription| subscription.interval_ms)
    }

    pub fn handle_line<W: Write>(&mut self, line: &str, out: &mut W) -> io::Result<Control> {
        let fields = match parse_fields(line) {
            Ok(fields) => fields,
            Err(()) => {
                write_error(out, "bad command line")?;
                return Ok(Control::Continue);
            }
        };

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
                // The shell's `case '' | *[!0-9]*)`: an empty value was filled
                // above, so only non-digits are an error here.
                if !is_digits(&interval_text) {
                    write_error(out, "interval_ms must be an integer")?;
                    return Ok(Control::Continue);
                }
                let Ok(interval_ms) = interval_text.parse::<u64>() else {
                    write_error(out, "interval_ms must be 100..3600000")?;
                    return Ok(Control::Continue);
                };
                if !(MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&interval_ms) {
                    write_error(out, "interval_ms must be 100..3600000")?;
                    return Ok(Control::Continue);
                }
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
                if fields.interval.is_empty() {
                    write_error(out, "set needs interval_ms")?;
                    return Ok(Control::Continue);
                }
                if !is_digits(&fields.interval) {
                    write_error(out, "interval_ms must be an integer")?;
                    return Ok(Control::Continue);
                }
                let Ok(interval_ms) = fields.interval.parse::<u64>() else {
                    write_error(out, "interval_ms must be 100..3600000")?;
                    return Ok(Control::Continue);
                };
                if !(MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&interval_ms) {
                    write_error(out, "interval_ms must be 100..3600000")?;
                    return Ok(Control::Continue);
                }
                // `set` changes the cadence only; `next` stays where it was.
                if let Some(subscription) = &mut self.subscription {
                    subscription.interval_ms = interval_ms;
                }
                write_ack(out, "set")?;
            }
            "sample" => {
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

/// The line a worker that cannot start printed before exiting 1. The weather
/// worker has no such condition any more — the shell's checks were `jq not
/// installed` / `curl not installed`, and both are compiled in — but the
/// frozen shape stays here, covered by a test, for the README's description of
/// a worker that cannot start.
#[cfg(test)]
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

/// jq's jq-stream + `join("|")` + bash's `read`: `None` means "no JSON value
/// at all" (a whitespace-only line), `Err` means jq failed on the line.
struct Fields {
    cmd: String,
    topic: String,
    interval: String,
}

fn parse_fields(line: &str) -> Result<Fields, ()> {
    let Some(value) = parse_first_value(line)? else {
        return Ok(Fields {
            cmd: String::new(),
            topic: String::new(),
            interval: String::new(),
        });
    };
    let map = match &value {
        serde_json::Value::Object(map) => Some(map),
        serde_json::Value::Null => None,
        _ => return Err(()),
    };
    let (cmd, topic, interval) = match map {
        Some(map) => (
            scalar_field(map.get("cmd"))?,
            scalar_field(map.get("topic"))?,
            interval_field(map.get("interval_ms")),
        ),
        None => (String::new(), String::new(), String::new()),
    };
    let joined = format!("{cmd}|{topic}|{interval}");
    let mut parts = joined.splitn(3, '|');
    let cmd = parts.next().unwrap_or_default().to_string();
    let topic = parts.next().unwrap_or_default().to_string();
    let interval = parts.next().unwrap_or_default().to_string();
    Ok(Fields {
        cmd,
        topic,
        interval,
    })
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
/// `cmd`/`topic` made jq's `join` fail, which was a bad command line.
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

fn is_digits(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

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
            "{\"ok\":true,\"worker\":\"weather\",\"version\":1,\"topics\":[\"weather\"]}"
        );
    }

    #[test]
    fn bad_lines_and_unknown_commands_are_answered() {
        let mut session = Session::new(600_000);
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
    fn subscribe_unsubscribe_and_set_acknowledge_like_the_shell() {
        let mut session = Session::new(600_000);
        let (lines, control) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"weather","interval_ms":1000}"#,
                r#"{"cmd":"set","interval_ms":250}"#,
                r#"{"cmd":"unsubscribe","topic":"weather"}"#,
                r#"{"cmd":"set","interval_ms":300}"#,
            ],
            1_000,
        );
        assert_eq!(control, Control::Continue);
        assert_eq!(
            lines,
            vec![
                r#"{"ok":true,"ack":"subscribe"}"#,
                r#"{"ok":true,"ack":"set"}"#,
                r#"{"ok":true,"ack":"unsubscribe"}"#,
                r#"{"ok":true,"ack":"set"}"#,
            ]
        );
        assert_eq!(session.interval_ms(), None, "unsubscribed");
    }

    #[test]
    fn errors_match_the_shell_exactly() {
        let mut session = Session::new(600_000);
        let (lines, _) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"weather2"}"#,
                r#"{"cmd":"unsubscribe","topic":"weather2"}"#,
                r#"{"cmd":"subscribe","topic":"weather","interval_ms":50}"#,
                r#"{"cmd":"subscribe","topic":"weather","interval_ms":3600001}"#,
                r#"{"cmd":"subscribe","topic":"weather","interval_ms":"x"}"#,
                r#"{"cmd":"subscribe","topic":"weather","interval_ms":100.0}"#,
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
                r#"{"ok":false,"err":"unknown topic: weather2"}"#,
                r#"{"ok":false,"err":"unknown topic: weather2"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"set needs interval_ms"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#,
                r#"{"ok":false,"err":"set needs interval_ms"}"#,
            ]
        );
    }

    #[test]
    fn subscribe_without_interval_uses_the_current_or_default_cadence() {
        let mut session = Session::new(600_000);
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"weather","interval_ms":250}"#],
            1_000,
        );
        assert_eq!(session.interval_ms(), Some(250));
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"weather"}"#],
            1_000,
        );
        assert_eq!(session.interval_ms(), Some(250));
        run(
            &mut session,
            &[r#"{"cmd":"unsubscribe","topic":"weather"}"#],
            1_000,
        );
        run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"weather"}"#],
            1_000,
        );
        assert_eq!(session.interval_ms(), Some(600_000));
    }

    #[test]
    fn auto_subscription_is_due_immediately() {
        let mut session = Session::new(600_000);
        assert!(session.due(0));
        assert!(session.due(1_700_000_000_000));
        session.advance(1_000);
        assert!(!session.due(1_000));
        assert!(session.due(601_000));
    }

    #[test]
    fn set_does_not_reschedule_but_sample_does() {
        let mut session = Session::new(600_000);
        session.advance(1_000); // next = 601_000
        run(&mut session, &[r#"{"cmd":"set","interval_ms":100}"#], 2_000);
        assert!(!session.due(2_000), "set leaves next alone");
        assert!(session.due(601_000));
        let mut output = Vec::new();
        session
            .handle_line(r#"{"cmd":"sample"}"#, &mut output)
            .expect("sample");
        assert!(session.due(3_000), "sample makes the topic due now");
    }

    #[test]
    fn stop_acks_and_stops() {
        let mut session = Session::new(600_000);
        let (lines, control) = run(
            &mut session,
            &[r#"{"cmd":"stop"}"#, r#"{"cmd":"sample"}"#],
            1_000,
        );
        assert_eq!(control, Control::Stop);
        assert_eq!(lines, vec![r#"{"ok":true,"ack":"stop"}"#]);
    }

    #[test]
    fn pipe_in_a_field_shifts_the_shell_fields() {
        let mut session = Session::new(600_000);
        let (lines, _) = run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"weather|x"}"#],
            1_000,
        );
        assert_eq!(
            lines,
            vec![r#"{"ok":false,"err":"interval_ms must be an integer"}"#]
        );
    }

    #[test]
    fn a_worker_that_cannot_start_has_the_frozen_shape() {
        assert_eq!(
            start_error("jq not installed"),
            r#"{"ok":false,"worker":"weather","err":"jq not installed"}"#
        );
    }

    #[test]
    fn sample_and_error_lines_are_the_frozen_shape() {
        let mut output = Vec::new();
        write_sample(&mut output, 1_730_000_000_123, r#"{"city":"x"}"#).expect("sample");
        write_sample_error(&mut output, 1_730_000_000_123, "boom \"quoted\"").expect("error");
        let text = String::from_utf8(output).expect("utf8");
        assert_eq!(
            text,
            concat!(
                "{\"ok\":true,\"worker\":\"weather\",\"topic\":\"weather\",",
                "\"t\":1730000000123,\"data\":{\"city\":\"x\"}}\n",
                "{\"ok\":false,\"worker\":\"weather\",\"err\":\"boom \\\"quoted\\\"\",",
                "\"t\":1730000000123}\n",
            )
        );
    }

    #[test]
    fn number_fields_render_like_jq_tostring() {
        // jq preserves the literal of a float and renders integers plainly.
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
