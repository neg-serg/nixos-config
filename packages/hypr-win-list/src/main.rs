//! List Hyprland windows in a vicinae dmenu picker, focus the chosen one.
//!
//! Rust port of `hypr-win-list.py`: builds one line per window
//! (`<glyph> <title> (<workspace>) — <address>`), pipes the lines into
//! `vicinae dmenu`, and focuses the window the user picked. Windows on special
//! workspaces and the already-focused window are hidden, because picking those
//! is never what the picker is for.
//!
//! No crates: `hyprctl` and `vicinae` are shelled out to, and the JSON the
//! compositor emits is read by the compact parser at the bottom.

use std::io::Write;
use std::process::{Command, Stdio};

const TITLE_LIMIT: usize = 36;
const WORKSPACE_LIMIT: usize = 16;
const CLASS_LIMIT: usize = 18;
/// Nerd Font private-use glyphs, one per window class family.
const GLYPHS: [(&str, char); 12] = [
    ("floorp", '\u{f269}'),
    ("kitty", '\u{f120}'),
    ("term", '\u{f120}'),
    ("alacritty", '\u{f120}'),
    ("foot", '\u{f120}'),
    ("mpv", '\u{f008}'),
    ("zathura", '\u{f1c1}'),
    ("org.pwmt.zathura", '\u{f1c1}'),
    ("steam", '\u{f1b6}'),
    ("obsidian", '\u{f03d}'),
    ("obs", '\u{f03d}'),
    ("swayimg", '\u{f03e}'),
];
const FALLBACK_GLYPH: char = '\u{f2d0}';

fn debug_enabled() -> bool {
    std::env::var_os("HYPR_WIN_LIST_DEBUG").is_some_and(|value| !value.is_empty())
}

fn debug(message: &str) {
    if debug_enabled() {
        eprintln!("[hypr-win-list] {message}");
    }
}

fn hyprctl() -> String {
    match std::env::var("HYPR_WIN_LIST_HYPRCTL") {
        Ok(value) if !value.is_empty() => value,
        _ => "hyprctl".to_string(),
    }
}

fn hypr_json(command: &str) -> Option<json::Value> {
    let output = Command::new(hyprctl())
        .args(["-j", command])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let payload = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if payload.is_empty() {
        return None;
    }
    json::parse(&payload)
}

