//! Re-assert Vivaldi preferences before the browser starts.
//!
//! Vivaldi rewrites `Preferences` from memory on exit, so this runs from a
//! systemd user unit before the browser starts. The profile is loaded once,
//! only differing keys are touched, and the file is written back with Vivaldi's
//! own `indent=1` formatting — the browser is picky about the file, and a
//! wholesale re-dump with different conventions would be a needless diff.
//!
//! Port of `modules/user/nix-maid/web/vivaldi-prefs.py`.
//!
//! Environment:
//!   VIVALDI_PREFS       path to `Preferences` (default
//!                       ~/.config/vivaldi/Default/Preferences)
//!   VIVALDI_CSS_MODS    css mods directory the pref must point at (default
//!                       ~/.config/vivaldi/css-mods)

use std::path::PathBuf;

/// The Neg dark theme id the browser chrome must keep selected.
const NEG_THEME: &str = "6265ce0d-0cec-40c1-8002-ef5c1f962c7a";

fn home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn env_path(name: &str, fallback: PathBuf) -> PathBuf {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => PathBuf::from(shellexpand_tilde(&value)),
        _ => fallback,
    }
}

fn shellexpand_tilde(path: &str) -> String {
    match path.strip_prefix("~/") {
        Some(rest) => format!("{}/{}", home().display(), rest),
        None => path.to_string(),
    }
}

// -- JSON (order preserving, `indent=1` like Vivaldi) -------------------

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    /// Integers keep their exact spelling so a round-trip does not turn `1`
    /// into `1.0` (Python's JSON distinguishes the two).
    Int(i64),
    Number(f64),
    Str(String),
    Array(Vec<Value>),
    Object(Vec<(String, Value)>),
}

impl Value {
    fn as_object_mut(&mut self) -> Option<&mut Vec<(String, Value)>> {
        match self {
            Value::Object(entries) => Some(entries),
            _ => None,
        }
    }

    fn empty_object() -> Value {
        Value::Object(Vec::new())
    }
}

fn get<'a>(entries: &'a [(String, Value)], key: &str) -> Option<&'a Value> {
    entries
        .iter()
        .find(|(name, _)| name == key)
        .map(|(_, value)| value)
}

fn set(entries: &mut Vec<(String, Value)>, key: &str, value: Value) {
    match entries.iter_mut().find(|(name, _)| name == key) {
        Some(entry) => entry.1 = value,
        None => entries.push((key.to_string(), value)),
    }
}

/// `p.setdefault(key, {})` that works on an object value.
fn ensure_object<'a>(value: &'a mut Value, key: &str) -> &'a mut Value {
    if !matches!(value, Value::Object(_)) {
        *value = Value::empty_object();
    }
    let entries = value.as_object_mut().expect("object");
    if get(entries, key).is_none() {
        entries.push((key.to_string(), Value::empty_object()));
    }
    let index = entries
        .iter()
        .position(|(name, _)| name == key)
        .expect("inserted above");
    &mut entries[index].1
}

/// `p.setdefault("vivaldi", {}).setdefault("appearance", {})` and friends.
fn nested<'a>(root: &'a mut Value, path: &[&str]) -> &'a mut Value {
    let mut current = root;
    for key in path {
        current = ensure_object(current, key);
    }
    current
}

fn parse(text: &str) -> Option<Value> {
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
                        'b' => out.push('\u{8}'),
                        'f' => out.push('\u{c}'),
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
        if matches!(self.peek(), Some('e') | Some('E')) {
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
        if !text.contains('.') && !text.contains('e') && !text.contains('E') {
            return text.parse::<i64>().ok().map(Value::Int);
        }
        text.parse::<f64>().ok().map(Value::Number)
    }
}

/// `json.dump(value, indent=1)`: one space per nesting level, `": "` and
/// `", "`-free compact separators with newlines between entries.
fn dump(value: &Value, indent: usize) -> String {
    let mut out = String::new();
    write_value(&mut out, value, indent, 0);
    out
}

