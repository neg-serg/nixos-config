//! The §7 helper-worker protocol for `kbdlayout`.
//!
//! One JSON object per stdin line, one line of output per response. The
//! command set is INTERFACES.md §7 plus the domain command `switch` (and the
//! plain `switch …` wire line the Quickshell capsule used); the `layout` topic
//! is auto-subscribed at `--interval-ms`. Error samples keep the worker alive;
//! a failed `switch` is an error sample, a bad command is an error line.

use std::io::{self, Write};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::cli::{is_uint, MAX_INTERVAL_MS, MIN_INTERVAL_MS};
use crate::hypr::Hyprctl;
use crate::sample;

pub const WORKER: &str = "kbdlayout";
pub const TOPIC: &str = "layout";
/// The frozen handshake line (INTERFACES.md §7).
pub const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"kbdlayout\",\"version\":1,\"topics\":[\"layout\"]}";

/// Milliseconds since the epoch, like the shell's `$EPOCHREALTIME` math.
pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

/// Write one protocol line and flush: a scene reads line by line, never after
/// the worker exits.
pub fn write_line(out: &mut impl Write, line: &str) -> io::Result<()> {
    out.write_all(line.as_bytes())?;
    out.write_all(b"\n")?;
    out.flush()
}

/// A worker that cannot start answers in the protocol shape (no handshake,
/// no `t`) and exits non-zero.
pub fn write_start_error(message: &str, out: &mut impl Write) -> io::Result<()> {
    write_line(
        out,
        &format!(
            "{{\"ok\":false,\"worker\":\"{WORKER}\",\"err\":{}}}",
            sample::quote(message)
        ),
    )
}

/// An error sample: the worker stays alive and the scene shows `err`.
pub fn write_error_sample(message: &str, out: &mut impl Write) -> io::Result<()> {
    write_line(out, &error_sample_line(message, now_ms()))
}

fn error_sample_line(message: &str, t: u64) -> String {
    format!(
        "{{\"ok\":false,\"worker\":\"{WORKER}\",\"err\":{},\"t\":{t}}}",
        sample::quote(message)
    )
}

fn json_error(message: &str) -> String {
    format!("{{\"ok\":false,\"err\":{}}}", sample::quote(message))
}

fn ack(command: &str) -> String {
    format!("{{\"ok\":true,\"ack\":\"{command}\"}}")
}

fn sample_line(t: u64, data: &str) -> String {
    format!(
        "{{\"ok\":true,\"worker\":\"{WORKER}\",\"topic\":\"{TOPIC}\",\"t\":{t},\"data\":{data}}}"
    )
}

/// `(field // "") | tostring`: null, missing and `false` are the empty string;
/// everything else keeps its JSON form (`true` is the string `true`, numbers
/// and containers print compactly).
fn field_text(value: &Value, key: &str) -> String {
    match value.get(key) {
        None | Some(Value::Null) | Some(Value::Bool(false)) => String::new(),
        Some(Value::String(text)) => text.clone(),
        Some(other) => other.to_string(),
    }
}

/// `((.interval_ms // "") | tostring)`.
fn interval_text(value: &Value) -> String {
    match value.get("interval_ms") {
        None | Some(Value::Null) | Some(Value::Bool(false)) => String::new(),
        Some(Value::String(text)) => text.clone(),
        // A JSON number that is not an integer literal (100.0, 1e3) prints
        // with '.' or an exponent, so it never passes the digit check. A
        // number that fits in 64 bits prints as plain decimal digits.
        Some(Value::Number(number)) => number.to_string(),
        Some(other) => other.to_string(),
    }
}

