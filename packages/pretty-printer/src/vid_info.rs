//! `vid-info` — one pretty line per video file, straight from ffprobe.
//!
//! Resolution, duration, size in MiB, overall bitrate, frame rate, audio sample
//! rate and audio bitrate, each in the bracketed `pretty-printer` format.
//!
//! Port of `packages/local-bin/scripts/vid-info.py`; the library it imported is
//! now the `lib.rs` next to this file, so the script needs no interpreter.

#[path = "lib.rs"]
mod lib;

use std::path::Path;
use std::process::{Command, Stdio};

/// Size units of the Python enum: 2 KiB, 3 MiB, 4 GiB, 5 TiB.
fn convert_unit(size: f64, unit: u32) -> f64 {
    match unit {
        2 => size / 1024.0,
        3 => size / (1024.0 * 1024.0),
        4 => size / (1024.0 * 1024.0 * 1024.0),
        5 => size / (1024.0 * 1024.0 * 1024.0 * 1024.0),
        _ => size,
    }
}

/// `datetime.timedelta(seconds=n)` as Python renders it.
fn timedelta(seconds: i64) -> String {
    let days = seconds / 86_400;
    let rest = seconds % 86_400;
    let hours = rest / 3600;
    let minutes = (rest % 3600) / 60;
    let secs = rest % 60;
    if days != 0 {
        format!(
            "{days} day{}, {hours}:{minutes:02}:{secs:02}",
            if days == 1 { "" } else { "s" }
        )
    } else {
        format!("{hours}:{minutes:02}:{secs:02}")
    }
}

fn number_field(value: &json::Value, key: &str) -> Option<f64> {
    match value.get(key)? {
        json::Value::Number(number) => Some(*number),
        json::Value::Str(text) => text.trim().parse().ok(),
        _ => None,
    }
}

fn media_info(filename: &str) {
    let output = match Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-show_format",
            "-show_streams",
            "-print_format",
            "json",
            filename,
        ])
        .stdin(Stdio::null())
        .output()
    {
        Ok(output) => output,
        Err(_) => {
            eprintln!("[vid-info] missing ffprobe in PATH");
            return;
        }
    };
    if !output.status.success() {
        eprintln!(
            "[vid-info] ffprobe failed for {filename}: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
        return;
    }
    let Some(document) = json::parse(&String::from_utf8_lossy(&output.stdout)) else {
        eprintln!("[vid-info] bad ffprobe JSON for {filename}");
        return;
    };
    let streams = match document.get("streams") {
        Some(json::Value::Array(items)) if !items.is_empty() => items.clone(),
        _ => return,
    };

    let mut out = String::new();
    let mut frame_rate = String::new();
    let mut audio_bitrate = String::new();
    let mut audio_sample_rate = String::new();
    for stream in &streams {
        let codec = stream.get("codec_type").and_then(json::Value::as_str);
        match codec {
            Some("video") => {
                if let (Some(width), Some(height)) = (
                    number_field(stream, "width"),
                    number_field(stream, "height"),
                ) {
                    out.push_str(&lib::wrapped(&format!(
                        "{}x{}",
                        width as i64, height as i64
                    )));
                }
                if let Some(rate) = stream
                    .get("avg_frame_rate")
                    .and_then(json::Value::as_str)
                    .filter(|text| !text.is_empty())
                {
                    let (num, den) = match rate.split_once('/') {
                        Some((num, den)) => (num, den),
                        None => (rate, "1"),
                    };
                    if let (Ok(num), Ok(den)) = (num.parse::<f64>(), den.parse::<f64>()) {
                        if den != 0.0 {
                            frame_rate = format!("{:.0}", num / den);
                        }
                    }
                }
            }
            Some("audio") => {
                if let Some(bitrate) = number_field(stream, "bit_rate") {
                    audio_bitrate = format!("{:.0}", convert_unit(bitrate, 2).floor());
                }
                if let Some(sample_rate) = number_field(stream, "sample_rate") {
                    audio_sample_rate = format!("{sample_rate}");
                    let parsed: f64 = audio_sample_rate.parse().unwrap_or(0.0);
                    audio_sample_rate = format!("{}", parsed / 1000.0);
                }
            }
            _ => {}
        }
    }

    let Some(format) = document.get("format") else {
        return;
    };
    let duration = number_field(format, "duration").unwrap_or(0.0);
    out.push_str(&lib::wrapped(&timedelta(duration.floor() as i64)));
    let size = convert_unit(number_field(format, "size").unwrap_or(0.0), 3).floor();
    out.push_str(&lib::size(&format!("{size:.0}"), Some("MIB"), Some("")));
    let video_bitrate = convert_unit(number_field(format, "bit_rate").unwrap_or(0.0), 2).floor();
    out.push_str(&lib::size(
        &format!("{video_bitrate:.0}"),
        Some("kbps"),
        Some("vidbrate"),
    ));
    if !frame_rate.is_empty() {
        out.push_str(&lib::wrap_with(
            &frame_rate,
            "",
            "fps",
            lib::colour_enabled(),
        ));
    }
    if !audio_sample_rate.is_empty() {
        out.push_str(&lib::size(&audio_sample_rate, Some("K"), Some("")));
    }
    if !audio_bitrate.is_empty() {
        out.push_str(&lib::size(&audio_bitrate, Some("kbps"), Some("audbrate")));
    }
    println!("{out}");
}

fn main() -> std::process::ExitCode {
    let mut directory = String::new();
    for filename in std::env::args().skip(1) {
        if !Path::new(&filename).exists() {
            continue;
        }
        if let Some(parent) = Path::new(&filename).parent() {
            if !parent.as_os_str().is_empty() {
                directory = parent.display().to_string();
            }
        }
        let directory_out = if directory.is_empty() || directory == "." {
            String::new()
        } else {
            lib::fancy_file(&directory)
        };
        let name = Path::new(&filename)
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_default();
        println!(
            "{}{}{}",
            lib::prefix(),
            directory_out,
            lib::fancy_file(&name)
        );
        media_info(&filename);
    }
    std::process::ExitCode::SUCCESS
}

/// Minimal JSON reader for ffprobe output.
mod json {
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
            if self.peek() == Some('}') {
                self.pos += 1;
                return Some(Value::Object(entries));
            }
            loop {
                self.skip_ws();
                let key = self.string()?;
                self.skip_ws();
                if self.peek() != Some(':') {
                    return None;
                }
                self.pos += 1;
                entries.push((key, self.value()?));
                self.skip_ws();
                match self.peek()? {
                    ',' => self.pos += 1,
                    '}' => {
                        self.pos += 1;
                        return Some(Value::Object(entries));
                    }
                    _ => return None,
                }
            }
        }

        fn array(&mut self) -> Option<Value> {
            self.pos += 1;
            let mut items = Vec::new();
            self.skip_ws();
            if self.peek() == Some(']') {
                self.pos += 1;
                return Some(Value::Array(items));
            }
            loop {
                items.push(self.value()?);
                self.skip_ws();
                match self.peek()? {
                    ',' => self.pos += 1,
                    ']' => {
                        self.pos += 1;
                        return Some(Value::Array(items));
                    }
                    _ => return None,
                }
            }
        }

        fn string(&mut self) -> Option<String> {
            if self.peek() != Some('"') {
                return None;
            }
            self.pos += 1;
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
            if self.peek() == Some('-') {
                self.pos += 1;
            }
            while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                self.pos += 1;
            }
            if self.peek() == Some('.') {
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