fn write_value(out: &mut String, value: &Value, indent: usize, level: usize) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(flag) => out.push_str(if *flag { "true" } else { "false" }),
        Value::Int(number) => out.push_str(&number.to_string()),
        Value::Number(number) => out.push_str(&format_number(*number)),
        Value::Str(text) => write_string(out, text),
        Value::Array(items) => {
            if items.is_empty() {
                out.push_str("[]");
                return;
            }
            out.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                newline(out, indent, level + 1);
                write_value(out, item, indent, level + 1);
            }
            newline(out, indent, level);
            out.push(']');
        }
        Value::Object(entries) => {
            if entries.is_empty() {
                out.push_str("{}");
                return;
            }
            out.push('{');
            for (index, (key, item)) in entries.iter().enumerate() {
                if index > 0 {
                    out.push(',');
                }
                newline(out, indent, level + 1);
                write_string(out, key);
                out.push_str(": ");
                write_value(out, item, indent, level + 1);
            }
            newline(out, indent, level);
            out.push('}');
        }
    }
}

fn newline(out: &mut String, indent: usize, level: usize) {
    out.push('\n');
    for _ in 0..indent * level {
        out.push(' ');
    }
}

/// Floats print with the shortest round-tripping form and always keep a
/// decimal part, the way Python's `json` writes `1.0` and `-0.0`.
fn format_number(number: f64) -> String {
    if number.fract() == 0.0 && number.is_finite() && number.abs() < 1e16 {
        if number == 0.0 && number.is_sign_negative() {
            return "-0.0".to_string();
        }
        format!("{:.1}", number)
    } else {
        format!("{number}")
    }
}

fn write_string(out: &mut String, text: &str) {
    out.push('"');
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out.push('"');
}

// -- the preference fixes ----------------------------------------------

