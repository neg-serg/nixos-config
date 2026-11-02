//! Pretty-printing helpers: colours, brackets and file info lines.
//!
//! Port of `packages/pretty-printer/src/neg_pretty_printer/__init__.py`, whose
//! escapes come from the `colored` package (`fg(n)` is `ESC[38;5;<n>m`, with no
//! reset of its own). The tests pin the exact chains captured from the Python
//! implementation, so output stays byte-identical for anything that greps it.
//!
//! Like `colored`, escapes are only emitted when stdout is a terminal and
//! `NO_COLOR` is unset; the colourless mode keeps the brackets and the glyphs.

use std::io::IsTerminal;
use std::path::Path;

/// Whether escapes should be emitted (mirrors the `colored` package).
pub fn colour_enabled() -> bool {
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

const OPEN_BRACKET: &str = "\u{27ee}";
const CLOSE_BRACKET: &str = "\u{27ef}";
const PROMPT_GLYPH: &str = "\u{276f}";

/// `PrettyPrinter._wrap`: `darkblue + ⟮ + darkwhite + out + darkblue + ⟯`.
fn wrap_raw(colour: bool, out: &str) -> String {
    format!(
        "{}{OPEN_BRACKET}{}{out}{}{CLOSE_BRACKET}",
        fg(colour, 238),
        fg(colour, 7),
        fg(colour, 238)
    )
}

/// `PrettyPrinter.wrap`.
pub fn wrap_with(text: &str, delim: &str, postfix: &str, colour: bool) -> String {
    let delim = if delim.is_empty() {
        String::new()
    } else {
        format!("{}{delim}", fg(colour, 24))
    };
    let postfix = if postfix.is_empty() {
        String::new()
    } else {
        format!("{}{postfix}", fg(colour, 243))
    };
    wrap_raw(colour, &format!("{text}{delim}{postfix}"))
}

pub fn wrap(text: &str) -> String {
    wrap_with(text, "", "", colour_enabled())
}

/// `PrettyPrinter.size`.
pub fn size_with(value: &str, unit: Option<&str>, pref: Option<&str>, colour: bool) -> String {
    let prefix = match pref {
        None => String::new(),
        Some("") => "sz".to_string(),
        Some(other) => other.to_string(),
    };
    // `pref + almostgray + ":"`, then `darkwhite + pref + darkwhite + value`.
    let prefix = if prefix.is_empty() {
        String::new()
    } else {
        format!("{prefix}{}:", fg(colour, 243))
    };
    let body = match unit {
        None => format!("{}{prefix}{}{value}", fg(colour, 7), fg(colour, 7)),
        Some(unit) => format!(
            "{}{prefix}{}{value}{}{unit}",
            fg(colour, 7),
            fg(colour, 7),
            fg(colour, 243)
        ),
    };
    wrap_raw(colour, &body)
}

pub fn size(value: &str, unit: Option<&str>, pref: Option<&str>) -> String {
    size_with(value, unit, pref, colour_enabled())
}

/// `PrettyPrinter.filelen`.
pub fn filelen_with(length: &str, colour: bool) -> String {
    wrap_raw(
        colour,
        &format!(
            "{}len{}={}{length}",
            fg(colour, 7),
            fg(colour, 243),
            fg(colour, 7)
        ),
    )
}

pub fn filelen(length: &str) -> String {
    filelen_with(length, colour_enabled())
}

/// `PrettyPrinter.newfile` / `.dir`: a plain wrapped string.
pub fn wrapped_with(text: &str, colour: bool) -> String {
    wrap_raw(colour, text)
}

pub fn wrapped(text: &str) -> String {
    wrapped_with(text, colour_enabled())
}

/// `PrettyPrinter.prefix`: the `❯>` prompt.
pub fn prefix_with(colour: bool) -> String {
    wrap_raw(
        colour,
        &format!("{}{PROMPT_GLYPH}{}>", fg(colour, 25), fg(colour, 26)),
    )
}

pub fn prefix() -> String {
    prefix_with(colour_enabled())
}

/// `PrettyPrinter.delim`.
pub fn delim_with(colour: bool) -> String {
    format!("{}{}", fg(colour, 24), fg(colour, 0))
}

pub fn delim() -> String {
    delim_with(colour_enabled())
}

/// `PrettyPrinter.fancy_file`: `~` for the home prefix and coloured separators.
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
        if ch == '/' || ch == '\u{00b7}' {
            separated.push_str(&fg(colour, 4));
            separated.push(ch);
            separated.push_str(&fg(colour, 7));
        } else {
            separated.push(ch);
        }
    }
    wrap_raw(colour, &separated)
}

pub fn fancy_file(filename: &str) -> String {
    fancy_file_with(filename, colour_enabled())
}

/// Line count through `wc -l`, like the Python's `wccount`.
pub fn wc_lines(path: &Path) -> i64 {
    match std::process::Command::new("wc")
        .args(["-l", &path.display().to_string()])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
    {
        Ok(output) => String::from_utf8_lossy(&output.stdout)
            .split_whitespace()
            .next()
            .and_then(|value| value.parse().ok())
            .unwrap_or(0),
        Err(_) => 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every expectation was captured from the Python implementation with the
    /// real `colored` package installed.
    #[test]
    fn chains_match_the_python_library() {
        assert_eq!(
            wrap_raw(true, "x"),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7mx\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            wrap_with("x", ":", "fps", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7mx\u{1b}[38;5;24m:\u{1b}[38;5;243mfps\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            size_with("10", None, Some(""), true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;7msz\u{1b}[38;5;243m:\u{1b}[38;5;7m10\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            size_with("10", Some("MIB"), Some(""), true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;7msz\u{1b}[38;5;243m:\u{1b}[38;5;7m10\u{1b}[38;5;243mMIB\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            size_with("10", Some("kbps"), Some("vidbrate"), true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;7mvidbrate\u{1b}[38;5;243m:\u{1b}[38;5;7m10\u{1b}[38;5;243mkbps\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            size_with("10", Some("K"), Some(""), true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;7msz\u{1b}[38;5;243m:\u{1b}[38;5;7m10\u{1b}[38;5;243mK\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            filelen_with("42", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;7mlen\u{1b}[38;5;243m=\u{1b}[38;5;7m42\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            prefix_with(true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;25m\u{276f}\u{1b}[38;5;26m>\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(delim_with(true), "\u{1b}[38;5;24m\u{1b}[38;5;0m");
    }

    #[test]
    fn fancy_file_colours_home_and_separators() {
        std::env::set_var("HOME", "/home/neg");
        assert_eq!(
            fancy_file_with("~x", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;2m~\u{1b}[38;5;7mx\u{1b}[38;5;238m\u{27ef}"
        );
        assert_eq!(
            fancy_file_with("/home/neg/a/b.mkv", true),
            "\u{1b}[38;5;238m\u{27ee}\u{1b}[38;5;7m\u{1b}[38;5;2m~\u{1b}[38;5;7m\u{1b}[38;5;4m/\u{1b}[38;5;7ma\u{1b}[38;5;4m/\u{1b}[38;5;7mb.mkv\u{1b}[38;5;238m\u{27ef}"
        );
        std::env::remove_var("HOME");
    }

    #[test]
    fn colourless_mode_keeps_the_frame() {
        assert_eq!(wrap_raw(false, "x"), "\u{27ee}x\u{27ef}");
        assert_eq!(prefix_with(false), "\u{27ee}\u{276f}>\u{27ef}");
        assert_eq!(
            size_with("10", None, Some(""), false),
            "\u{27ee}sz:10\u{27ef}"
        );
    }
}
