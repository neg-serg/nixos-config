//! The colour scheme matugen would make from each wallpaper, for the cards of
//! the pleamar picker scene.
//!
//!     wallpaper-palettes DIR [NAME...]      one JSON line per wallpaper, as soon as it is read
//!     wallpaper-palettes --names DIR        the wallpapers of the folder, one name a line
//!
//! matugen runs as a dry run (nothing is written or applied) with the options
//! the picker sets a wallpaper with, so a card shows the exact scheme its
//! wallpaper will give:
//!
//!     {"n": name, "m": mtime, "s": bytes, "w": width, "h": height,
//!      "c": {role: "#rrggbb", ...}}
//!
//! with `"e": 1` instead of `"c"` when matugen cannot read the image. A video is
//! read from a frame of it (the still helper beside this script), whose path
//! comes as `"f"`; `"w"` and `"h"` are the frame's.
//!
//! Without `NAME...` the whole folder is walked in name order. A line on stdin
//! of tab-separated names moves those names to the front of the queue.
//!
//! Port of `files/pleamar/scripts/helpers/wallpaper-palettes.py`. The vendored
//! `files/qs-wallpaperpicker/scripts/wallpaper-palettes.py` is an upstream
//! export and stays untouched.
//!
//! Environment: `MATUGEN`, `WALLPAPER_STILL` (defaults: the same names on PATH).

use std::collections::VecDeque;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};

const WORKERS: usize = 3;
const VIDEO_EXTENSIONS: [&str; 5] = [".mp4", ".webm", ".mkv", ".mov", ".m4v"];

/// The roles a picker card needs, in the order matugen reports them.
const ROLES: [&str; 25] = [
    "background",
    "surface",
    "surface_container_lowest",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "on_surface",
    "on_surface_variant",
    "outline",
    "outline_variant",
    "primary",
    "on_primary",
    "primary_container",
    "on_primary_container",
    "secondary",
    "on_secondary",
    "secondary_container",
    "on_secondary_container",
    "tertiary",
    "on_tertiary",
    "tertiary_container",
    "on_tertiary_container",
    "error",
    "source_color",
];

// -- image headers -----------------------------------------------------

fn be_u16(bytes: &[u8]) -> u32 {
    u32::from(u16::from_be_bytes([bytes[0], bytes[1]]))
}

fn le_u16(bytes: &[u8]) -> u32 {
    u32::from(u16::from_le_bytes([bytes[0], bytes[1]]))
}

fn be_u32(bytes: &[u8]) -> u32 {
    u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

/// `(width, height)` from the file's header, or `(0, 0)`.
pub fn image_size(path: &Path) -> (u32, u32) {
    let Ok(bytes) = std::fs::read(path) else {
        return (0, 0);
    };
    if bytes.len() >= 24 && bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return (be_u32(&bytes[16..20]), be_u32(&bytes[20..24]));
    }
    if bytes.len() >= 10 && (bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a")) {
        return (le_u16(&bytes[6..8]), le_u16(&bytes[8..10]));
    }
    if bytes.len() >= 30 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        match &bytes[12..16] {
            b"VP8 " => {
                return (
                    le_u16(&bytes[26..28]) & 0x3FFF,
                    le_u16(&bytes[28..30]) & 0x3FFF,
                );
            }
            b"VP8L" => {
                let bits = u32::from_le_bytes([bytes[21], bytes[22], bytes[23], bytes[24]]);
                return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
            }
            b"VP8X" => {
                let width = u32::from_le_bytes([bytes[24], bytes[25], bytes[26], 0]) + 1;
                let height = u32::from_le_bytes([bytes[27], bytes[28], bytes[29], 0]) + 1;
                return (width, height);
            }
            _ => {}
        }
    }
    if bytes.len() >= 2 && bytes.starts_with(b"\xff\xd8") {
        return jpeg_size(&bytes);
    }
    (0, 0)
}

