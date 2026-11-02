//! Move Hyprland windows onto the workspaces the config routes them to.
//!
//! Rust port of `hypr-rearrange.py`: reads the workspace routing rules (the
//! `cls` / `routes` tables of `hyprland.lua`, or the legacy `windowrule` lines
//! of `hyprland.conf`), asks the compositor for its clients and moves every
//! window whose class or title matches a rule to that rule's workspace —
//! `--dry-run` prints what it would do instead.
//!
//! No crates: `hyprctl` is shelled out to, the JSON is read by the compact
//! parser at the bottom, and the patterns are matched by the small matcher in
//! `pattern`, which covers the subset Hyprland class/title regexes use
//! (`^`, `$`, `.`, `*`, `+`, `?`, `|`, groups, `[...]`, escapes) plus plain
//! substring matching for unanchored patterns.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// One routing rule: the workspace a client belongs to and what it matches on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub workspace: String,
    pub kind: MatchKind,
    pub pattern: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchKind {
    Class,
    Title,
    InitialClass,
    InitialTitle,
}

impl MatchKind {
    fn from_selector(selector: &str) -> Option<MatchKind> {
        Some(match selector {
            "class" => MatchKind::Class,
            "title" => MatchKind::Title,
            "initialClass" => MatchKind::InitialClass,
            "initialTitle" => MatchKind::InitialTitle,
            _ => return None,
        })
    }

    fn field<'a>(&self, client: &'a json::Value) -> &'a str {
        let key = match self {
            MatchKind::Class => "class",
            MatchKind::Title => "title",
            MatchKind::InitialClass => "initialClass",
            MatchKind::InitialTitle => "initialTitle",
        };
        client.get(key).and_then(json::Value::as_str).unwrap_or("")
    }
}

// -- config parsing ----------------------------------------------------

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn expand(text: &str) -> PathBuf {
    let mut expanded = String::new();
    let mut chars = text.chars();
    while let Some(ch) = chars.next() {
        if ch == '~' {
            expanded.push_str(&home_dir().display().to_string());
        } else if ch == '$' {
            let mut name = String::new();
            while let Some(next) = chars.clone().next() {
                if next.is_alphanumeric() || next == '_' {
                    name.push(next);
                    chars.next();
                } else {
                    break;
                }
            }
            if name.is_empty() {
                expanded.push('$');
            } else {
                expanded.push_str(&std::env::var(&name).unwrap_or_default());
            }
        } else {
            expanded.push(ch);
        }
    }
    PathBuf::from(expanded)
}

/// Unescape the usual Lua string escapes.
pub fn unescape_lua(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.push(ch);
            continue;
        }
        match chars.next() {
            Some('\\') => out.push('\\'),
            Some('"') => out.push('"'),
            Some('n') => out.push('\n'),
            Some('t') => out.push('\t'),
            Some(other) => {
                out.push('\\');
                out.push(other);
            }
            None => out.push('\\'),
        }
    }
    out
}

/// Extract the `{...}` block that follows `local <name> = ` in the Lua config.
fn lua_table<'a>(content: &'a str, name: &str) -> Option<&'a str> {
    let needle = format!("local {name} = {{");
    let start = content.find(&needle)? + needle.len();
    let rest = &content[start..];
    let mut depth = 1usize;
    for (index, ch) in rest.char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return Some(&rest[..index]);
                }
            }
            _ => {}
        }
    }
    None
}

/// `cls` table: alias -> regex pattern.
pub fn parse_lua_cls(content: &str) -> Vec<(String, String)> {
    let Some(block) = lua_table(content, "cls") else {
        return Vec::new();
    };
    let mut map = Vec::new();
    for line in block.lines() {
        let line = line.trim();
        if line.starts_with("--") {
            continue;
        }
        let Some((name, value)) = line.split_once('=') else {
            continue;
        };
        let name = name.trim();
        if name.is_empty() || !name.chars().all(|ch| ch.is_alphanumeric() || ch == '_') {
            continue;
        }
        let value = value.trim().trim_end_matches(',');
        if value.len() < 2 || !value.starts_with('"') || !value.ends_with('"') {
            continue;
        }
        map.push((name.to_string(), unescape_lua(&value[1..value.len() - 1])));
    }
    map
}

