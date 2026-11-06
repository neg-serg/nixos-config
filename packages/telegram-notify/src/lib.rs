//! Shared pieces of the daily Telegram reminders.
//!
//! Both reminders talk to the Bot API through `curl`, because `api.telegram.org`
//! is only reachable through the sing-box socks proxy on this host and the repo
//! already ships a curl-based sender. The bot token lives in the request URL,
//! and `/proc/<pid>/cmdline` is world-readable, so the URL never reaches argv:
//! it is handed to `curl -K -` on stdin instead.
//!
//! The module is shared by `calendar.rs` and `pill.rs` through `#[path]`
//! includes, which keeps the crate a two-binary package without a library
//! target.

#![allow(dead_code)]

use std::io::Write;
use std::process::{Command, Stdio};

pub const DEFAULT_CURL: &str = "/run/current-system/sw/bin/curl";

/// Curl config that carries only the URL.
///
/// Quotes and backslashes are escaped for curl's config parser; the token
/// charset itself is `[0-9A-Za-z_:-]`, so nothing else needs handling.
pub fn curl_url_config(url: &str) -> String {
    let escaped = url.replace('\\', "\\\\").replace('"', "\\\"");
    format!("url = \"{escaped}\"\n")
}

/// Today's date in local time as `YYYY-MM-DD`.
///
/// The units fire at a wall-clock time and the panel's pill state carries a
/// local date, so the reminders must agree with local time, not with UTC. The
/// date comes from `date +%F` (coreutils is always on the system path here) and
/// falls back to the UTC computation when that is unavailable.
/// `TELEGRAM_REMINDER_TODAY` overrides it, which is what the tests use.
pub fn local_today() -> String {
    if let Ok(value) = std::env::var("TELEGRAM_REMINDER_TODAY") {
        let value = value.trim().to_string();
        if !value.is_empty() {
            return value;
        }
    }
    for candidate in ["/run/current-system/sw/bin/date", "date"] {
        let Ok(output) = Command::new(candidate).arg("+%F").output() else {
            continue;
        };
        if !output.status.success() {
            continue;
        }
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if text.len() == 10 && text.split('-').count() == 3 {
            return text;
        }
    }
    utc_today()
}

/// Today's date as `YYYY-MM-DD` (UTC).
pub fn utc_today() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs() as i64)
        .unwrap_or(0);
    let (year, month, day) = civil_from_days(seconds.div_euclid(86_400));
    format!("{year:04}-{month:02}-{day:02}")
}

/// Howard Hinnant's `civil_from_days`.
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// `YYYY-MM-DD` plus one day, for the calendar range end.
pub fn tomorrow(today: &str) -> String {
    let parts: Vec<&str> = today.split('-').collect();
    if parts.len() != 3 {
        return today.to_string();
    }
    let (Ok(year), Ok(month), Ok(day)) = (
        parts[0].parse::<i64>(),
        parts[1].parse::<i64>(),
        parts[2].parse::<i64>(),
    ) else {
        return today.to_string();
    };
    let days = days_from_civil(year, month, day) + 1;
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}")
}

/// Howard Hinnant's `days_from_civil`.
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = if month > 2 { month - 3 } else { month + 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// `DD.MM.YYYY`, the format khal prints and expects.
pub fn khal_date(iso: &str) -> String {
    let parts: Vec<&str> = iso.split('-').collect();
    if parts.len() != 3 {
        return iso.to_string();
    }
    format!("{}.{}.{}", parts[2], parts[1], parts[0])
}

/// Post one message through the shared curl sender.
///
/// `sender` is an executable taking the message as its only argument (the
/// repo's `telegram-send` wrapper, which owns the retry/proxy policy).
pub fn send_via_sender(sender: &str, message: &str, timeout_seconds: u64) -> bool {
    let mut command = Command::new(sender);
    command.arg(message);
    run_with_timeout(command, timeout_seconds)
}

/// Post a message to the Bot API through curl, retrying like the Python
/// reminder did. Returns the parsed response body on success.
pub struct CurlPost<'a> {
    pub curl: &'a str,
    pub token: &'a str,
    pub chat_id: &'a str,
    pub text: &'a str,
    pub reply_markup: Option<&'a str>,
    pub proxy: Option<&'a str>,
    pub attempts: usize,
    pub pause_seconds: u64,
}