/// Walk the JPEG marker chain until the frame header.
fn jpeg_size(bytes: &[u8]) -> (u32, u32) {
    let mut offset = 2;
    while offset + 1 < bytes.len() {
        if bytes[offset] != 0xFF {
            offset += 1;
            continue;
        }
        let mut marker = bytes[offset + 1];
        offset += 2;
        while marker == 0xFF {
            if offset >= bytes.len() {
                return (0, 0);
            }
            marker = bytes[offset];
            offset += 1;
        }
        if marker == 0xD9 || marker == 0xDA {
            return (0, 0);
        }
        if marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            continue;
        }
        if offset + 1 >= bytes.len() {
            return (0, 0);
        }
        let length = be_u16(&bytes[offset..offset + 2]) as usize;
        if (0xC0..=0xCF).contains(&marker) && ![0xC4, 0xC8, 0xCC].contains(&marker) {
            if offset + 7 > bytes.len() {
                return (0, 0);
            }
            // Skip the length, the sample precision, then height and width.
            let height = be_u16(&bytes[offset + 3..offset + 5]);
            let width = be_u16(&bytes[offset + 5..offset + 7]);
            return (width, height);
        }
        if length < 2 {
            return (0, 0);
        }
        offset += length;
    }
    (0, 0)
}

// -- external helpers --------------------------------------------------

fn program(name: &str, env: &str) -> String {
    match std::env::var(env) {
        Ok(value) if !value.is_empty() => value,
        _ => name.to_string(),
    }
}

/// The still helper: `WALLPAPER_STILL`, else the sibling of this executable
/// (the picker installs both into `~/.local/bin`), else whatever is on PATH.
fn still_program() -> String {
    if let Ok(value) = std::env::var("WALLPAPER_STILL") {
        if !value.is_empty() {
            return value;
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for name in ["pleamar-wallpaper-still", "wallpaper-still"] {
                let candidate = dir.join(name);
                if candidate.is_file() {
                    return candidate.display().to_string();
                }
            }
        }
    }
    "wallpaper-still".to_string()
}

/// A video's grabbed frame (cached by the still helper), or `None`.
pub fn still(path: &Path) -> Option<String> {
    let helper = still_program();
    let output = Command::new(helper)
        .arg(path)
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let frame = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if frame.is_empty() {
        None
    } else {
        Some(frame)
    }
}

/// The colours matugen would pick, in role order.
pub fn scheme(path: &Path) -> Option<Vec<(String, String)>> {
    let matugen = program("matugen", "MATUGEN");
    let output = Command::new(matugen)
        .args([
            "image",
            &path.display().to_string(),
            "--source-color-index",
            "0",
            "--dry-run",
            "-j",
            "hex",
            "-q",
        ])
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let document = json::parse(&text)?;
    let colors = document.get("colors")?;
    let mut picked = Vec::new();
    for role in ROLES {
        let Some(entry) = colors.get(role) else {
            continue;
        };
        let color = entry
            .get("default")
            .filter(|value| !matches!(value, json::Value::Null))
            .or_else(|| entry.get("dark"));
        let Some(color) = color
            .and_then(|value| value.get("color"))
            .and_then(json::Value::as_str)
        else {
            continue;
        };
        picked.push((role.to_string(), color.to_string()));
    }
    Some(picked)
}

// -- the folder --------------------------------------------------------

/// Every file that is not hidden, in name order.
pub fn names_in(folder: &Path) -> Result<Vec<String>, String> {
    let entries =
        std::fs::read_dir(folder).map_err(|exc| format!("{}: {}", folder.display(), exc))?;
    let mut names: Vec<String> = entries
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().to_string())
        .filter(|name| !name.starts_with('.'))
        .filter(|name| folder.join(name).is_file())
        .collect();
    names.sort();
    Ok(names)
}

fn is_video(name: &str) -> bool {
    let lower = name.to_lowercase();
    VIDEO_EXTENSIONS
        .iter()
        .any(|extension| lower.ends_with(extension))
}

fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out.push('"');
    out
}

