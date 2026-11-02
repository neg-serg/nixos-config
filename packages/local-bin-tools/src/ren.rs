//! `ren` — pretty file renamer (normalise to the personal naming scheme).
//!
//!     ren [-i] FILES …      -i applies the rename, otherwise only the mapping
//!
//! Directories lose nothing; files keep everything after the last `·` as their
//! extension. The coloured output (`❯` prompt, `~` for `$HOME`, blue separators)
//! matches the Python library the script used to import, so `ren` needs no
//! interpreter and no `PYTHONPATH`.
//!
//! Port of `packages/local-bin/scripts/ren`. Its `re.sub` chain is written out
//! as explicit passes: a "run of SET around SEPARATOR" pattern (like `·*-·*`),
//! a plain run collapse (like `[ _\t\.]+`) and edge trimming.

use std::path::Path;

const SEPARATOR: char = '\u{00b7}';
const OPEN_BRACKET: &str = "\u{27ee}";
const CLOSE_BRACKET: &str = "\u{27ef}";
const OPEN_GLYPH: &str = "\u{276f}";

/// `colored` only emits escapes when stdout is a terminal (and `NO_COLOR` is
/// unset); the plain mode keeps the brackets and the prompt, only without
/// colour. Mirrored here, because scripts and diffs pipe this output.
fn colour_enabled() -> bool {
    use std::io::IsTerminal;
    if std::env::var("NO_COLOR")
        .map(|value| !value.is_empty())
        .unwrap_or(false)
    {
        return false;
    }
    std::io::stdout().is_terminal()
}

fn fg(colour: bool, color: u8) -> String {
    if colour {
        format!("\u{1b}[38;5;{color}m")
    } else {
        String::new()
    }
}

/// `PrettyPrinter._wrap`: the bracket frame.
fn wrap_raw(colour: bool, out: &str) -> String {
    // darkblue, ⟮, darkwhite, out, darkblue, ⟯ — the Python `_wrap` order.
    format!(
        "{}{OPEN_BRACKET}{}{out}{}{CLOSE_BRACKET}",
        fg(colour, 238),
        fg(colour, 7),
        fg(colour, 238)
    )
}

/// `PrettyPrinter.prefix`: the `❯>` prompt.
pub fn prefix() -> String {
    prefix_with(colour_enabled())
}

pub fn prefix_with(colour: bool) -> String {
    wrap_raw(
        colour,
        &format!("{}{}{}>", fg(colour, 25), OPEN_GLYPH, fg(colour, 26)),
    )
}

/// `PrettyPrinter.fancy_file`: `~` for the home prefix and blue separators.
pub fn fancy_file(filename: &str) -> String {
    fancy_file_with(filename, colour_enabled())
}

pub fn fancy_file_with(filename: &str, colour: bool) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let tilde = format!("{}~{}", fg(colour, 2), fg(colour, 7));
    let mut text = filename.replace('~', &tilde);
    if !home.is_empty() {
        text = text.replace(&home, &tilde);
    }
    // `re.sub("([/·])", fg(4) + r"\1" + fg(7))`: colour, character, reset.
    let mut separated = String::with_capacity(text.len());
    for ch in text.chars() {
        if ch == '/' || ch == SEPARATOR {
            separated.push_str(&fg(colour, 4));
            separated.push(ch);
            separated.push_str(&fg(colour, 7));
        } else {
            separated.push(ch);
        }
    }
    wrap_raw(colour, &separated)
}

/// Replace every maximal run of `set` characters with `replacement`.
fn collapse(text: &str, set: &[char], replacement: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut in_run = false;
    for ch in text.chars() {
        if set.contains(&ch) {
            if !in_run {
                out.push_str(replacement);
                in_run = true;
            }
        } else {
            out.push(ch);
            in_run = false;
        }
    }
    out
}

/// `SET* SEP SET*` → `replacement`: a separator with optional run characters on
/// either side (this is `·*-·*`, `[+·\.]*-[+·\.]*` and `[+·\.]*:[+·\.]*`).
fn around_separator(text: &str, set: &[char], separator: char, replacement: &str) -> String {
    let chars: Vec<char> = text.chars().collect();
    let mut out = String::with_capacity(text.len());
    let mut index = 0;
    while index < chars.len() {
        if chars[index] == separator {
            // Take the run back only if it was started in this iteration.
            let mut start = out.len();
            let mut trimmed = 0;
            while trimmed < out.len() {
                let (previous, previous_len) = match out[..start].chars().next_back() {
                    Some(ch) => (ch, ch.len_utf8()),
                    None => break,
                };
                if set.contains(&previous) {
                    start -= previous_len;
                    trimmed += 1;
                } else {
                    break;
                }
            }
            let kept: String = out[..start].to_string();
            out = kept;
            let mut end = index + 1;
            while end < chars.len() && set.contains(&chars[end]) {
                end += 1;
            }
            out.push_str(replacement);
            index = end;
            continue;
        }
        out.push(chars[index]);
        index += 1;
    }
    out
}