impl CurlPost<'_> {
    /// `Ok(body)` on a successful call, `Err(message)` after the last attempt.
    pub fn send(&self) -> Result<String, String> {
        let url = format!("https://api.telegram.org/bot{}/sendMessage", self.token);
        for attempt in 0..self.attempts {
            let mut command = Command::new(self.curl);
            command.arg("-s");
            if let Some(proxy) = self.proxy {
                command.args(["--proxy", proxy]);
            }
            command
                .args(["-K", "-"])
                .args(["--data-urlencode", &format!("chat_id={}", self.chat_id)])
                .args(["--data-urlencode", &format!("text={}", self.text)]);
            if let Some(markup) = self.reply_markup {
                command.args(["--data-urlencode", &format!("reply_markup={markup}")]);
            }
            command
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            let Ok(mut child) = command.spawn() else {
                return Err("cannot spawn curl".to_string());
            };
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(curl_url_config(&url).as_bytes());
            }
            let output = match child.wait_with_output() {
                Ok(output) => output,
                Err(exc) => return Err(format!("curl failed: {exc}")),
            };
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).to_string());
            }
            if attempt + 1 < self.attempts {
                std::thread::sleep(std::time::Duration::from_secs(self.pause_seconds));
            }
        }
        Err(format!(
            "could not deliver after {} attempts",
            self.attempts
        ))
    }
}

/// Run a command, giving up after `timeout_seconds`.
fn run_with_timeout(mut command: Command, timeout_seconds: u64) -> bool {
    command.stdout(Stdio::null()).stderr(Stdio::inherit());
    let Ok(mut child) = command.spawn() else {
        return false;
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(timeout_seconds);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => return status.success(),
            Ok(None) if std::time::Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return false;
            }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(50)),
            Err(_) => return false,
        }
    }
}

/// Compact JSON reader for `khal list --json` and curl responses.
pub mod json {
    #[derive(Debug, Clone, PartialEq)]
    pub enum Value {
        Null,
        Bool(bool),
        Number(f64),
        Str(String),
        Array(Vec<Value>),
        Object(Vec<(String, Value)>),
    }

    impl Value {
        pub fn get(&self, key: &str) -> Option<&Value> {
            match self {
                Value::Object(entries) => entries
                    .iter()
                    .find(|(name, _)| name == key)
                    .map(|(_, value)| value),
                _ => None,
            }
        }

        pub fn as_str(&self) -> Option<&str> {
            match self {
                Value::Str(text) => Some(text),
                _ => None,
            }
        }

        pub fn as_i64(&self) -> Option<i64> {
            match self {
                Value::Number(number) => Some(*number as i64),
                _ => None,
            }
        }

        pub fn as_bool(&self) -> Option<bool> {
            match self {
                Value::Bool(flag) => Some(*flag),
                _ => None,
            }
        }

        pub fn as_array(&self) -> Option<&[Value]> {
            match self {
                Value::Array(items) => Some(items),
                _ => None,
            }
        }
    }

    impl Value {
        /// Serialize with the layout the Python scripts used: `indent` of
        /// `Some(n)` pretty-prints, `None` writes one line.
        pub fn dump(&self, indent: Option<usize>) -> String {
            let mut out = String::new();
            self.write(&mut out, indent, 0);
            out
        }