/// One record: the JSON `{"n": …, "m": …, "s": …, "w": …, "h": …, "c"|"e": …}`.
pub fn record(folder: &Path, name: &str) -> Option<String> {
    let path = folder.join(name);
    let metadata = std::fs::metadata(&path).ok()?;
    let mtime = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|delta| delta.as_secs())
        .unwrap_or(0);
    let mut body = format!(
        "{{\"n\":{},\"m\":{},\"s\":{}",
        json_string(name),
        mtime,
        metadata.len()
    );
    let mut image = Some(path.clone());
    if is_video(name) {
        match still(&path) {
            Some(frame) => {
                body.push_str(&format!(",\"f\":{}", json_string(&frame)));
                image = Some(PathBuf::from(frame));
            }
            None => image = None,
        }
    }
    let (width, height) = image.as_deref().map(image_size).unwrap_or((0, 0));
    body.push_str(&format!(",\"w\":{width},\"h\":{height}"));
    match image.as_deref().and_then(scheme) {
        Some(colors) => {
            let rendered: Vec<String> = colors
                .iter()
                .map(|(role, value)| format!("{}:{}", json_string(role), json_string(value)))
                .collect();
            body.push_str(&format!(",\"c\":{{{}}}", rendered.join(",")));
        }
        None => body.push_str(",\"e\":1"),
    }
    body.push('}');
    Some(body)
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--names") {
        if args.len() != 2 {
            eprintln!("usage: wallpaper-palettes --names DIR");
            return std::process::ExitCode::from(1);
        }
        let folder = expand(&args[1]);
        match names_in(&folder) {
            Ok(names) => {
                let mut stdout = std::io::stdout();
                for name in names {
                    let _ = writeln!(stdout, "{name}");
                }
                let _ = stdout.flush();
                std::process::ExitCode::SUCCESS
            }
            Err(exc) => {
                eprintln!("wallpaper-palettes: {exc}");
                std::process::ExitCode::from(1)
            }
        }
    } else {
        if args.is_empty() {
            eprintln!("usage: wallpaper-palettes DIR [NAME...]");
            return std::process::ExitCode::from(1);
        }
        run(&expand(&args[0]), &args[1..])
    }
}

fn expand(path: &str) -> PathBuf {
    match path.strip_prefix("~/") {
        Some(rest) => match std::env::var_os("HOME") {
            Some(home) => PathBuf::from(home).join(rest),
            None => PathBuf::from(path),
        },
        None => PathBuf::from(path),
    }
}

fn run(folder: &Path, requested: &[String]) -> std::process::ExitCode {
    let mut initial: Vec<String> = Vec::new();
    if requested.is_empty() {
        match names_in(folder) {
            Ok(names) => initial = names,
            Err(exc) => {
                eprintln!("wallpaper-palettes: {exc}");
                return std::process::ExitCode::from(1);
            }
        }
    } else {
        for name in requested {
            if !initial.contains(name) {
                initial.push(name.clone());
            }
        }
    }
    let queue = Arc::new(Mutex::new(VecDeque::from(initial)));
    let output = Arc::new(Mutex::new(()));

    // A line of tab-separated names moves those names to the front.
    {
        let queue = Arc::clone(&queue);
        std::thread::spawn(move || {
            let stdin = std::io::stdin();
            for line in stdin.lock().lines().map_while(Result::ok) {
                let names: Vec<String> = line
                    .trim_end_matches('\n')
                    .split('\t')
                    .filter(|name| !name.is_empty())
                    .map(str::to_string)
                    .collect();
                let mut queue = queue.lock().expect("queue");
                for name in names.iter().rev() {
                    if let Some(index) = queue.iter().position(|candidate| candidate == name) {
                        queue.remove(index);
                    }
                    queue.push_front(name.clone());
                }
            }
        });
    }

    let mut workers = Vec::new();
    for _ in 0..WORKERS {
        let queue = Arc::clone(&queue);
        let output = Arc::clone(&output);
        let folder = folder.to_path_buf();
        workers.push(std::thread::spawn(move || loop {
            let name = {
                let mut queue = queue.lock().expect("queue");
                match queue.pop_front() {
                    Some(name) => name,
                    None => return,
                }
            };
            let Some(line) = record(&folder, &name) else {
                continue;
            };
            let _guard = output.lock().expect("output");
            let mut stdout = std::io::stdout();
            let _ = writeln!(stdout, "{line}");
            let _ = stdout.flush();
        }));
    }
    for worker in workers {
        let _ = worker.join();
    }
    std::process::ExitCode::SUCCESS
}

// -- JSON (matugen's dry-run output) -----------------------------------