/// Collapse whitespace.
pub fn clean(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Clean and shorten, with an ellipsis when it had to cut.
pub fn clip(text: &str, limit: usize) -> String {
    let text = clean(text);
    let chars: Vec<char> = text.chars().collect();
    if chars.len() > limit {
        let mut out: String = chars[..limit - 1].iter().collect();
        out.push('…');
        return out;
    }
    text
}

/// Workspace label: the glyph prefix is dropped, the rest is kept.
pub fn workspace_label(name: &str) -> String {
    let name = clean(name);
    if name.is_empty() {
        return String::new();
    }
    if let Some((_, tail)) = name.split_once(' ') {
        let tail = tail.trim();
        if !tail.is_empty() {
            return tail.to_string();
        }
    }
    name
}

pub fn glyph(class: &str) -> char {
    let class = class.to_lowercase();
    for (key, icon) in GLYPHS {
        if class.contains(key) {
            return icon;
        }
    }
    FALLBACK_GLYPH
}

fn contains_control_chars(line: &str) -> bool {
    line.chars().any(|ch| (ch as u32) < 32 && ch != '\t')
}

fn as_i64(value: &json::Value) -> Option<i64> {
    value.as_i64()
}

struct Entry {
    line: String,
}

/// One picker line per eligible window.
fn build_entries() -> Vec<Entry> {
    let Some(clients_raw) = hypr_json("clients") else {
        return Vec::new();
    };
    let workspaces_raw = hypr_json("workspaces").unwrap_or(json::Value::Null);
    let active_raw = hypr_json("activewindow").unwrap_or(json::Value::Null);

    let clients = clients_raw
        .get("clients")
        .filter(|value| value.as_array().is_some())
        .unwrap_or(&clients_raw);
    let workspaces = workspaces_raw
        .get("workspaces")
        .filter(|value| value.as_array().is_some())
        .unwrap_or(&workspaces_raw);

    let mut ws_map: Vec<(i64, String)> = Vec::new();
    let mut special_ids: Vec<i64> = Vec::new();
    for workspace in workspaces.as_array().unwrap_or(&[]) {
        let id = workspace.get("id").and_then(as_i64);
        if let Some(id) = id {
            let name = workspace
                .get("name")
                .and_then(json::Value::as_str)
                .unwrap_or("")
                .to_string();
            let name = if name.is_empty() {
                id.to_string()
            } else {
                clean(&name)
            };
            ws_map.push((id, name));
        }
        let special = workspace
            .get("special")
            .and_then(json::Value::as_bool)
            .unwrap_or(false)
            || clean(
                workspace
                    .get("name")
                    .and_then(json::Value::as_str)
                    .unwrap_or(""),
            )
            .starts_with("special");
        if special {
            if let Some(id) = id {
                special_ids.push(id);
            }
        }
    }

    let active_addr = clean(
        active_raw
            .get("address")
            .and_then(json::Value::as_str)
            .unwrap_or(""),
    );

    let mut entries = Vec::new();
    for client in clients.as_array().unwrap_or(&[]) {
        if client.get("mapped").and_then(json::Value::as_bool) == Some(false) {
            continue;
        }
        let workspace = client.get("workspace");
        let (mut wid, mut wname) = (None, String::new());
        if let Some(workspace) = workspace {
            if workspace.as_array().is_some() {
                continue;
            }
            if let Some(id) = workspace.get("id").and_then(as_i64) {
                wid = Some(id);
                wname = clean(
                    workspace
                        .get("name")
                        .and_then(json::Value::as_str)
                        .unwrap_or(""),
                );
            } else if let Some(id) = as_i64(workspace) {
                wid = Some(id);
                wname = ws_map
                    .iter()
                    .find(|(candidate, _)| *candidate == id)
                    .map(|(_, name)| name.clone())
                    .unwrap_or_else(|| id.to_string());
            }
        }
        let Some(wid) = wid else {
            continue;
        };
        if special_ids.contains(&wid) || wname.starts_with("special") {
            continue;
        }
        let address = clean(
            client
                .get("address")
                .and_then(json::Value::as_str)
                .unwrap_or(""),
        );
        if address.is_empty() || address == active_addr {
            continue;
        }
        let class = clean(
            client
                .get("class")
                .and_then(json::Value::as_str)
                .unwrap_or(""),
        );
        let title = clean(
            client
                .get("title")
                .and_then(json::Value::as_str)
                .unwrap_or(""),
        );
        let ws_label = workspace_label(&wname);

        let mut parts: Vec<String> = vec![glyph(&class).to_string()];
        let mut workspace_added = false;
        if !title.is_empty() {
            parts.push(clip(&title, TITLE_LIMIT));
        }
        if !ws_label.is_empty()
            && (title.is_empty() || !title.to_lowercase().contains(&ws_label.to_lowercase()))
        {
            parts.push(format!("({})", clip(&ws_label, WORKSPACE_LIMIT)));
            workspace_added = true;
        }
        if title.is_empty() {
            if !ws_label.is_empty() && !workspace_added {
                parts.push(format!("({})", clip(&ws_label, WORKSPACE_LIMIT)));
            }
            if !class.is_empty() {
                parts.push(clip(&class, CLASS_LIMIT));
            }
        }
        let display = parts
            .into_iter()
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join(" ");
        let line = format!("{display} — {address}");
        if contains_control_chars(&line) {
            debug(&format!("skipped entry with control chars: {line:?}"));
            continue;
        }
        debug(&format!("entry: {line:?}"));
        entries.push(Entry { line });
    }
    entries
}

/// Run the picker and return the chosen address, if any.
fn pick(entries: &[Entry]) -> Option<String> {
    let input: String = entries
        .iter()
        .map(|entry| entry.line.as_str())
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";
    debug(&format!("vicinae dmenu count={}", entries.len()));
    let mut child = Command::new("vicinae")
        .args(["dmenu", "-s", "\u{f1b67} Windows"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }
    let output = child.wait_with_output().ok()?;
    if !output.status.success() {
        return None;
    }
    let selection = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let (_, address) = selection.split_once(" — ")?;
    let address = address.trim().to_string();
    if address.is_empty() {
        None
    } else {
        Some(address)
    }
}

fn focus(address: &str) {
    let _ = Command::new(hyprctl())
        .args([
            "dispatch",
            &format!("hl.dsp.focus({{window=\"address:{address}\"}})"),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn main() -> std::process::ExitCode {
    let entries = build_entries();
    if entries.is_empty() {
        return std::process::ExitCode::SUCCESS;
    }
    if let Some(address) = pick(&entries) {
        focus(&address);
    }
    std::process::ExitCode::SUCCESS
}

/// Compact JSON reader for `hyprctl -j` output.
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
    fn whitespace_is_collapsed_and_clipped() {
        assert_eq!(clean("  a  b\tc "), "a b c");
        assert_eq!(clip("0123456789", 5), "0123…");
        assert_eq!(clip("abc", 5), "abc");
        // Multi-byte characters count as one each.
        assert_eq!(clip("привет мир", 7), "привет…");
    }

    #[test]
    fn workspace_labels_drop_the_glyph_prefix() {
        assert_eq!(workspace_label("\u{f020} term"), "term");
        assert_eq!(workspace_label("term"), "term");
        assert_eq!(workspace_label("  "), "");
        assert_eq!(workspace_label("\u{f020} "), "\u{f020}");
    }

    #[test]
    fn glyphs_follow_the_class_family() {
        assert_eq!(glyph("kitty"), '\u{f120}');
        assert_eq!(glyph("org.pwmt.zathura"), '\u{f1c1}');
        assert_eq!(glyph("Steam"), '\u{f1b6}');
        assert_eq!(glyph("unknown"), FALLBACK_GLYPH);
    }

    #[test]
    fn control_characters_disqualify_a_line() {
        assert!(contains_control_chars("a\u{1}b"));
        assert!(!contains_control_chars("a\tb"));
        assert!(!contains_control_chars("обычная строка"));
    }
}