/// Protocol cadence validation. The shell checked digits, then the
/// `100..60000` range with `test`; a digits string past the 64-bit range made
/// `test` fail, both comparisons were false, and the value was accepted, so
/// this saturates instead of inventing an error the shell did not print.
fn protocol_interval(text: &str) -> Result<u64, &'static str> {
    if !is_uint(text) {
        return Err("interval_ms must be an integer");
    }
    let Ok(interval) = text.parse::<u64>() else {
        return Ok(u64::MAX);
    };
    if !(MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&interval) {
        return Err("interval_ms must be 100..60000");
    }
    Ok(interval)
}

#[derive(Debug, PartialEq, Eq)]
pub enum Control {
    Continue,
    Stop,
}

struct Subscription {
    interval_ms: u64,
    next_ms: u64,
}

/// Worker state: the auto-subscription, the last emitted `data` object (the
/// change detector for socket events) and the compositor handle.
pub struct Session {
    hyprctl: Hyprctl,
    leds: PathBuf,
    default_interval_ms: u64,
    subscription: Option<Subscription>,
    last_status: String,
}

impl Session {
    pub fn new(hyprctl: Hyprctl, interval_ms: u64, leds: PathBuf) -> Self {
        Self {
            hyprctl,
            leds,
            default_interval_ms: interval_ms,
            // The shell subscribed `layout` before anything else, so a scene
            // that only reads lines still gets a heartbeat.
            subscription: Some(Subscription {
                interval_ms,
                next_ms: 0,
            }),
            last_status: String::new(),
        }
    }

    pub fn handle_line(&mut self, line: &str, out: &mut impl Write) -> io::Result<Control> {
        // Anything that does not start with `{` was the plain switch line in
        // the shell; a JSON array is not a command object either.
        if !line.starts_with('{') {
            return self.handle_plain(line, out);
        }
        match serde_json::from_str::<Value>(line) {
            Ok(value) => self.handle_json(&value, out),
            Err(_) => {
                write_line(out, &json_error("bad command line"))?;
                Ok(Control::Continue)
            }
        }
    }

    fn handle_json(&mut self, value: &Value, out: &mut impl Write) -> io::Result<Control> {
        let command = field_text(value, "cmd");
        match command.as_str() {
            "subscribe" => self.subscribe(value, out),
            "unsubscribe" => self.unsubscribe(value, out),
            "set" => self.set(value, out),
            "sample" => {
                if let Some(subscription) = self.subscription.as_mut() {
                    subscription.next_ms = 0;
                }
                write_line(out, &ack("sample"))?;
                self.emit_sample(out)?;
                Ok(Control::Continue)
            }
            "switch" => {
                let device = default_field(value, "device", "current");
                let direction = default_field(value, "direction", "next");
                write_line(out, &ack("switch"))?;
                self.switch_words(&device, &direction, out)?;
                Ok(Control::Continue)
            }
            "stop" => {
                write_line(out, &ack("stop"))?;
                Ok(Control::Stop)
            }
            _ => {
                write_line(out, &json_error(&format!("unknown cmd: {command}")))?;
                Ok(Control::Continue)
            }
        }
    }

    fn subscribe(&mut self, value: &Value, out: &mut impl Write) -> io::Result<Control> {
        let topic = field_text(value, "topic");
        if topic != TOPIC {
            write_line(out, &json_error(&format!("unknown topic: {topic}")))?;
            return Ok(Control::Continue);
        }
        let interval = interval_text(value);
        let interval_ms = if interval.is_empty() {
            self.subscription
                .as_ref()
                .map(|subscription| subscription.interval_ms)
                .unwrap_or(self.default_interval_ms)
        } else {
            match protocol_interval(&interval) {
                Ok(interval_ms) => interval_ms,
                Err(message) => {
                    write_line(out, &json_error(message))?;
                    return Ok(Control::Continue);
                }
            }
        };
        self.subscription = Some(Subscription {
            interval_ms,
            next_ms: 0,
        });
        write_line(out, &ack("subscribe"))?;
        Ok(Control::Continue)
    }