/// `routes` table: `{ class = cls.<alias>, id = <n>, ... }` lines.
pub fn parse_lua_routes(content: &str) -> Vec<Rule> {
    let cls = parse_lua_cls(content);
    if cls.is_empty() {
        return Vec::new();
    }
    let Some(block) = lua_table(content, "routes") else {
        return Vec::new();
    };
    let mut rules = Vec::new();
    for line in block.lines() {
        let line = line.trim();
        if line.starts_with("--") || !line.contains("class") || !line.contains("id") {
            continue;
        }
        let alias = field_after(line, "cls.");
        let id = field_after(line, "id = ");
        let (Some(alias), Some(id)) = (alias, id) else {
            continue;
        };
        let alias = alias.trim_end_matches(|ch: char| !ch.is_alphanumeric() && ch != '_');
        let id = id
            .trim_end_matches(|ch: char| !ch.is_ascii_digit())
            .to_string();
        if id.is_empty() {
            continue;
        }
        if let Some((_, pattern)) = cls.iter().find(|(name, _)| name == alias) {
            rules.push(Rule {
                workspace: id,
                kind: MatchKind::Class,
                pattern: pattern.clone(),
            });
        }
    }
    rules
}

/// Value that follows `prefix` in a Lua table line, up to the next separator.
fn field_after<'a>(line: &'a str, prefix: &str) -> Option<&'a str> {
    let start = line.find(prefix)? + prefix.len();
    let rest = &line[start..];
    let end = rest.find([',', '}']).unwrap_or(rest.len());
    Some(rest[..end].trim())
}

/// Legacy `hyprland.conf`: `windowrule(v2)` lines with a workspace action.
pub fn parse_conf(path: &Path, visited: &mut Vec<PathBuf>) -> Vec<Rule> {
    let real = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    if visited.contains(&real) {
        return Vec::new();
    }
    visited.push(real.clone());
    let Ok(content) = std::fs::read_to_string(&real) else {
        eprintln!("Warning: could not read config file {}", path.display());
        return Vec::new();
    };
    let mut rules = Vec::new();
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("source") {
            if let Some((_, target)) = rest.split_once('=') {
                let target = target.trim();
                if target.contains('*') || target.contains('?') {
                    // Glob includes are not expanded here; the Lua config is
                    // the canonical format and plain paths cover the rest.
                    eprintln!("Warning: glob include not supported: {target}");
                    continue;
                }
                rules.extend(parse_conf(&expand(target), visited));
            }
            continue;
        }
        if !line.starts_with("windowrule") {
            continue;
        }
        let Some((keyword, definition)) = line.split_once('=') else {
            continue;
        };
        let Some((action, condition)) = definition.split_once(',') else {
            continue;
        };
        let action = action.trim();
        let Some(workspace) = action.strip_prefix("workspace") else {
            continue;
        };
        let Some(id) = workspace.split_whitespace().next() else {
            continue;
        };
        let condition = condition.trim();
        let (kind, pattern) = if keyword.trim().starts_with("windowrulev2") {
            let Some((selector, pattern)) = condition.split_once(':') else {
                continue;
            };
            let Some(kind) = MatchKind::from_selector(selector.trim()) else {
                continue;
            };
            (kind, pattern.trim().to_string())
        } else {
            (MatchKind::Class, condition.to_string())
        };
        if !id.is_empty() && !pattern.is_empty() {
            rules.push(Rule {
                workspace: id.to_string(),
                kind,
                pattern,
            });
        }
    }
    rules
}

/// Routing rules from the Lua config, falling back to the legacy `.conf`.
pub fn config_rules() -> Vec<Rule> {
    let lua = home_dir().join(".config/hypr/hyprland.lua");
    if lua.is_file() {
        if let Ok(content) = std::fs::read_to_string(&lua) {
            let rules = parse_lua_routes(&content);
            if !rules.is_empty() {
                return rules;
            }
        }
    }
    let conf = home_dir().join(".config/hypr/hyprland.conf");
    parse_conf(&conf, &mut Vec::new())
}

/// Workspace of the first rule that matches the client, if any.
pub fn match_rule(client: &json::Value, rules: &[Rule]) -> Option<String> {
    for rule in rules {
        if pattern::search(&rule.pattern, rule.kind.field(client)) {
            return Some(rule.workspace.clone());
        }
    }
    None
}

// -- hyprctl -----------------------------------------------------------

