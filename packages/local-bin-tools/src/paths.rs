//! paths — the repo path resolver, from the shell.
//!
//! The Nix side addresses files by name (`config.lib.neg.path "files/x"`,
//! `r.path "files/x"`, `paths.path "files/x"`). This tool answers the questions
//! that convention raises:
//!
//!     paths keys [DIR]      the dotted key to write in Nix for each file
//!     paths refs QUERY      every .nix line referencing QUERY ("who uses this?")
//!     paths find [QUERY]    fuzzy-pick a tracked file and show its references
//!     paths resolve REF     resolve a relative REF to an absolute path
//!
//! Options: `--root DIR` (default: the git top level), `--all` also searches
//! non-`.nix` files in `refs`, `find --no-fzf` never opens the picker.
//! Exit status: 0 on success, 1 when nothing matched.
//!
//! Port of `packages/local-bin/bin/paths`.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn repo_root(explicit: Option<&str>) -> PathBuf {
    if let Some(path) = explicit {
        return std::fs::canonicalize(path).unwrap_or_else(|_| PathBuf::from(path));
    }
    match Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            PathBuf::from(text)
        }
        _ => std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    }
}

/// `^[A-Za-z_][A-Za-z0-9_'-]*$`
fn is_ident(key: &str) -> bool {
    let mut chars = key.chars();
    match chars.next() {
        Some(first) if first.is_ascii_alphabetic() || first == '_' => {}
        _ => return false,
    }
    chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '\'' || ch == '-')
}

fn dotted(keys: &[String]) -> String {
    keys.iter()
        .map(|key| {
            if is_ident(key) {
                key.clone()
            } else {
                format!("\"{key}\"")
            }
        })
        .collect::<Vec<_>>()
        .join(".")
}

/// Relative path without touching the filesystem (like `os.path.relpath` for the
/// plain `root/…` case this tool sees).
fn relative(root: &Path, value: &str) -> String {
    let root_text = root.display().to_string();
    match value.strip_prefix(&format!("{root_text}/")) {
        Some(rest) => rest.to_string(),
        None => value.to_string(),
    }
}

fn keys_command(root: &Path, directory: &str, extension: &str, any: bool) -> i32 {
    let extensions = if any {
        "\"any\"".to_string()
    } else {
        format!("[ \"{extension}\" ]")
    };
    let root_path = root.to_path_buf();
    let root = root.display();
    let expr = format!(
        "\n      let\n        neg = import {root}/lib/neg-helpers.nix;\n        paths = neg.rooted {root};\n        tree = paths.tree {{ dir = \"{directory}\"; extensions = {extensions}; }};\n      in\n      map (l: {{ key = l.path; value = toString l.value; }}) (neg.leaves tree)\n    "
    );
    let output = Command::new("nix")
        .args(["eval", "--impure", "--json", "--expr", &expr])
        .stdin(Stdio::null())
        .output();
    let output = match output {
        Ok(output) => output,
        Err(exc) => {
            eprintln!("paths: cannot run nix: {exc}");
            return 1;
        }
    };
    if !output.status.success() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
        return 1;
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let Some(json::Value::Array(leaves)) = json::parse(&text) else {
        eprintln!("paths: nix eval returned unexpected JSON");
        return 1;
    };
    if leaves.is_empty() {
        eprintln!("paths: nothing addressable under {directory}/");
        return 1;
    }
    let mut rows: Vec<(String, String)> = leaves
        .iter()
        .filter_map(|leaf| {
            let keys: Vec<String> = match leaf.get("key") {
                Some(json::Value::Array(items)) => items
                    .iter()
                    .filter_map(|item| item.as_str().map(str::to_string))
                    .collect(),
                _ => return None,
            };
            let value = leaf
                .get("value")
                .and_then(json::Value::as_str)
                .unwrap_or("");
            Some((dotted(&keys), relative(&root_path, value)))
        })
        .collect();
    rows.sort_by(|left, right| left.0.cmp(&right.0));
    let width = rows.iter().map(|(key, _)| key.len()).max().unwrap_or(0);
    for (key, rel) in rows {
        println!("{}  {rel}", pad(&key, width));
    }
    0
}

fn pad(text: &str, width: usize) -> String {
    let mut out = text.to_string();
    while out.chars().count() < width {
        out.push(' ');
    }
    out
}

