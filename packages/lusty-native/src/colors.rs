//! LS_COLORS parsing and per-entry coloring.
//!
//! Semantics follow GNU ls: type codes first (ln/di/so/pi/bd/cd/ex), then
//! extension rules, matched case-insensitively on the end of the name with
//! the longest matching key winning (so *.tar.gz beats *.gz). Rules with
//! extra wildcards or character classes fall back to a full-name glob scan.
//! SGR codes pass through verbatim: a style like 01;34 is ESC[01;34m.
use std::collections::HashMap;
use std::path::Path;

use crate::listing::FileKind;

pub struct Colors {
    types: HashMap<String, String>,
    /// (lowercased suffix without the leading '*', code), e.g. ("tar.gz", ..)
    suffix: Vec<(String, String)>,
    /// (lowercased full pattern, code) for rules with extra wildcards/classes
    complex: Vec<(String, String)>,
}

impl Colors {
    pub fn parse(env: &str) -> Colors {
        let mut types: HashMap<String, String> = HashMap::new();
        let mut suffix: Vec<(String, String)> = Vec::new();
        let mut complex: Vec<(String, String)> = Vec::new();
        for item in env.split(':') {
            let Some((k, v)) = item.split_once('=') else {
                continue;
            };
            if k.len() == 2 {
                types.insert(k.to_string(), v.to_string());
            } else if let Some(rest) = k.strip_prefix('*') {
                if !rest.contains(['*', '?', '[']) {
                    suffix.push((rest.to_ascii_lowercase(), v.to_string()));
                } else {
                    complex.push((k.to_ascii_lowercase(), v.to_string()));
                }
            }
        }
        Colors {
            types,
            suffix,
            complex,
        }
    }

    /// Resolve the style code for one entry. The is_exec flag is only
    /// consulted for plain files (the caller stats lazily when painting).
    pub fn code_for(&self, name: &str, kind: FileKind, is_exec: bool) -> Option<&str> {
        let type_key = match kind {
            FileKind::Link => "ln",
            FileKind::Dir => "di",
            FileKind::Socket => "so",
            FileKind::Pipe => "pi",
            FileKind::Block => "bd",
            FileKind::Char => "cd",
            FileKind::File => "",
        };
        if !type_key.is_empty() {
            if let Some(code) = self.types.get(type_key) {
                return Some(code);
            }
        }
        if kind == FileKind::File && is_exec {
            if let Some(code) = self.types.get("ex") {
                return Some(code);
            }
        }

        // Extension rules: longest matching suffix wins; ties go to the later
        // rule (later LS_COLORS entries override).
        let lname = name.to_ascii_lowercase();
        let mut best: Option<(usize, &str)> = None;
        for (suf, code) in &self.suffix {
            if lname.ends_with(suf.as_str()) && best.map_or(true, |(l, _)| suf.len() >= l) {
                best = Some((suf.len(), code));
            }
        }
        if let Some((_, code)) = best {
            return Some(code);
        }
        for (pat, code) in &self.complex {
            if glob_match(pat, &lname) {
                return Some(code);
            }
        }
        None
    }
}

/// Full-name glob match supporting '*', '?' and '[...]' classes (with '^' or
/// '!' negation and a-b ranges). Both sides are expected to be lowercased.
fn glob_match(pat: &str, text: &str) -> bool {
    let p: Vec<char> = pat.chars().collect();
    let t: Vec<char> = text.chars().collect();
    glob_impl(&p, &t)
}

fn glob_impl(p: &[char], t: &[char]) -> bool {
    if p.is_empty() {
        return t.is_empty();
    }
    match p[0] {
        '*' => {
            let mut i = 0;
            while i < p.len() && p[i] == '*' {
                i += 1;
            }
            glob_impl(&p[i..], t) || (!t.is_empty() && glob_impl(p, &t[1..]))
        }
        '?' => !t.is_empty() && glob_impl(&p[1..], &t[1..]),
        '[' => class_impl(p, t),
        c => !t.is_empty() && c.eq_ignore_ascii_case(&t[0]) && glob_impl(&p[1..], &t[1..]),
    }
}