        fn write(&self, out: &mut String, indent: Option<usize>, level: usize) {
            match self {
                Value::Null => out.push_str("null"),
                Value::Bool(flag) => out.push_str(if *flag { "true" } else { "false" }),
                Value::Number(number) => {
                    if number.fract() == 0.0 && number.abs() < 1e15 {
                        out.push_str(&format!("{}", *number as i64));
                    } else {
                        out.push_str(&format!("{number}"));
                    }
                }
                Value::Str(text) => write_json_string(out, text),
                Value::Array(items) => {
                    if items.is_empty() {
                        out.push_str("[]");
                        return;
                    }
                    out.push('[');
                    for (index, item) in items.iter().enumerate() {
                        if index > 0 {
                            out.push(',');
                            newline(out, indent, level + 1);
                        } else if indent.is_some() {
                            newline(out, indent, level + 1);
                        }
                        item.write(out, indent, level + 1);
                    }
                    close_indent(out, indent, level);
                    out.push(']');
                }
                Value::Object(entries) => {
                    if entries.is_empty() {
                        out.push_str("{}");
                        return;
                    }
                    out.push('{');
                    for (index, (key, value)) in entries.iter().enumerate() {
                        if index > 0 {
                            out.push(',');
                        }
                        if index > 0 || indent.is_some() {
                            newline(out, indent, level + 1);
                        }
                        write_json_string(out, key);
                        out.push_str(": ");
                        value.write(out, indent, level + 1);
                    }
                    close_indent(out, indent, level);
                    out.push('}');
                }
            }
        }
    }

    /// Separator before an item; compact output uses a single space.
    fn newline(out: &mut String, indent: Option<usize>, level: usize) {
        if indent.is_some() {
            out.push('\n');
            indent_spaces(out, indent, level);
        } else {
            out.push(' ');
        }
    }

    /// Indentation before a closing bracket, nothing in compact mode.
    fn close_indent(out: &mut String, indent: Option<usize>, level: usize) {
        if indent.is_some() {
            out.push('\n');
            indent_spaces(out, indent, level);
        }
    }

    fn indent_spaces(out: &mut String, indent: Option<usize>, level: usize) {
        if let Some(width) = indent {
            for _ in 0..width * level {
                out.push(' ');
            }
        }
    }