fn grep(root: &Path, query: &str, all_files: bool) -> Vec<String> {
    let glob = if all_files { "*" } else { "*.nix" };
    let output = Command::new("rg")
        .args([
            "--line-number",
            "--no-heading",
            "--color",
            "never",
            "--glob",
            glob,
            "--",
            query,
            ".",
        ])
        .current_dir(root)
        .stdin(Stdio::null())
        .output();
    match output {
        // rg finishes files in parallel, so its own order changes between runs;
        // sorting keeps `paths refs` stable in scripts and diffs.
        Ok(output) => {
            let mut hits: Vec<String> = String::from_utf8_lossy(&output.stdout)
                .lines()
                .filter(|line| !line.trim().is_empty())
                .map(str::to_string)
                .collect();
            hits.sort();
            hits
        }
        Err(_) => Vec::new(),
    }
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut root_arg: Option<String> = None;
    let mut rest: Vec<String> = Vec::new();
    let mut index = 0;
    while index < args.len() {
        match args[index].as_str() {
            "--root" => {
                index += 1;
                root_arg = args.get(index).cloned();
            }
            other => rest.push(other.to_string()),
        }
        index += 1;
    }
    let root = repo_root(root_arg.as_deref());
    let Some(command) = rest.first().cloned() else {
        eprintln!("usage: paths [--root DIR] {{keys,refs,find,resolve}} …");
        return std::process::ExitCode::from(2);
    };
    let tail: Vec<String> = rest[1..].to_vec();
    let code = match command.as_str() {
        "keys" => {
            let directory = tail.first().cloned().unwrap_or_else(|| "files".to_string());
            let mut extension = ".nix".to_string();
            let mut any = false;
            let mut position = 1;
            while position < tail.len() {
                match tail[position].as_str() {
                    "--ext" => {
                        position += 1;
                        if let Some(value) = tail.get(position) {
                            extension = value.clone();
                        }
                    }
                    "--any" => any = true,
                    _ => {}
                }
                position += 1;
            }
            keys_command(&root, &directory, &extension, any)
        }
        "refs" => {
            let query = tail.first().cloned().unwrap_or_default();
            let all = tail.iter().any(|flag| flag == "--all");
            let hits = grep(&root, &query, all);
            if hits.is_empty() {
                eprintln!("paths: no reference to '{query}'");
                1
            } else {
                for line in hits {
                    println!("{line}");
                }
                0
            }
        }
        "find" => {
            let query = tail
                .iter()
                .find(|arg| !arg.starts_with('-'))
                .cloned()
                .unwrap_or_default();
            let no_fzf = tail.iter().any(|flag| flag == "--no-fzf");
            let listing = Command::new("git")
                .args(["ls-files"])
                .current_dir(&root)
                .output()
                .map(|output| String::from_utf8_lossy(&output.stdout).to_string())
                .unwrap_or_default();
            let candidates: Vec<String> = listing
                .lines()
                .filter(|file| query.is_empty() || file.contains(&query))
                .map(str::to_string)
                .collect();
            if candidates.is_empty() {
                eprintln!("paths: no tracked file matches '{query}'");
                return std::process::ExitCode::from(1);
            }
            let chosen = if candidates.len() > 1 && !no_fzf {
                match Command::new("fzf")
                    .args([
                        "--prompt",
                        "path> ",
                        "--preview",
                        "git log -1 --format='%h %s' -- {}",
                    ])
                    .current_dir(&root)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .spawn()
                    .and_then(|mut child| {
                        use std::io::Write as _;
                        if let Some(stdin) = child.stdin.take() {
                            let mut stdin = stdin;
                            let _ = stdin.write_all(candidates.join("\n").as_bytes());
                        }
                        child.wait_with_output()
                    }) {
                    Ok(output) if output.status.success() => {
                        String::from_utf8_lossy(&output.stdout).trim().to_string()
                    }
                    _ => return std::process::ExitCode::from(1),
                }
            } else {
                candidates[0].clone()
            };
            println!("{chosen}");
            let basename = Path::new(&chosen)
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_default();
            let hits = grep(&root, &basename, false);
            if !hits.is_empty() {
                println!();
                println!("# referenced by ({}):", hits.len());
                for line in hits.iter().take(20) {
                    println!("{line}");
                }
            }
            0
        }
        "resolve" => {
            let mut reference = String::new();
            let mut from: Option<String> = None;
            let mut position = 0;
            while position < tail.len() {
                match tail[position].as_str() {
                    "--from" => {
                        position += 1;
                        from = tail.get(position).cloned();
                    }
                    other => reference = other.to_string(),
                }
                position += 1;
            }
            let base = match &from {
                Some(file) => {
                    let joined = root.join(file);
                    joined
                        .parent()
                        .map(|parent| parent.to_path_buf())
                        .unwrap_or(root.clone())
                }
                None => root.clone(),
            };
            let target = normalize(&base.join(&reference));
            println!("{}", target.display());
            let root_text = format!("{}/", root.display());
            if !target.display().to_string().starts_with(&root_text) {
                eprintln!(
                    "paths: '{reference}' leaves the repository — write it as a root-relative name instead (config.lib.neg.path \"…\", r.path \"…\" or neg.rooted)"
                );
                return std::process::ExitCode::from(1);
            }
            if target.exists() {
                0
            } else {
                1
            }
        }
        other => {
            eprintln!("paths: unknown command {other}");
            2
        }
    };
    std::process::ExitCode::from(code as u8)
}

/// Lexical normalisation: resolve `.`/`..` without touching the filesystem.
fn normalize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            std::path::Component::ParentDir => {
                out.pop();
            }
            std::path::Component::CurDir => {}
            other => out.push(other),
        }
    }
    out
}

/// Minimal JSON reader for `nix eval --json`.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifiers_are_quoted_only_when_needed() {
        assert!(is_ident("files"));
        assert!(is_ident("hdr-auto-switch"));
        assert!(is_ident("a_1'"));
        assert!(!is_ident("1abc"));
        assert!(!is_ident("with space"));
        assert_eq!(
            dotted(&[
                "files".to_string(),
                "mpv".to_string(),
                "hdr auto".to_string()
            ]),
            "files.mpv.\"hdr auto\""
        );
    }

    #[test]
    fn paths_are_normalised_lexically() {
        let root = Path::new("/repo");
        assert_eq!(normalize(&root.join("a/../b")), PathBuf::from("/repo/b"));
        assert_eq!(normalize(&root.join("./x")), PathBuf::from("/repo/x"));
        assert_eq!(
            normalize(&root.join("../../outside")),
            PathBuf::from("/outside")
        );
    }

    #[test]
    fn relatives_are_trimmed_to_the_repo() {
        let root = Path::new("/repo");
        assert_eq!(relative(root, "/repo/files/x.nix"), "files/x.nix");
        assert_eq!(relative(root, "/elsewhere/x"), "/elsewhere/x");
    }
}