/// Re-assert every managed preference; returns the human-readable report.
pub fn apply(prefs: &mut Value, css_mods: &str) -> Vec<String> {
    let mut reports = Vec::new();
    let mut changed = false;

    // 1a. Point the CSS mods dir at the profile mods folder so the compact
    // address-bar mod loads (the pref is empty by default).
    {
        let appearance = nested(prefs, &["vivaldi", "appearance"]);
        if let Value::Object(entries) = appearance {
            let differs = !matches!(get(entries, "css_ui_mods_directory"), Some(Value::Str(value)) if value == css_mods);
            if differs {
                set(
                    entries,
                    "css_ui_mods_directory",
                    Value::Str(css_mods.to_string()),
                );
                changed = true;
            }
        }
    }

    // Neg dark theme must stay selected; if it was dropped, the browser chrome
    // falls back to the default grey theme.
    {
        let themes = nested(prefs, &["vivaldi", "themes"]);
        if let Value::Object(entries) = themes {
            for key in ["current", "current_private"] {
                let matches_theme =
                    matches!(get(entries, key), Some(Value::Str(value)) if value == NEG_THEME);
                if !matches_theme {
                    set(entries, key, Value::Str(NEG_THEME.to_string()));
                    changed = true;
                }
            }
        }
    }

    // Hide the panel bar by default for new windows (it was visible again after
    // a pref reset).
    {
        let defaults = nested(prefs, &["vivaldi", "panels", "window_defaults"]);
        if let Value::Object(entries) = defaults {
            for key in ["barVisible", "contentVisible"] {
                let already_false = matches!(get(entries, key), Some(Value::Bool(false)));
                if !already_false {
                    set(entries, key, Value::Bool(false));
                    changed = true;
                }
            }
        }
    }

    // DevTools UI theme: keep it dark like the browser chrome. The value inside
    // devtools.preferences is a JSON-encoded string ("dark").
    {
        let preferences = nested(prefs, &["devtools", "preferences"]);
        if let Value::Object(entries) = preferences {
            let already_dark =
                matches!(get(entries, "uiTheme"), Some(Value::Str(value)) if value == "\"dark\"");
            if !already_dark {
                set(entries, "uiTheme", Value::Str("\"dark\"".to_string()));
                changed = true;
            }
        }
    }

    if changed {
        reports.push(
            "css_ui_mods_directory, Neg theme, hidden panel bar and DevTools \
             dark theme re-asserted"
                .to_string(),
        );
    }

    // 1b. UI Auto-hide (Vivaldi 7.9+): toolbars slide out on hover — reads as
    // random popups. Force the master switch and per-toolbar flags off; bars
    // keep their manual visibility.
    let auto_hide = [
        ("enabled", false),
        ("panel", false),
        ("tab_bar", false),
        ("bookmarks_bar", false),
        ("status_bar", false),
        ("in_fullscreen", false),
    ];
    let mut changed = false;
    {
        let section = nested(prefs, &["vivaldi", "auto_hide"]);
        if let Value::Object(entries) = section {
            for (key, wanted) in auto_hide {
                let matches_wanted =
                    matches!(get(entries, key), Some(Value::Bool(false))) == !wanted;
                if !matches_wanted {
                    set(entries, key, Value::Bool(wanted));
                    changed = true;
                }
            }
        }
    }
    if changed {
        // Python printed the dict with its own repr (`False`, not `false`).
        let rendered = auto_hide
            .iter()
            .map(|(key, value)| {
                let literal = if *value { "True" } else { "False" };
                format!("'{key}': {literal}")
            })
            .collect::<Vec<_>>()
            .join(", ");
        reports.push(format!("UI Auto-hide disabled: {{{rendered}}}"));
    }

    // `vivaldi.actions[0]`, normalising the list/dict shapes Vivaldi uses.
    let actions = {
        let vivaldi = nested(prefs, &["vivaldi"]);
        let Value::Object(entries) = vivaldi else {
            return reports;
        };
        if get(entries, "actions").is_none() {
            entries.push((
                "actions".to_string(),
                Value::Array(vec![Value::empty_object()]),
            ));
        }
        match entries
            .iter_mut()
            .find(|(name, _)| name == "actions")
            .map(|(_, value)| value)
        {
            Some(Value::Array(items)) => {
                if items.is_empty() {
                    items.push(Value::empty_object());
                }
                items.first_mut()
            }
            Some(value @ Value::Object(_)) => Some(value),
            _ => None,
        }
    };
    let Some(actions) = actions else {
        return reports;
    };
    let Value::Object(actions) = actions else {
        return reports;
    };

    // 1c. Unbind Ctrl+W from close-tab so the emacs keys reach web pages (the
    // composer/terminal forwards it to zsh as C-w).
    if get(actions, "COMMAND_CLOSE_TAB").is_none() {
        actions.push(("COMMAND_CLOSE_TAB".to_string(), Value::Object(Vec::new())));
    }
    let close_tab = actions
        .iter_mut()
        .find(|(name, _)| name == "COMMAND_CLOSE_TAB")
        .map(|(_, value)| value)
        .expect("inserted above");
    if let Value::Object(entries) = close_tab {
        let shortcuts = shortcuts_of(entries);
        if shortcuts.contains(&"ctrl+w") {
            let filtered: Vec<Value> = shortcuts
                .iter()
                .copied()
                .filter(|shortcut| *shortcut != "ctrl+w")
                .map(|shortcut| Value::Str(shortcut.to_string()))
                .collect();
            set(entries, "shortcuts", Value::Array(filtered));
            let rendered = shortcuts_of(entries).join(",");
            reports.push(format!("Ctrl+W unbound from close-tab: [{rendered}]"));
        }
    }

    // 1d. Bind Ctrl+G to close-tab. Vivaldi ships Ctrl+G as "Find Next in Page",
    // so that binding is freed; Ctrl+F4 keeps working.
    let mut changed = Vec::new();
    if let Value::Object(entries) = close_tab {
        let shortcuts = shortcuts_of(entries);
        if !shortcuts.contains(&"ctrl+g") {
            let mut updated: Vec<Value> = shortcuts
                .iter()
                .map(|shortcut| Value::Str((*shortcut).to_string()))
                .collect();
            updated.push(Value::Str("ctrl+g".to_string()));
            set(entries, "shortcuts", Value::Array(updated));
            changed.push(format!("close-tab={}", shortcuts_of(entries).join(",")));
        }
        if let Some((_, find_next)) = actions
            .iter_mut()
            .find(|(name, _)| name == "COMMAND_FIND_NEXT_IN_PAGE")
        {
            if let Value::Object(find_entries) = find_next {
                if shortcuts_of(find_entries).contains(&"ctrl+g") {
                    let filtered: Vec<Value> = shortcuts_of(find_entries)
                        .iter()
                        .copied()
                        .filter(|shortcut| *shortcut != "ctrl+g")
                        .map(|shortcut| Value::Str(shortcut.to_string()))
                        .collect();
                    set(find_entries, "shortcuts", Value::Array(filtered));
                    changed.push(format!(
                        "find-next={}",
                        shortcuts_of(find_entries).join(",")
                    ));
                }
            }
        }
    }
    if !changed.is_empty() {
        reports.push(format!("Ctrl+G closes the tab: {}", changed.join("; ")));
    }

    // 1e. New tab = the dark newtab extension instead of Vivaldi's start page:
    // the start page paints a white frame while its target renders. Vivaldi
    // falls back on its own when no active override exists. link = 3 means
    // "extension" (NEW_PAGE_TYPE.extension).
    {
        let new_page = nested(prefs, &["vivaldi", "tabs", "new_page"]);
        if let Value::Object(entries) = new_page {
            let already_extension =
                matches!(get(entries, "link"), Some(Value::Int(number)) if *number == 3);
            if !already_extension {
                set(entries, "link", Value::Int(3));
                reports
                    .push("new tab opens the dark newtab extension (link = extension)".to_string());
            }
        }
    }

    reports
}

