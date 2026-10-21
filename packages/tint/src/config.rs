//! The user config file: a flat TOML subset that only needs to describe
//! *differences* from the built-in behaviour.
//!
//! Deliberately small. A full TOML parser would be a dependency and a second
//! grammar to document; what people actually want from a colouriser config is
//! "these words are errors", "this prefix is a header", "drop this wrapper".
//! Everything else is discoverable from the built-in table.

use std::collections::HashMap;

use crate::rule::{Matcher, Rule};
use crate::scan::PRIO_RULE;
use crate::style::{Color, Style};
use crate::theme::Kind;

/// Styles named directly in the config, referenced from hits by index.
#[derive(Default, Debug, Clone)]
pub struct StyleTable {
    styles: Vec<Style>,
}

impl StyleTable {
    /// Intern a style and return its 1-based slot (0 means "use the theme").
    pub fn intern(&mut self, style: Style) -> u16 {
        if let Some(pos) = self.styles.iter().position(|s| *s == style) {
            return pos as u16 + 1;
        }
        self.styles.push(style);
        self.styles.len() as u16
    }

    /// Resolve a hit's style against the theme.
    pub fn resolve(&self, slot: u16, theme_style: Style) -> Style {
        if slot == 0 {
            theme_style
        } else {
            self.styles
                .get(slot as usize - 1)
                .copied()
                .unwrap_or(theme_style)
        }
    }

    pub fn len(&self) -> usize {
        self.styles.len()
    }
}

/// Everything the config file can change.
#[derive(Default, Debug)]
pub struct Config {
    pub theme: Option<String>,
    pub color: Option<String>,
    /// Wrap these commands in the generated shell integration, guessing the
    /// ruleset from the command name.
    pub extra_wrappers: Vec<String>,
    /// Never wrap these commands.
    pub skip_wrappers: Vec<String>,
    pub rules: Vec<Rule>,
    pub styles: StyleTable,
    /// Raw `theme`-relative style for a kind: `theme_style.err = "red,bold"`.
    pub kind_styles: HashMap<Kind, Style>,
}

/// Parse the config text. Errors carry the line number so a typo is findable.
pub fn parse(text: &str) -> Result<Config, String> {
    let mut config = Config::default();
    for (index, raw) in text.lines().enumerate() {
        let line_no = index + 1;
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        let (key, value) = line
            .split_once('=')
            .ok_or_else(|| format!("line {line_no}: expected `key = value`"))?;
        // Keys may be quoted TOML-style — required when the needle carries
        // punctuation that is not a bare-key character (`prefix."###"`).
        let key = unquote(key.trim()).unwrap_or_else(|| key.trim().to_string());
        let key = key.as_str();
        let value = value.trim();
        let unquoted = unquote(value).unwrap_or_else(|| value.to_string());
        match key {
            "theme" => config.theme = Some(unquoted),
            "color" | "colour" => config.color = Some(unquoted),
            "wrap" => config.extra_wrappers.extend(split_words(&unquoted)),
            "skip" => config.skip_wrappers.extend(split_words(&unquoted)),
            _ => {
                if let Some(kind_name) = key.strip_prefix("theme.style.") {
                    let kind = Kind::by_name(kind_name)
                        .ok_or_else(|| format!("line {line_no}: unknown kind `{kind_name}`"))?;
                    let style = style_from_spec(&unquoted)
                        .map_err(|err| format!("line {line_no}: {err}"))?;
                    config.kind_styles.insert(kind, style);
                    continue;
                }
                let (source, needle) = key
                    .split_once('.')
                    .ok_or_else(|| format!("line {line_no}: unsupported key `{key}`"))?;
                if needle.is_empty() {
                    return Err(format!("line {line_no}: empty match in `{key}`"));
                }
                let matcher = match source {
                    "keyword" | "word" => Matcher::Word(needle.as_bytes().to_vec()),
                    "literal" => Matcher::Literal(needle.as_bytes().to_vec()),
                    "prefix" => Matcher::Prefix(needle.as_bytes().to_vec()),
                    "suffix" => Matcher::Suffix(needle.as_bytes().to_vec()),
                    other => return Err(format!("line {line_no}: unsupported key `{other}.`")),
                };
                let (kind, style) = match Kind::by_name(&unquoted) {
                    Some(kind) => (kind, 0),
                    None => (
                        Kind::Note,
                        config.styles.intern(
                            style_from_spec(&unquoted)
                                .map_err(|err| format!("line {line_no}: {err}"))?,
                        ),
                    ),
                };
                config.rules.push(Rule {
                    matcher,
                    kind,
                    style,
                    prio: PRIO_RULE + 50,
                });
            }
        }
    }
    Ok(config)
}