mod json {
    #[derive(Debug, Clone, PartialEq)]
    pub enum Value {
        Null,
        Bool(bool),
        Int(i64),
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
            let mut float = false;
            if matches!(self.peek(), Some('.')) {
                float = true;
                self.pos += 1;
                while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                    self.pos += 1;
                }
            }
            if matches!(self.peek(), Some('e') | Some('E')) {
                float = true;
                self.pos += 1;
                if matches!(self.peek(), Some('+') | Some('-')) {
                    self.pos += 1;
                }
                while matches!(self.peek(), Some(ch) if ch.is_ascii_digit()) {
                    self.pos += 1;
                }
            }
            if self.pos == start {
                return None;
            }
            let text: String = self.chars[start..self.pos].iter().collect();
            if !float {
                if let Ok(value) = text.parse::<i64>() {
                    return Some(Value::Int(value));
                }
            }
            text.parse::<f64>().ok().map(Value::Number)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "wallpaper-palettes-{tag}-{}-{}",
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
    fn png_gif_and_webp_sizes_are_read_from_headers() {
        let dir = temp_dir("headers");
        let png = dir.join("a.png");
        let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
        bytes.extend_from_slice(&[0, 0, 0, 13]); // IHDR length
        bytes.extend_from_slice(b"IHDR");
        bytes.extend_from_slice(&1920u32.to_be_bytes());
        bytes.extend_from_slice(&1080u32.to_be_bytes());
        std::fs::write(&png, &bytes).unwrap();
        assert_eq!(image_size(&png), (1920, 1080));

        let gif = dir.join("b.gif");
        let mut bytes = b"GIF89a".to_vec();
        bytes.extend_from_slice(&640u16.to_le_bytes());
        bytes.extend_from_slice(&480u16.to_le_bytes());
        std::fs::write(&gif, &bytes).unwrap();
        assert_eq!(image_size(&gif), (640, 480));

        let webp = dir.join("c.webp");
        let mut bytes = b"RIFF\x00\x00\x00\x00WEBPVP8X".to_vec();
        bytes.extend_from_slice(&[0u8; 8]);
        bytes.extend_from_slice(&[0xFF, 0x0F, 0x00]); // 4095 + 1
        bytes.extend_from_slice(&[0x57, 0x08, 0x00]); // 2135 + 1
        std::fs::write(&webp, &bytes).unwrap();
        assert_eq!(image_size(&webp), (4096, 2136));

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn jpeg_sizes_are_read_from_the_frame_header() {
        let dir = temp_dir("jpeg");
        let jpeg = dir.join("d.jpg");
        let mut bytes = b"\xff\xd8".to_vec();
        // APP0 with a length that has to be honoured.
        bytes.extend_from_slice(&[0xFF, 0xE0, 0x00, 0x10]);
        bytes.extend_from_slice(&[0u8; 14]);
        // SOF0: length 17, precision 8, height 2160, width 3840.
        bytes.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x11, 0x08]);
        bytes.extend_from_slice(&2160u16.to_be_bytes());
        bytes.extend_from_slice(&3840u16.to_be_bytes());
        std::fs::write(&jpeg, &bytes).unwrap();
        assert_eq!(image_size(&jpeg), (3840, 2160));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn unknown_files_report_zero_and_hidden_files_are_skipped() {
        let dir = temp_dir("names");
        std::fs::write(dir.join("a.png"), b"not an image").unwrap();
        std::fs::write(dir.join("b.jpg"), b"also not").unwrap();
        std::fs::write(dir.join(".hidden.png"), b"x").unwrap();
        std::fs::create_dir_all(dir.join("sub")).unwrap();
        assert_eq!(names_in(&dir).unwrap(), vec!["a.png", "b.jpg"]);
        assert_eq!(image_size(&dir.join("a.png")), (0, 0));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn videos_are_recognised_by_extension() {
        assert!(is_video("clip.MP4"));
        assert!(is_video("x.webm"));
        assert!(!is_video("x.png"));
    }

    #[test]
    fn records_carry_size_and_a_failure_marker() {
        let dir = temp_dir("record");
        std::fs::write(dir.join("plain.png"), b"nope").unwrap();
        // Without matugen the record still describes the file, with "e": 1.
        std::env::set_var("MATUGEN", "/bin/false");
        let line = record(&dir, "plain.png").expect("record");
        assert!(line.starts_with("{\"n\":\"plain.png\",\"m\":"), "{line}");
        assert!(line.contains("\"w\":0,\"h\":0"), "{line}");
        assert!(line.ends_with("\"e\":1}"), "{line}");
        assert!(record(&dir, "missing.png").is_none());
        std::env::remove_var("MATUGEN");
        std::fs::remove_dir_all(&dir).ok();
    }
}
