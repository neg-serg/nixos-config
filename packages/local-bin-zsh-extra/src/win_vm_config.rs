//! The subset of zsh variable handling that `win-vm` needs from its
//! `config.sh`.
//!
//! The original sources the file as shell code. This port understands plain
//! assignments (`NAME=value`, optional `export`, single/double quotes,
//! backslash escapes, `$NAME`/`${NAME}` expansion, the `${NAME:-word}` family
//! and leading `~`), which is what the shipped template and the documented
//! knobs use. Command substitutions, conditionals and loops are not executed:
//! the config is configuration, not a program. A line that does not parse as
//! an assignment is ignored, the way a comment would be.

use std::collections::BTreeMap;

pub type Vars = BTreeMap<String, String>;

/// `: "${NAME:=default}"`: a non-empty environment value wins, otherwise the
/// default is stored.
pub fn set_default(vars: &mut Vars, name: &str, default: &str) {
    let value = match std::env::var_os(name) {
        Some(value) if !value.is_empty() => value.to_string_lossy().into_owned(),
        _ => default.to_string(),
    };
    vars.insert(name.to_string(), value);
}

pub fn parse_config(text: &str, vars: &mut Vars) {
    for raw in logical_lines(text) {
        let line = raw.trim_start();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let line = match line.strip_prefix("export ") {
            Some(rest) => rest.trim_start(),
            None => line,
        };
        let Some(equals) = line.find('=') else {
            continue;
        };
        let name = &line[..equals];
        if !is_variable_name(name) {
            continue;
        }
        let value = parse_word(&line[equals + 1..], vars);
        vars.insert(name.to_string(), value);
    }
}

fn is_variable_name(name: &str) -> bool {
    let mut characters = name.chars();
    match characters.next() {
        Some(first) if first.is_ascii_alphabetic() || first == '_' => {}
        _ => return false,
    }
    characters.all(|character| character.is_ascii_alphanumeric() || character == '_')
}

/// Join lines whose last character is an unescaped backslash (`\` + newline).
fn logical_lines(text: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();
    for line in text.split('\n') {
        let trailing = line
            .as_bytes()
            .iter()
            .rev()
            .take_while(|byte| **byte == b'\\')
            .count();
        if trailing % 2 == 1 {
            current.push_str(&line[..line.len() - 1]);
        } else {
            current.push_str(line);
            lines.push(std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        lines.push(current);
    }
    lines
}

/// Parse one shell word, expanding quotes, escapes and variables. Trailing
/// words on the same line (and comments after whitespace) are ignored.
fn parse_word(text: &str, vars: &Vars) -> String {
    let characters: Vec<char> = text.chars().collect();
    let mut result = String::new();
    let mut index = 0;
    let mut quote: Option<char> = None;
    let mut at_start = true;
    while index < characters.len() {
        let character = characters[index];
        match quote {
            Some('\'') => {
                if character == '\'' {
                    quote = None;
                } else {
                    result.push(character);
                }
                index += 1;
            }
            Some('"') => {
                if character == '"' {
                    quote = None;
                    index += 1;
                } else if character == '\\'
                    && index + 1 < characters.len()
                    && matches!(characters[index + 1], '$' | '`' | '"' | '\\' | '\n')
                {
                    result.push(characters[index + 1]);
                    index += 2;
                } else if character == '$' {
                    let (value, next) = expand(&characters, index, vars);
                    result.push_str(&value);
                    index = next;
                } else {
                    result.push(character);
                    index += 1;
                }
            }
            Some(_) => {}
            None => {
                if character.is_whitespace() {
                    break;
                }
                match character {
                    '\'' => {
                        quote = Some('\'');
                        index += 1;
                    }
                    '"' => {
                        quote = Some('"');
                        index += 1;
                    }
                    '\\' => {
                        if index + 1 < characters.len() {
                            if characters[index + 1] != '\n' {
                                result.push(characters[index + 1]);
                            }
                            index += 2;
                        } else {
                            index += 1;
                        }
                    }
                    '$' => {
                        let (value, next) = expand(&characters, index, vars);
                        result.push_str(&value);
                        index = next;
                    }
                    '~' if at_start
                        && (index + 1 == characters.len() || characters[index + 1] == '/') =>
                    {
                        result.push_str(&home(vars));
                        index += 1;
                    }
                    _ => {
                        result.push(character);
                        index += 1;
                    }
                }
            }
        }
        at_start = false;
    }
    result
}

fn home(vars: &Vars) -> String {
    lookup(vars, "HOME")
}

fn lookup(vars: &Vars, name: &str) -> String {
    lookup_option(vars, name).unwrap_or_default()
}

fn lookup_option(vars: &Vars, name: &str) -> Option<String> {
    if let Some(value) = vars.get(name) {
        return Some(value.clone());
    }
    std::env::var(name).ok()
}

/// Expand `$` at `index`; returns the replacement and the next index.
fn expand(characters: &[char], index: usize, vars: &Vars) -> (String, usize) {
    let Some(next) = characters.get(index + 1).copied() else {
        return ("$".to_string(), index + 1);
    };
    if next == '{' {
        let mut end = index + 2;
        while end < characters.len() && characters[end] != '}' {
            end += 1;
        }
        if end == characters.len() {
            return ("$".to_string(), index + 1);
        }
        let inside: String = characters[index + 2..end].iter().collect();
        return (expand_braced(&inside, vars), end + 1);
    }
    if next.is_ascii_alphabetic() || next == '_' {
        let mut end = index + 1;
        while end < characters.len()
            && (characters[end].is_ascii_alphanumeric() || characters[end] == '_')
        {
            end += 1;
        }
        let name: String = characters[index + 1..end].iter().collect();
        return (lookup(vars, &name), end);
    }
    ("$".to_string(), index + 1)
}

fn expand_braced(inside: &str, vars: &Vars) -> String {
    for operator in [":-", ":=", "-", "="] {
        if let Some((name, word)) = inside.split_once(operator) {
            let value = lookup_option(vars, name);
            let take_default = match operator {
                ":-" | ":=" => value.as_deref().map(str::is_empty).unwrap_or(true),
                _ => value.is_none(),
            };
            if take_default {
                return expand_inline(word, vars);
            }
            return value.unwrap_or_default();
        }
    }
    if is_variable_name(inside) {
        lookup(vars, inside)
    } else {
        String::new()
    }
}

/// Minimal expansion for the default word of `${NAME:-word}`; quotes are not
/// interpreted there, which matches the simple defaults used in config files.
fn expand_inline(text: &str, vars: &Vars) -> String {
    let characters: Vec<char> = text.chars().collect();
    let mut result = String::new();
    let mut index = 0;
    while index < characters.len() {
        if characters[index] == '$' {
            let (value, next) = expand(&characters, index, vars);
            result.push_str(&value);
            index = next;
        } else {
            result.push(characters[index]);
            index += 1;
        }
    }
    result
}