    /// Non-ASCII is escaped, matching `json.dumps`' default.
    fn write_json_string(out: &mut String, text: &str) {
        out.push('"');
        for ch in text.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
                // JSON `\u` escapes are UTF-16 code units, so an astral
                // character needs a surrogate pair. One `\u1f4ca` is invalid
                // JSON and would make a request body (e.g. a Telegram
                // question with an emoji) unparseable for llama-swap.
                ch if (ch as u32) > 0xffff => {
                    let code = ch as u32 - 0x10000;
                    let high = 0xd800 + (code >> 10);
                    let low = 0xdc00 + (code & 0x3ff);
                    out.push_str(&format!("\\u{high:04x}\\u{low:04x}"));
                }
                ch if (ch as u32) > 0x7e => out.push_str(&format!("\\u{:04x}", ch as u32)),
                ch => out.push(ch),
            }
        }
        out.push('"');
    }

    pub fn parse(text: &str) -> Option<Value> {
        let chars: Vec<char> = text.chars().collect();
        let mut parser = Parser { chars, pos: 0 };
        let value = parser.value()?;
        parser.skip_ws();
        if parser.pos != parser.chars.len() {
            return None;
        }
        Some(value)
    }

    struct Parser {
        chars: Vec<char>,
        pos: usize,
    }

    impl Parser {
        fn peek(&self) -> Option<char> {
            self.chars.get(self.pos).copied()
        }

        fn skip_ws(&mut self) {
            while matches!(self.peek(), Some(ch) if ch.is_whitespace()) {
                self.pos += 1;
            }
        }

        fn eat(&mut self, ch: char) -> bool {
            if self.peek() == Some(ch) {
                self.pos += 1;
                true
            } else {
                false
            }
        }

        fn value(&mut self) -> Option<Value> {
            self.skip_ws();
            match self.peek()? {
                '{' => self.object(),
                '[' => self.array(),
                '"' => self.string().map(Value::Str),
                't' => self.literal("true", Value::Bool(true)),
                'f' => self.literal("false", Value::Bool(false)),
                'n' => self.literal("null", Value::Null),
                _ => self.number(),
            }
        }

        fn literal(&mut self, text: &str, value: Value) -> Option<Value> {
            for expected in text.chars() {
                if self.peek()? != expected {
                    return None;
                }
                self.pos += 1;
            }
            Some(value)
        }

        fn object(&mut self) -> Option<Value> {
            self.pos += 1;
            let mut entries = Vec::new();
            self.skip_ws();
            if self.eat('}') {
                return Some(Value::Object(entries));
            }
            loop {
                self.skip_ws();
                let key = self.string()?;
                self.skip_ws();
                if !self.eat(':') {
                    return None;
                }
                entries.push((key, self.value()?));
                self.skip_ws();
                if self.eat(',') {
                    continue;
                }
                if self.eat('}') {
                    return Some(Value::Object(entries));
                }
                return None;
            }
        }

        fn array(&mut self) -> Option<Value> {
            self.pos += 1;
            let mut items = Vec::new();
            self.skip_ws();
            if self.eat(']') {
                return Some(Value::Array(items));
            }
            loop {
                items.push(self.value()?);
                self.skip_ws();
                if self.eat(',') {
                    continue;
                }
                if self.eat(']') {
                    return Some(Value::Array(items));
                }
                return None;
            }
        }

        fn string(&mut self) -> Option<String> {
            if !self.eat('"') {
                return None;
            }
            let mut out = String::new();
            loop {
                let ch = self.peek()?;
                self.pos += 1;
                match ch {
                    '"' => return Some(out),
                    '\\' => {
                        let escaped = self.peek()?;
                        self.pos += 1;
                        match escaped {
                            '"' => out.push('"'),
                            '\\' => out.push('\\'),
                            '/' => out.push('/'),
                            'n' => out.push('\n'),
                            't' => out.push('\t'),
                            'r' => out.push('\r'),
                            'u' => {
                                let mut code = String::new();
                                for _ in 0..4 {
                                    code.push(self.peek()?);
                                    self.pos += 1;
                                }
                                let value = u32::from_str_radix(&code, 16).ok()?;
                                out.push(char::from_u32(value).unwrap_or('\u{fffd}'));
                            }
                            other => out.push(other),
                        }
                    }
                    other => out.push(other),
                }
            }
        }

        fn number(&mut self) -> Option<Value> {
            let start = self.pos;
            if matches!(self.peek(), Some('-')) {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                self.pos += 1;
            }
            if matches!(self.peek(), Some('.')) {
                self.pos += 1;
                while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                    self.pos += 1;
                }
            }
            if self.pos == start {
                return None;
            }
            let text: String = self.chars[start..self.pos].iter().collect();
            text.parse::<f64>().ok().map(Value::Number)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn civil_dates_round_trip() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(civil_from_days(days_from_civil(2026, 11, 2)), (2026, 11, 2));
        assert_eq!(tomorrow("2026-11-02"), "2026-11-03");
        assert_eq!(tomorrow("2026-12-31"), "2027-01-01");
        assert_eq!(tomorrow("2024-02-28"), "2024-02-29");
        assert_eq!(khal_date("2026-11-02"), "02.11.2026");
    }

    #[test]
    fn json_writer_matches_the_python_layout() {
        let value = json::parse(r#"{"b": 1, "a": [true, null, "x"], "c": {}}"#).expect("json");
        assert_eq!(
            value.dump(Some(4)),
            "{\n    \"b\": 1,\n    \"a\": [\n        true,\n        null,\n        \"x\"\n    ],\n    \"c\": {}\n}"
        );
        assert_eq!(
            value.dump(None),
            r#"{"b": 1, "a": [true, null, "x"], "c": {}}"#
        );
        // Non-ASCII becomes \u escapes, like json.dumps' default.
        assert_eq!(json::Value::Str("✅".into()).dump(None), "\"\\u2705\"");
        // Astral characters become a UTF-16 surrogate pair.
        assert_eq!(
            json::Value::Str("📊".into()).dump(None),
            "\"\\ud83d\\udcca\""
        );
    }

    #[test]
    fn curl_config_escapes_quotes_and_backslashes() {
        assert_eq!(
            curl_url_config("https://x/bot1:a/sendMessage"),
            "url = \"https://x/bot1:a/sendMessage\"\n"
        );
        assert_eq!(curl_url_config("a\"b\\c"), "url = \"a\\\"b\\\\c\"\n");
    }
}