/// Drop a trailing `#` comment that is not inside quotes.
fn strip_comment(line: &str) -> &str {
    let bytes = line.as_bytes();
    let mut quote: Option<u8> = None;
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'"' | b'\'' => {
                if quote == Some(bytes[i]) {
                    quote = None;
                } else if quote.is_none() {
                    quote = Some(bytes[i]);
                }
            }
            // A comment starts at line start or after whitespace, so a `#`
            // inside a needle (`prefix.###`) stays part of the key.
            b'#' if quote.is_none() && (i == 0 || bytes[i - 1].is_ascii_whitespace()) => {
                return &line[..i];
            }
            _ => {}
        }
        i += 1;
    }
    line
}

fn unquote(value: &str) -> Option<String> {
    let bytes = value.as_bytes();
    if bytes.len() >= 2 {
        let first = bytes[0];
        let last = bytes[bytes.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return Some(value[1..value.len() - 1].to_string());
        }
    }
    None
}

fn split_words(value: &str) -> Vec<String> {
    value
        .split(|c: char| c.is_whitespace() || c == ',')
        .filter(|word| !word.is_empty())
        .map(|word| word.to_string())
        .collect()
}

fn color_by_name(name: &str) -> Option<Color> {
    let idx = match name {
        "black" => 0,
        "red" => 1,
        "green" => 2,
        "yellow" => 3,
        "blue" => 4,
        "magenta" | "purple" => 5,
        "cyan" => 6,
        "white" | "grey" | "gray" => 7,
        "brightblack" | "grey-bright" => 8,
        "brightred" => 9,
        "brightgreen" => 10,
        "brightyellow" => 11,
        "brightblue" => 12,
        "brightmagenta" => 13,
        "brightcyan" => 14,
        "brightwhite" => 15,
        _ => return None,
    };
    Some(Color::Idx(idx))
}

/// Parse `red,bold`, `#ff8800,underline`, `idx:141`, `on-blue`, `none`.
pub fn style_from_spec(spec: &str) -> Result<Style, String> {
    let mut style = Style::NONE;
    for token in spec
        .split(|c: char| c == ',' || c.is_whitespace())
        .filter(|t| !t.is_empty())
    {
        let token = token.to_ascii_lowercase();
        let mut background = false;
        let name = if let Some(rest) = token
            .strip_prefix("on-")
            .or_else(|| token.strip_prefix("bg-"))
        {
            background = true;
            rest
        } else {
            token.as_str()
        };
        match name {
            "bold" => style.bold = true,
            "dim" | "faint" => style.dim = true,
            "italic" => style.italic = true,
            "underline" => style.underline = true,
            "none" | "plain" => style = Style::NONE,
            _ => {
                let color = if let Some(hex) = name.strip_prefix('#') {
                    parse_hex(hex)?
                } else if let Some(index) = name.strip_prefix("idx:") {
                    let value: u8 = index
                        .parse()
                        .map_err(|_| format!("bad palette index `{index}`"))?;
                    Color::Idx(value)
                } else if let Some(index) = name.strip_prefix("idx") {
                    let value: u8 = index
                        .parse()
                        .map_err(|_| format!("bad palette index `{index}`"))?;
                    Color::Idx(value)
                } else if let Ok(value) = name.parse::<u8>() {
                    Color::Idx(value)
                } else if let Some(color) = color_by_name(name) {
                    color
                } else {
                    return Err(format!("unknown style token `{token}`"));
                };
                if background {
                    style.bg = Some(color);
                } else {
                    style.fg = Some(color);
                }
            }
        }
    }
    Ok(style)
}