fn class_impl(p: &[char], t: &[char]) -> bool {
    if t.is_empty() {
        return false;
    }
    let mut idx = 1;
    let mut neg = false;
    if idx < p.len() && (p[idx] == '^' || p[idx] == '!') {
        neg = true;
        idx += 1;
    }
    let start = idx;
    let mut matched = false;
    while idx < p.len() {
        if p[idx] == ']' && idx > start {
            break;
        }
        if idx + 2 < p.len() && p[idx + 1] == '-' && p[idx + 2] != ']' {
            if p[idx] <= t[0] && t[0] <= p[idx + 2] {
                matched = true;
            }
            idx += 3;
        } else {
            if p[idx].eq_ignore_ascii_case(&t[0]) {
                matched = true;
            }
            idx += 1;
        }
    }
    if idx >= p.len() || p[idx] != ']' {
        return false; // unterminated class: no match
    }
    let ok = if neg { !matched } else { matched };
    ok && glob_impl(&p[idx + 1..], &t[1..])
}

/// Extract the LS_COLORS value from a dircolors -b output line.
fn extract(s: &str) -> Option<&str> {
    let i = s.find("LS_COLORS=")? + "LS_COLORS=".len();
    let rest = &s[i..];
    let quote = rest.chars().next()?;
    if quote != '"' && quote != '\'' {
        return None;
    }
    let body = &rest[quote.len_utf8()..];
    let end = body.find(quote)?;
    Some(&body[..end])
}

/// Palette from the environment: LS_COLORS verbatim when set, else the user
/// dircolors file via dircolors -b, else the stock GNU palette.
pub fn load() -> Colors {
    if let Ok(env) = std::env::var("LS_COLORS") {
        if !env.is_empty() {
            return Colors::parse(&env);
        }
    }
    let mut args = vec!["-b".to_string()];
    if let Ok(home) = std::env::var("HOME") {
        let user_file = format!("{}/.config/dircolors/dircolors", home);
        if Path::new(&user_file).exists() {
            args.push(user_file);
        }
    }
    if let Ok(out) = std::process::Command::new("dircolors").args(&args).output() {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout);
            if let Some(env) = extract(&s) {
                return Colors::parse(env);
            }
        }
    }
    Colors::parse("")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoke_palette_codes() {
        // The exact LS_COLORS used by the nvim smoke tests.
        let c = Colors::parse("di=01;34:ln=01;36:ex=01;32:*.jpg=01;35:*.lua=38;5;114");
        assert_eq!(c.code_for("sub", FileKind::Dir, false), Some("01;34"));
        assert_eq!(c.code_for("pic.jpg", FileKind::File, false), Some("01;35"));
        assert_eq!(
            c.code_for("beta.lua", FileKind::File, false),
            Some("38;5;114")
        );
        assert_eq!(c.code_for("alpha.txt", FileKind::File, false), None);
        assert_eq!(c.code_for("lnk", FileKind::Link, false), Some("01;36"));
        // ex wins over an extension rule for plain files
        assert_eq!(c.code_for("run.lua", FileKind::File, true), Some("01;32"));
    }

    #[test]
    fn case_insensitive_extension() {
        let c = Colors::parse("*.jpg=31");
        assert_eq!(c.code_for("A.JPG", FileKind::File, false), Some("31"));
    }

    #[test]
    fn longest_suffix_wins() {
        let c = Colors::parse("*.gz=33:*.tar.gz=32");
        assert_eq!(c.code_for("x.tar.gz", FileKind::File, false), Some("32"));
        assert_eq!(c.code_for("y.gz", FileKind::File, false), Some("33"));
    }

    #[test]
    fn suffix_globs_match_extensionless_names() {
        let c = Colors::parse("*id_rsa=35:*Dockerfile=36:*.lesshst=37");
        assert_eq!(c.code_for("id_rsa", FileKind::File, false), Some("35"));
        assert_eq!(c.code_for("Dockerfile", FileKind::File, false), Some("36"));
        assert_eq!(c.code_for(".lesshst", FileKind::File, false), Some("37"));
    }

    #[test]
    fn class_glob_matches() {
        let c = Colors::parse("*.part[0-9]=31");
        assert_eq!(c.code_for("x.part7", FileKind::File, false), Some("31"));
        assert_eq!(c.code_for("x.partx", FileKind::File, false), None);
    }

    #[test]
    fn extract_from_dircolors_output() {
        let out = "LS_COLORS=\"di=01;34:*.jpg=01;35\"\nexport LS_COLORS\n";
        assert_eq!(extract(out), Some("di=01;34:*.jpg=01;35"));
        let out2 = "LS_COLORS='di=01;34'\n";
        assert_eq!(extract(out2), Some("di=01;34"));
    }
}