    fn unsubscribe(&mut self, value: &Value, out: &mut impl Write) -> io::Result<Control> {
        let topic = field_text(value, "topic");
        if topic != TOPIC {
            write_line(out, &json_error(&format!("unknown topic: {topic}")))?;
            return Ok(Control::Continue);
        }
        self.subscription = None;
        write_line(out, &ack("unsubscribe"))?;
        Ok(Control::Continue)
    }

    fn set(&mut self, value: &Value, out: &mut impl Write) -> io::Result<Control> {
        let interval = interval_text(value);
        if interval.is_empty() {
            write_line(out, &json_error("set needs interval_ms"))?;
            return Ok(Control::Continue);
        }
        match protocol_interval(&interval) {
            Ok(interval_ms) => {
                if let Some(subscription) = self.subscription.as_mut() {
                    subscription.interval_ms = interval_ms;
                }
                write_line(out, &ack("set"))?;
            }
            Err(message) => write_line(out, &json_error(message))?,
        }
        Ok(Control::Continue)
    }

    fn handle_plain(&mut self, line: &str, out: &mut impl Write) -> io::Result<Control> {
        let mut words = line.split_whitespace();
        let command = words.next().unwrap_or("");
        if command != "switch" {
            write_line(out, &json_error(&format!("unknown command: {line}")))?;
            return Ok(Control::Continue);
        }
        let device = words.next().unwrap_or("current");
        let direction = words.next().unwrap_or("next");
        write_line(out, &ack("switch"))?;
        self.switch_words(device, direction, out)?;
        Ok(Control::Continue)
    }

    /// Shared by the JSON `switch` command and the plain `switch …` line:
    /// validate the direction, ask the compositor, then sample unconditionally
    /// (the layout may be unchanged, but the scene asked for the switch).
    fn switch_words(
        &mut self,
        device: &str,
        direction: &str,
        out: &mut impl Write,
    ) -> io::Result<()> {
        let direction = match direction {
            "" | "next" => "next",
            "prev" => "prev",
            other => {
                write_line(
                    out,
                    &json_error(&format!("switch: unknown direction '{other}' (next|prev)")),
                )?;
                return Ok(());
            }
        };
        match self.hyprctl.switch_layout(device, direction) {
            Err(message) => write_line(out, &error_sample_line(&message, now_ms())),
            Ok(()) => self.emit_sample(out),
        }
    }

    /// Unconditional sample (start, cadence, after a switch).
    pub fn emit_sample(&mut self, out: &mut impl Write) -> io::Result<()> {
        let t = now_ms();
        match self.hyprctl.build_status(&self.leds) {
            Err(message) => write_line(out, &error_sample_line(&message, now_ms())),
            Ok(data) => {
                self.last_status = data;
                write_line(out, &sample_line(t, &self.last_status))
            }
        }
    }

    /// Sample only when the status changed (event bursts repeat state).
    pub fn emit_changed_sample(&mut self, out: &mut impl Write) -> io::Result<()> {
        match self.hyprctl.build_status(&self.leds) {
            Err(message) => write_line(out, &error_sample_line(&message, now_ms())),
            Ok(data) => {
                if data == self.last_status {
                    return Ok(());
                }
                let t = now_ms();
                self.last_status = data;
                write_line(out, &sample_line(t, &self.last_status))
            }
        }
    }

    /// Emit the sample of every topic that is due, pushing its next deadline.
    pub fn emit_due_samples(&mut self, now: u64, out: &mut impl Write) -> io::Result<()> {
        let due = match &self.subscription {
            Some(subscription) => subscription.next_ms <= now,
            None => false,
        };
        if !due {
            return Ok(());
        }
        if let Some(subscription) = self.subscription.as_mut() {
            subscription.next_ms = now.saturating_add(subscription.interval_ms);
        }
        self.emit_sample(out)
    }
}

fn default_field(value: &Value, key: &str, default: &str) -> String {
    let field = field_text(value, key);
    if field.is_empty() {
        default.to_string()
    } else {
        field
    }
}