fn parse_hex(hex: &str) -> Result<Color, String> {
    if hex.len() != 6 {
        return Err(format!("colour `#{hex}` is not 6 hex digits"));
    }
    let byte = |from: usize| -> Result<u8, String> {
        u8::from_str_radix(&hex[from..from + 2], 16)
            .map_err(|_| format!("colour `#{hex}` is not valid hex"))
    };
    Ok(Color::Rgb(byte(0)?, byte(2)?, byte(4)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_theme_and_colour() {
        let cfg = parse("theme = \"vivid\"\ncolor = \"always\"\n").unwrap();
        assert_eq!(cfg.theme.as_deref(), Some("vivid"));
        assert_eq!(cfg.color.as_deref(), Some("always"));
    }

    #[test]
    fn parses_custom_rules() {
        let cfg =
            parse("keyword.FATAL = \"red,bold\"\nprefix.!!! = \"brightred\"\nsuffix.[done] = ok\n")
                .unwrap();
        assert_eq!(cfg.rules.len(), 3);
        assert_eq!(cfg.rules[0].matcher, Matcher::Word(b"FATAL".to_vec()));
        assert_eq!(cfg.rules[1].matcher, Matcher::Prefix(b"!!!".to_vec()));
        assert_eq!(cfg.rules[2].kind, Kind::Ok);
        assert_eq!(cfg.styles.len(), 2, "two raw styles interned");
    }

    #[test]
    fn parses_wrappers_and_skips() {
        let cfg = parse("wrap = \"go rustup\"\nskip = \"find, tar\"\n").unwrap();
        assert_eq!(cfg.extra_wrappers, ["go", "rustup"]);
        assert_eq!(cfg.skip_wrappers, ["find", "tar"]);
    }

    #[test]
    fn a_hash_inside_a_needle_is_not_a_comment() {
        let cfg = parse("prefix.### = \"brightmagenta,bold\"\n").unwrap();
        assert_eq!(cfg.rules.len(), 1);
        assert_eq!(cfg.rules[0].matcher, Matcher::Prefix(b"###".to_vec()));
    }

    #[test]
    fn quoted_keys_are_accepted() {
        let cfg = parse("\"prefix.>>>\" = \"brightmagenta,bold\"\n").unwrap();
        assert_eq!(cfg.rules.len(), 1);
        assert_eq!(cfg.rules[0].matcher, Matcher::Prefix(b">>>".to_vec()));
    }

    #[test]
    fn comments_and_blank_lines_are_ignored() {
        let cfg = parse("# hello\n\n   \ntheme = dark # inline\n").unwrap();
        assert_eq!(cfg.theme.as_deref(), Some("dark"));
    }

    #[test]
    fn bad_keys_are_reported_with_a_line_number() {
        let err = parse("theme = \"dark\"\nnonsense = 1\n").unwrap_err();
        assert!(err.starts_with("line 2:"), "{err}");
    }

    #[test]
    fn style_spec_supports_names_hex_and_indices() {
        let style = style_from_spec("red,bold").unwrap();
        assert_eq!(style.fg, Some(Color::Idx(1)));
        assert!(style.bold);
        let style = style_from_spec("#00ff00").unwrap();
        assert_eq!(style.fg, Some(Color::Rgb(0, 255, 0)));
        let style = style_from_spec("idx:141,on-blue").unwrap();
        assert_eq!(style.fg, Some(Color::Idx(141)));
        assert_eq!(style.bg, Some(Color::Idx(4)));
        assert!(style_from_spec("chartreuse").is_err());
    }

    #[test]
    fn style_table_deduplicates() {
        let mut table = StyleTable::default();
        let a = table.intern(Style::fg(1));
        let b = table.intern(Style::fg(1));
        assert_eq!(a, b);
        assert_eq!(table.len(), 1);
        assert_eq!(table.resolve(a, Style::fg(9)), Style::fg(1));
        assert_eq!(table.resolve(0, Style::fg(9)), Style::fg(9));
    }
}