fn hyprctl(args: &[&str]) -> Option<String> {
    let output = Command::new("hyprctl")
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

pub fn clients() -> Vec<json::Value> {
    let Some(out) = hyprctl(&["-j", "clients"]) else {
        eprintln!("Error running hyprctl -j clients");
        std::process::exit(1);
    };
    match json::parse(&out) {
        Some(json::Value::Array(items)) => items,
        _ => {
            eprintln!("Error parsing JSON from hyprctl -j clients");
            std::process::exit(1);
        }
    }
}

fn main() -> std::process::ExitCode {
    let dry_run = std::env::args().skip(1).any(|arg| arg == "--dry-run");
    let clients = clients();
    let rules = config_rules();
    println!(
        "Found {} clients and {} workspace rules.",
        clients.len(),
        rules.len()
    );

    let mut moves: Vec<(String, String)> = Vec::new();
    for client in &clients {
        let Some(address) = client.get("address").and_then(json::Value::as_str) else {
            continue;
        };
        let Some(workspace) = client.get("workspace") else {
            continue;
        };
        let id = workspace
            .get("id")
            .and_then(json::Value::as_i64)
            .unwrap_or(0);
        let name = workspace
            .get("name")
            .and_then(json::Value::as_str)
            .unwrap_or("");
        // Special workspaces have negative ids; they are not routed.
        if id < 0 {
            continue;
        }
        let Some(target) = match_rule(client, &rules) else {
            continue;
        };
        let current_id = id.to_string();
        if target == current_id || target == name {
            continue;
        }
        if let Some(stripped) = target.strip_prefix("name:") {
            if stripped == name {
                continue;
            }
        }
        let class = client
            .get("class")
            .and_then(json::Value::as_str)
            .unwrap_or("");
        let title = client
            .get("title")
            .and_then(json::Value::as_str)
            .unwrap_or("");
        let short: String = title.chars().take(20).collect();
        println!("Match: {class} ({short}...) -> Rule target: {target} (Current: {name})");
        moves.push((address.to_string(), target));
    }

    if moves.is_empty() {
        println!("No windows need moving.");
        return std::process::ExitCode::SUCCESS;
    }
    println!("\nMoving {} windows...", moves.len());

    let commands: Vec<String> = moves
        .iter()
        .map(|(address, workspace)| {
            format!("dispatch movetoworkspacesilent {workspace},address:{address}")
        })
        .collect();

    if dry_run {
        for command in &commands {
            println!("[DRY RUN] {command}");
        }
        return std::process::ExitCode::SUCCESS;
    }
    let batch = commands.join(" ; ");
    match Command::new("hyprctl").args(["--batch", &batch]).status() {
        Ok(status) if status.success() => {
            println!("Done.");
            std::process::ExitCode::SUCCESS
        }
        Ok(status) => {
            println!("Error executing moves: hyprctl exited with {status}");
            std::process::ExitCode::from(1)
        }
        Err(exc) => {
            println!("Error executing moves: {exc}");
            std::process::ExitCode::from(1)
        }
    }
}

/// The pattern subset Hyprland class/title rules use.
///
/// Anchors (`^`, `$`) are honoured, `.` matches any character, `*`/`+`/`?`
/// repeat the previous atom, `|` alternates, `(...)` groups, `[...]` is a
/// character class (ranges and a leading `^` negation) and a leading `\\`
/// escapes a metacharacter. An unanchored pattern matches anywhere, like
/// `re.search`.
pub mod pattern {
    #[derive(Debug, Clone)]
    enum Node {
        Char(char),
        Any,
        Class {
            negated: bool,
            ranges: Vec<(char, char)>,
        },
        Group(Vec<Vec<Node>>),
        Repeat {
            node: Box<Node>,
            min: usize,
            max: Option<usize>,
        },
        Start,
        End,
    }

    fn parse(pattern: &str) -> Option<(Vec<Node>, bool, bool)> {
        let chars: Vec<char> = pattern.chars().collect();
        let mut parser = Parser { chars, pos: 0 };
        let mut anchored_start = false;
        let mut anchored_end = false;
        if parser.peek() == Some('^') {
            anchored_start = true;
            parser.pos += 1;
        }
        let nodes = parser.alternation()?;
        if parser.peek() == Some('$') {
            anchored_end = true;
            parser.pos += 1;
        }
        if parser.pos != parser.chars.len() {
            return None;
        }
        Some((nodes, anchored_start, anchored_end))
    }

    struct Parser {
        chars: Vec<char>,
        pos: usize,
    }

    impl Parser {
        fn peek(&self) -> Option<char> {
            self.chars.get(self.pos).copied()
        }

        fn alternation(&mut self) -> Option<Vec<Node>> {
            let mut branches = vec![self.sequence()?];
            while self.peek() == Some('|') {
                self.pos += 1;
                branches.push(self.sequence()?);
            }
            if branches.len() == 1 {
                branches.pop()
            } else {
                Some(vec![Node::Group(branches)])
            }
        }

        fn sequence(&mut self) -> Option<Vec<Node>> {
            let mut nodes = Vec::new();
            while let Some(ch) = self.peek() {
                if ch == '|' || ch == ')' {
                    break;
                }
                let atom = self.atom()?;
                let atom = self.quantifier(atom);
                nodes.push(atom);
            }
            Some(nodes)
        }

        fn quantifier(&mut self, atom: Node) -> Node {
            let (min, max) = match self.peek() {
                Some('*') => (0, None),
                Some('+') => (1, None),
                Some('?') => (0, Some(1)),
                _ => return atom,
            };
            self.pos += 1;
            Node::Repeat {
                node: Box::new(atom),
                min,
                max,
            }
        }

        fn atom(&mut self) -> Option<Node> {
            let ch = self.peek()?;
            self.pos += 1;
            Some(match ch {
                '.' => Node::Any,
                '(' => {
                    // `alternation` already collapses a single branch, so wrap
                    // it back into a one-branch group.
                    let content = self.alternation()?;
                    if self.peek() != Some(')') {
                        return None;
                    }
                    self.pos += 1;
                    Node::Group(vec![content])
                }
                '[' => {
                    let mut negated = false;
                    if self.peek() == Some('^') {
                        negated = true;
                        self.pos += 1;
                    }
                    let mut ranges = Vec::new();
                    let mut first = true;
                    loop {
                        let ch = self.peek()?;
                        self.pos += 1;
                        if ch == ']' && !first {
                            break;
                        }
                        first = false;
                        let low = if ch == '\\' {
                            let escaped = self.peek()?;
                            self.pos += 1;
                            escaped
                        } else {
                            ch
                        };
                        if self.peek() == Some('-')
                            && self.chars.get(self.pos + 1).copied() != Some(']')
                        {
                            self.pos += 1;
                            let high = self.peek()?;
                            self.pos += 1;
                            ranges.push((low, high));
                        } else {
                            ranges.push((low, low));
                        }
                    }
                    Node::Class { negated, ranges }
                }
                '\\' => {
                    let escaped = self.peek()?;
                    self.pos += 1;
                    Node::Char(escaped)
                }
                '^' => Node::Start,
                '$' => Node::End,
                other => Node::Char(other),
            })
        }
    }

    fn match_nodes(nodes: &[Node], text: &[char], pos: usize) -> Option<usize> {
        let Some((first, rest)) = nodes.split_first() else {
            return Some(pos);
        };
        match first {
            Node::Char(expected) => {
                if text.get(pos) == Some(expected) {
                    match_nodes(rest, text, pos + 1)
                } else {
                    None
                }
            }
            Node::Any => {
                if text.get(pos).is_some() {
                    match_nodes(rest, text, pos + 1)
                } else {
                    None
                }
            }
            Node::Class { negated, ranges } => {
                let hit = text.get(pos).is_some_and(|ch| {
                    ranges.iter().any(|(low, high)| (low..=high).contains(&ch)) != *negated
                });
                if hit {
                    match_nodes(rest, text, pos + 1)
                } else {
                    None
                }
            }
            Node::Group(branches) => {
                for branch in branches {
                    let mut combined = branch.clone();
                    combined.extend_from_slice(rest);
                    if let Some(end) = match_nodes(&combined, text, pos) {
                        return Some(end);
                    }
                }
                None
            }
            Node::Repeat { node, min, max } => match_repeat(node, *min, *max, 0, text, pos, rest),
            Node::Start => {
                if pos == 0 {
                    match_nodes(rest, text, pos)
                } else {
                    None
                }
            }
            Node::End => {
                if pos == text.len() {
                    match_nodes(rest, text, pos)
                } else {
                    None
                }
            }
        }
    }

    fn match_repeat(
        node: &Node,
        min: usize,
        max: Option<usize>,
        count: usize,
        text: &[char],
        pos: usize,
        rest: &[Node],
    ) -> Option<usize> {
        // Greedy: extend by one iteration first, and only then let the tail
        // match, which is what gives `a+` and `.*` their longest-match
        // behaviour with backtracking.
        if max.is_none_or(|max| count < max) {
            let single = std::slice::from_ref(node);
            if let Some(end) = match_nodes(single, text, pos) {
                if end > pos {
                    if let Some(result) = match_repeat(node, min, max, count + 1, text, end, rest) {
                        return Some(result);
                    }
                }
            }
        }
        if count >= min {
            return match_nodes(rest, text, pos);
        }
        None
    }

    /// `re.search` semantics: the pattern may match anywhere unless anchored.
    pub fn search(pattern: &str, haystack: &str) -> bool {
        let Some((nodes, anchored_start, anchored_end)) = parse(pattern) else {
            return false;
        };
        let mut sequence = nodes;
        if anchored_end {
            sequence.push(Node::End);
        }
        let text: Vec<char> = haystack.chars().collect();
        if anchored_start {
            let mut prefixed = vec![Node::Start];
            prefixed.extend(sequence);
            return match_nodes(&prefixed, &text, 0).is_some();
        }
        for start in 0..=text.len() {
            if match_nodes(&sequence, &text, start).is_some() {
                return true;
            }
        }
        false
    }
}

/// Compact JSON reader for `hyprctl -j clients`.
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
    fn patterns_match_like_search() {
        assert!(pattern::search("^(term)$", "term"));
        assert!(!pattern::search("^(term)$", "terms"));
        assert!(pattern::search("^(steam|Steam)$", "Steam"));
        assert!(pattern::search(
            "^([Vv]ivaldi-stable|[Vv]ivaldi)$",
            "Vivaldi"
        ));
        assert!(pattern::search("firefox", "org.mozilla.firefox"));
        assert!(pattern::search("^swayimg(_[0-9]+)?$", "swayimg_42"));
        assert!(!pattern::search("^swayimg(_[0-9]+)?$", "swayimg_x"));
        assert!(pattern::search(".*\\.exe", "setup.exe"));
        assert!(!pattern::search(".*\\.exe", "setup.msi"));
        // A broken pattern matches nothing instead of panicking.
        assert!(!pattern::search("(", "anything"));
    }

    #[test]
    fn lua_tables_are_read() {
        let content = r#"
local cls = {
  term        = "^(term)$",
  web         = "^([Vv]ivaldi-stable|[Vv]ivaldi)$",
  --  wine     = "^(com.usebottles.bottles)$",
}

local routes = {
  { class = cls.term,        id = 1,  no_blur = true },
  { class = cls.web,         id = 2 },
  { class = cls.unknown,     id = 3 },
}
"#;
        let rules = parse_lua_routes(content);
        assert_eq!(rules.len(), 2);
        assert_eq!(
            rules[0],
            Rule {
                workspace: "1".to_string(),
                kind: MatchKind::Class,
                pattern: "^(term)$".to_string()
            }
        );
        assert_eq!(rules[1].workspace, "2");
        assert_eq!(rules[1].pattern, "^([Vv]ivaldi-stable|[Vv]ivaldi)$");
    }

    #[test]
    fn legacy_conf_rules_are_read() {
        let dir = std::env::temp_dir().join(format!("hypr-rearrange-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let nested = dir.join("extra.conf");
        std::fs::write(
            &nested,
            "windowrulev2 = workspace 7 silent, class:^(mpv)$\n",
        )
        .unwrap();
        let main = dir.join("hyprland.conf");
        std::fs::write(
            &main,
            format!(
                "# comment\nwindowrulev2 = workspace 3, class:^(nwim)$\n\
                 windowrule = workspace 4, ^(sioyek)$\n\
                 windowrulev2 = float, class:^(ignored)$\n\
                 source = {}\n",
                nested.display()
            ),
        )
        .unwrap();
        let rules = parse_conf(&main, &mut Vec::new());
        assert_eq!(rules.len(), 3);
        assert_eq!(rules[0].workspace, "3");
        assert_eq!(rules[0].kind, MatchKind::Class);
        assert_eq!(rules[1].workspace, "4");
        assert_eq!(rules[2].workspace, "7");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn rules_are_matched_in_order() {
        let rules = vec![
            Rule {
                workspace: "1".to_string(),
                kind: MatchKind::Class,
                pattern: "^(term)$".to_string(),
            },
            Rule {
                workspace: "2".to_string(),
                kind: MatchKind::Title,
                pattern: ".*\\.exe".to_string(),
            },
        ];
        let client =
            json::parse(r#"{"class": "term", "title": "setup.exe", "address": "0x1"}"#).unwrap();
        assert_eq!(match_rule(&client, &rules).as_deref(), Some("1"));
        let client = json::parse(r#"{"class": "other", "title": "setup.exe"}"#).unwrap();
        assert_eq!(match_rule(&client, &rules).as_deref(), Some("2"));
        let client = json::parse(r#"{"class": "other", "title": "notes"}"#).unwrap();
        assert_eq!(match_rule(&client, &rules), None);
    }

    #[test]
    fn lua_escapes_are_unescaped() {
        assert_eq!(unescape_lua(r"a\\b"), r"a\b");
        assert_eq!(unescape_lua(r#"a\"b"#), "a\"b");
        assert_eq!(unescape_lua(r"a\nb"), "a\nb");
    }
}