/// `fancy_name` from the Python: the rename rules, in the same order.
pub fn fancy_name(filename: &str, file: bool) -> String {
    let mut text = collapse(filename, &[' ', '_', '\t', '.'], &SEPARATOR.to_string());
    text = around_separator(&text, &[SEPARATOR], '-', "-");
    text = around_separator(&text, &['_', '-'], ',', "-");
    text = around_separator(&text, &['+', SEPARATOR, '.'], '-', "-");
    text = around_separator(&text, &['+', SEPARATOR, '.'], ':', ":");
    text = collapse(&text, &['('], "[");
    text = collapse(&text, &[')'], "]");
    text = collapse(&text, &['\'', '`'], "=");
    let edges = ['-', '.', '(', ')', '+', SEPARATOR];
    let trimmed = text
        .trim_matches(|ch: char| edges.contains(&ch))
        .to_string();
    let text = trimmed;
    if file {
        match text.rsplit_once(SEPARATOR) {
            Some((head, tail)) => format!("{head}.{tail}"),
            None => text,
        }
    } else {
        text
    }
}

fn main() -> std::process::ExitCode {
    let mut rename = false;
    let mut files: Vec<String> = Vec::new();
    for argument in std::env::args().skip(1) {
        match argument.as_str() {
            "-i" => rename = true,
            "-h" | "--help" => {
                println!("Usage: ren [-i] FILES ...");
                return std::process::ExitCode::SUCCESS;
            }
            other => files.push(other.to_string()),
        }
    }
    for name in files {
        let path = Path::new(&name);
        if !path.exists() {
            break;
        }
        let directory = path
            .parent()
            .map(|parent| parent.display().to_string())
            .unwrap_or_default();
        let input = path
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_default();
        let output = fancy_name(&input, !path.is_dir());
        if rename {
            let prefix = if directory.is_empty() {
                String::new()
            } else {
                format!("{directory}/")
            };
            if let Err(exc) =
                std::fs::rename(format!("{prefix}{input}"), format!("{prefix}{output}"))
            {
                eprintln!("ren: {exc}");
                return std::process::ExitCode::from(1);
            }
        }
        let directory_out = if directory.is_empty() {
            String::new()
        } else {
            fancy_file(&directory)
        };
        println!(
            "{}{}{} -> {}",
            prefix(),
            directory_out,
            fancy_file(&input),
            fancy_file(&output)
        );
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rename_rules_follow_the_python_chain() {
        // Runs of ` _\t.` become `·`, a lone `-` between them stays.
        assert_eq!(
            fancy_name("Some  File Name.mp3", true),
            "Some·File·Name.mp3"
        );
        assert_eq!(fancy_name("  --weird--  ", false), "weird");
        assert_eq!(fancy_name("a_(1).txt", true), "a·[1].txt");
        assert_eq!(fancy_name("it's.here", true), "it=s.here");
        // `·*-·*` collapses the separators around a dash.
        assert_eq!(fancy_name("x·-·y", false), "x-y");
        assert_eq!(
            fancy_name("Artist - Album - 01 - Track.flac", true),
            "Artist-Album-01-Track.flac"
        );
    }

    #[test]
    fn formatting_matches_the_python_library() {
        std::env::set_var("HOME", "/home/neg");
        assert_eq!(
            prefix_with(true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;25m\u{276f}\u{1b}[38;5;26m>\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            fancy_file_with("~x", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;2m~\u{1b}[38;5;7mx\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            fancy_file_with("/home/neg/a/b.mkv", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;2m~\u{1b}[38;5;7m\u{1b}[38;5;4m/\u{1b}[38;5;7ma\u{1b}[38;5;4m/\u{1b}[38;5;7mb.mkv\u{1b}[38;5;238m\u{27ef}"
        );
        // Piped output keeps the frame but drops the escapes.
        assert_eq!(fancy_file_with("~x", false), "\u{27ee}~x\u{27ef}");
        assert_eq!(prefix_with(false), "\u{27ee}\u{276f}>\u{27ef}");
        std::env::remove_var("HOME");
    }
}