/// The `shortcuts` list of one action, as `&str` (missing or malformed → empty).
fn shortcuts_of(entries: &[(String, Value)]) -> Vec<&str> {
    match get(entries, "shortcuts") {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|item| match item {
                Value::Str(text) => Some(text.as_str()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn main() -> std::process::ExitCode {
    let prefs_path = env_path(
        "VIVALDI_PREFS",
        home().join(".config/vivaldi/Default/Preferences"),
    );
    if !prefs_path.is_file() {
        return std::process::ExitCode::SUCCESS;
    }
    let css_mods = env_path("VIVALDI_CSS_MODS", home().join(".config/vivaldi/css-mods"));
    let Ok(text) = std::fs::read_to_string(&prefs_path) else {
        eprintln!("vivaldi-prefs: cannot read {}", prefs_path.display());
        return std::process::ExitCode::from(1);
    };
    let Some(mut prefs) = parse(&text) else {
        eprintln!("vivaldi-prefs: {} is not valid JSON", prefs_path.display());
        return std::process::ExitCode::from(1);
    };
    let reports = apply(&mut prefs, &css_mods.display().to_string());
    if reports.is_empty() {
        return std::process::ExitCode::SUCCESS;
    }
    if let Err(exc) = std::fs::write(&prefs_path, dump(&prefs, 1)) {
        eprintln!(
            "vivaldi-prefs: cannot write {}: {exc}",
            prefs_path.display()
        );
        return std::process::ExitCode::from(1);
    }
    for report in reports {
        println!("{report}");
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn prefs(text: &str) -> Value {
        parse(text).expect("json")
    }

    #[test]
    fn empty_profile_gets_every_managed_key() {
        let mut value = prefs("{}");
        let reports = apply(&mut value, "/home/neg/.config/vivaldi/css-mods");
        assert!(!reports.is_empty());
        let vivaldi = nested(&mut value, &["vivaldi"]);
        let Value::Object(entries) = vivaldi else {
            panic!("object")
        };
        let appearance = get(entries, "appearance").expect("appearance");
        assert!(matches!(appearance, Value::Object(entries)
            if matches!(get(entries, "css_ui_mods_directory"), Some(Value::Str(text))
                if text == "/home/neg/.config/vivaldi/css-mods")));
        let tabs = nested(&mut value, &["vivaldi", "tabs", "new_page"]);
        assert!(matches!(tabs, Value::Object(entries)
            if matches!(get(entries, "link"), Some(Value::Int(number)) if *number == 3)));
    }

    #[test]
    fn already_correct_profile_is_untouched() {
        let mut value = prefs(
            r#"{"vivaldi": {"appearance": {"css_ui_mods_directory": "/m"},
                "themes": {"current": "6265ce0d-0cec-40c1-8002-ef5c1f962c7a",
                           "current_private": "6265ce0d-0cec-40c1-8002-ef5c1f962c7a"},
                "panels": {"window_defaults": {"barVisible": false, "contentVisible": false}},
                "auto_hide": {"enabled": false, "panel": false, "tab_bar": false,
                              "bookmarks_bar": false, "status_bar": false, "in_fullscreen": false},
                "actions": [{"COMMAND_CLOSE_TAB": {"shortcuts": ["ctrl+f4", "ctrl+g"]},
                             "COMMAND_FIND_NEXT_IN_PAGE": {"shortcuts": ["ctrl+f3"]}}],
                "tabs": {"new_page": {"link": 3}}},
               "devtools": {"preferences": {"uiTheme": "\"dark\""}}}"#,
        );
        let before = dump(&value, 1);
        let reports = apply(&mut value, "/m");
        assert!(reports.is_empty(), "{reports:?}");
        assert_eq!(dump(&value, 1), before);
    }

    #[test]
    fn ctrl_w_is_unbound_and_ctrl_g_bound() {
        let mut value = prefs(
            r#"{"vivaldi": {"actions": [{"COMMAND_CLOSE_TAB": {"shortcuts": ["ctrl+w"]},
                "COMMAND_FIND_NEXT_IN_PAGE": {"shortcuts": ["ctrl+g", "ctrl+f3"]}}],
                "tabs": {"new_page": {"link": 3}},
                "auto_hide": {"enabled": false, "panel": false, "tab_bar": false,
                              "bookmarks_bar": false, "status_bar": false, "in_fullscreen": false},
                "themes": {"current": "6265ce0d-0cec-40c1-8002-ef5c1f962c7a",
                           "current_private": "6265ce0d-0cec-40c1-8002-ef5c1f962c7a"},
                "panels": {"window_defaults": {"barVisible": false, "contentVisible": false}},
                "appearance": {"css_ui_mods_directory": "/m"}},
               "devtools": {"preferences": {"uiTheme": "\"dark\""}}}"#,
        );
        let reports = apply(&mut value, "/m");
        let joined = reports.join("\n");
        assert!(joined.contains("Ctrl+W unbound"), "{joined}");
        assert!(joined.contains("Ctrl+G closes the tab"), "{joined}");
        let vivaldi = nested(&mut value, &["vivaldi", "actions"]);
        let Value::Array(items) = vivaldi else {
            panic!("array")
        };
        let Value::Object(action) = &items[0] else {
            panic!("object")
        };
        let close = get(action, "COMMAND_CLOSE_TAB").expect("close tab");
        let Value::Object(entries) = close else {
            panic!("object")
        };
        assert_eq!(shortcuts_of(entries), vec!["ctrl+g"]);
        let find = get(action, "COMMAND_FIND_NEXT_IN_PAGE").expect("find next");
        let Value::Object(entries) = find else {
            panic!("object")
        };
        assert_eq!(shortcuts_of(entries), vec!["ctrl+f3"]);
    }

    #[test]
    fn dumping_uses_vivaldis_indent_one() {
        let value = prefs(r#"{"a": 1, "b": [true, null], "c": {"d": "x"}}"#);
        assert_eq!(
            dump(&value, 1),
            "{\n \"a\": 1,\n \"b\": [\n  true,\n  null\n ],\n \"c\": {\n  \"d\": \"x\"\n }\n}"
        );
    }
}
