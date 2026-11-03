//! Theme files: a hand-written palette for `theme.plm`.
//!
//! The wallpaper pipeline derives the palette from a picture; a theme file is
//! the other end of the same pipe — the five tones a person chose, in a small
//! TOML subset:
//!
//! ```toml
//! name   = "Retro"
//! light  = false         # skin.light, and the mode in the header
//!
//! [palette]
//! coal    = "#101418"
//! surface = "#242A35"
//! ink     = "#CBD6E5"
//! ink_dim = "#AEB9C8"
//! accent  = "#006FCC"
//! ```
//!
//! Every key is optional: a file that names only its accent keeps the stock
//! palette for the rest (the same fallbacks `theme.sh` uses). What is written
//! is the same `library Skin` the wallpaper pipeline writes, so a scene cannot
//! tell which producer made it — [`crate::render::Theme`] renders both.
//!
//! The reader is deliberately small, not a TOML implementation: `key = value`
//! lines, `#` comments outside quotes, one `[palette]` section, `true`/`false`
//! and decimal integers. A mistake is a `line N: …` error and the file is
//! skipped; nothing is written.

use std::fs;
use std::path::Path;

use crate::hex;
use crate::render::Theme;

/// `colors.background`'s stock fallback (`theme.sh`).
pub const STOCK_COAL: &str = "#000000";
/// `colors.surfaceVariant`'s stock fallback.
pub const STOCK_SURFACE: &str = "#242A35";
/// `colors.text.primary`'s stock fallback.
pub const STOCK_INK: &str = "#CBD6E5";
/// `colors.text.secondary`'s stock fallback.
pub const STOCK_INK_DIM: &str = "#AEB9C8";
/// `colors.accent.primary`'s stock fallback.
pub const STOCK_ACCENT: &str = "#006FCC";

/// One parsed theme file.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ThemeFile {
    /// The card's name; `None` when the file leaves it out (the caller then
    /// uses the file stem).
    pub name: Option<String>,
    /// `skin.light`: whether the palette is a light one.
    pub light: bool,
    pub coal: String,
    pub surface: String,
    pub ink: String,
    pub ink_dim: String,
    pub accent: String,
}

impl ThemeFile {
    /// The `theme.plm` this file describes, with the light side's whites worked
    /// out from `kelvin` (`warm_palette`): only the accent comes from the file.
    pub fn to_theme_at(&self, path: &Path, palette: &LivePalette, kelvin: f64) -> Theme {
        let mut theme = self.to_theme(path);
        theme.coal = hex_of(palette.coal);
        theme.surface = hex_of(palette.surface);
        theme.ink = hex_of(palette.ink);
        theme.ink_dim = hex_of(palette.ink_dim);
        theme.accent = hex_of(palette.accent);
        theme.light = true;
        theme.mode = "light";
        theme.mode_note = format!("the light theme at {kelvin:.0} K");
        theme.generated_by = format!(
            "pleamar-themes from {} (light, {kelvin:.0} K)",
            path.display()
        );
        theme
    }

    /// The `theme.plm` this file describes, ready for
    /// [`Theme::render`](crate::render::Theme::render).
    ///
    /// `path` is what the header names as the source; the notes above each
    /// `let` say the tone came from the file rather than from a wallpaper.
    pub fn to_theme(&self, path: &Path) -> Theme {
        let source = path.display().to_string();
        Theme {
            title: "theme file's palette".to_string(),
            generated_by: format!("pleamar-themes from {source}"),
            source: Some(source),
            mode: if self.light { "light" } else { "dark" },
            mode_note: "the theme file says so".to_string(),
            coal_note: "colors.background, from the theme file.".to_string(),
            surface_note: "colors.surfaceVariant, from the theme file.".to_string(),
            ink_note: "colors.text.primary, from the theme file.".to_string(),
            accent_note: "colors.accent.primary, from the theme file.".to_string(),
            coal: self.coal.clone(),
            surface: self.surface.clone(),
            ink: self.ink.clone(),
            ink_dim: self.ink_dim.clone(),
            accent: self.accent.clone(),
            light: self.light,
        }
    }
}

/// Read a theme file. Every error starts with the 1-based line it came from.
pub fn parse(text: &str) -> Result<ThemeFile, String> {
    let mut name: Option<String> = None;
    let mut light = false;
    let mut palette = false;
    let mut coal = STOCK_COAL.to_string();
    let mut surface = STOCK_SURFACE.to_string();
    let mut ink = STOCK_INK.to_string();
    let mut ink_dim = STOCK_INK_DIM.to_string();
    let mut accent = STOCK_ACCENT.to_string();

    for (index, raw) in text.lines().enumerate() {
        let line_number = index + 1;
        let line = strip_comment(raw).trim();
        if line.is_empty() {
            continue;
        }
        if let Some(rest) = line.strip_prefix('[') {
            let Some(inside) = rest.strip_suffix(']') else {
                return Err(format!(
                    "line {line_number}: a section opens with '[' and ends with ']'"
                ));
            };
            match inside.trim() {
                "palette" => palette = true,
                other => {
                    return Err(format!(
                        "line {line_number}: unknown section [{other}] (only [palette] is read)"
                    ))
                }
            }
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            return Err(format!("line {line_number}: expected key = value"));
        };
        let key = key.trim();
        let value = value.trim();
        match (palette, key) {
            (false, "name") => name = Some(quoted(line_number, key, value)?),
            (false, "light") => {
                light = match value {
                    "true" => true,
                    "false" => false,
                    _ => {
                        return Err(format!(
                            "line {line_number}: light is true or false, not '{value}'"
                        ))
                    }
                }
            }
            (false, other) => {
                return Err(format!(
                    "line {line_number}: unknown key '{other}' outside [palette] (name, light)"
                ))
            }
            (true, "coal") => coal = colour(line_number, key, value)?,
            (true, "surface") => surface = colour(line_number, key, value)?,
            (true, "ink") => ink = colour(line_number, key, value)?,
            (true, "ink_dim") => ink_dim = colour(line_number, key, value)?,
            (true, "accent") => accent = colour(line_number, key, value)?,
            (true, other) => {
                return Err(format!(
                    "line {line_number}: unknown colour '{other}' (coal, surface, ink, ink_dim, accent)"
                ))
            }
        }
    }

    Ok(ThemeFile {
        name,
        light,
        coal,
        surface,
        ink,
        ink_dim,
        accent,
    })
}

/// Drop a `#` comment, but only outside a quoted value: `coal = "#000000"` keeps
/// its colour.
fn strip_comment(line: &str) -> &str {
    let mut quoted = false;
    for (index, character) in line.char_indices() {
        match character {
            '"' => quoted = !quoted,
            '#' if !quoted => return &line[..index],
            _ => {}
        }
    }
    line
}

/// A quoted string value, with no escapes and no trailing characters.
fn quoted(line_number: usize, key: &str, value: &str) -> Result<String, String> {
    let unsupported = || format!("line {line_number}: {key} needs one quoted string, not {value}");
    if value.len() < 2 || !value.starts_with('"') || !value.ends_with('"') {
        return Err(unsupported());
    }
    let inner = &value[1..value.len() - 1];
    if inner.contains('"') {
        return Err(unsupported());
    }
    Ok(inner.to_string())
}

/// A colour value, normalized to the lower-case `#rrggbb` form.
fn colour(line_number: usize, key: &str, value: &str) -> Result<String, String> {
    let raw = quoted(line_number, key, value)?;
    hex::normalize(&raw)
        .ok_or_else(|| format!("line {line_number}: '{raw}' is not a hex colour (#rgb or #rrggbb)"))
}

#[cfg(test)]
mod tests {
    use super::{parse, STOCK_ACCENT, STOCK_COAL, STOCK_INK, STOCK_INK_DIM, STOCK_SURFACE};

    #[test]
    fn a_minimal_file_is_all_stock_palette() {
        let theme = parse("name = \"Plain\"\n").expect("parse");
        assert_eq!(theme.name.as_deref(), Some("Plain"));
        assert!(!theme.light);
        assert_eq!(theme.coal, STOCK_COAL);
        assert_eq!(theme.surface, STOCK_SURFACE);
        assert_eq!(theme.ink, STOCK_INK);
        assert_eq!(theme.ink_dim, STOCK_INK_DIM);
        assert_eq!(theme.accent, STOCK_ACCENT);
    }

    #[test]
    fn an_empty_file_is_a_valid_stock_theme() {
        let theme = parse("").expect("parse");
        assert_eq!(
            theme,
            super::ThemeFile {
                name: None,
                light: false,
                coal: STOCK_COAL.to_string(),
                surface: STOCK_SURFACE.to_string(),
                ink: STOCK_INK.to_string(),
                ink_dim: STOCK_INK_DIM.to_string(),
                accent: STOCK_ACCENT.to_string(),
            }
        );
    }

    #[test]
    fn a_full_file_reads_every_key() {
        let text = "\
# a comment line
name = \"Retro\"
light = true

[palette]
coal = \"#101418\"   # the frame
surface = \"#242A35\"
ink = \"#CBD6E5\"
ink_dim = \"#AEB9C8\"
accent = \"#06C\"
";
        let theme = parse(text).expect("parse");
        assert_eq!(theme.name.as_deref(), Some("Retro"));
        assert!(theme.light);
        assert_eq!(theme.coal, "#101418");
        assert_eq!(theme.accent, "#0066cc", "short hex is expanded and lowered");
    }

    #[test]
    fn a_hash_inside_a_value_is_not_a_comment() {
        let theme = parse("[palette]\ncoal = \"#000000\"\n").expect("parse");
        assert_eq!(theme.coal, "#000000");
    }

    #[test]
    fn an_unknown_key_names_its_line() {
        let error = parse("name = \"x\"\nmode = \"fast\"\n").expect_err("must fail");
        assert!(error.starts_with("line 2:"), "{error}");
        assert!(error.contains("unknown key 'mode'"), "{error}");
    }

    #[test]
    fn an_unknown_section_is_refused() {
        let error = parse("[colours]\nink = \"#ffffff\"\n").expect_err("must fail");
        assert!(error.starts_with("line 1:"), "{error}");
        assert!(error.contains("[colours]"), "{error}");
    }

    #[test]
    fn a_palette_typo_names_the_valid_colours() {
        let error = parse("[palette]\ninkey = \"#ffffff\"\n").expect_err("must fail");
        assert!(error.starts_with("line 2:"), "{error}");
        assert!(
            error.contains("coal, surface, ink, ink_dim, accent"),
            "{error}"
        );
    }

    #[test]
    fn a_bad_colour_names_its_value() {
        let error = parse("[palette]\nink = \"white\"\n").expect_err("must fail");
        assert!(error.starts_with("line 2:"), "{error}");
        assert!(error.contains("'white' is not a hex colour"), "{error}");
    }

    #[test]
    fn a_value_must_be_quoted() {
        let error = parse("name = Retro\n").expect_err("must fail");
        assert!(error.contains("needs one quoted string"), "{error}");
    }

    #[test]
    fn a_palette_is_read_out_of_the_generated_file() {
        let text = "\
library Skin strict {
    let skin.coal = #101418
    let skin.surface = #242a35
    let skin.ink = #cbd6e5
    let skin.ink.dim = #aeb9c8
    let skin.accent = #0066cc
    let skin.accent.hover = mix(skin.accent, #ffffff, 20%)
    let skin.on.accent = #ffffff
    let skin.light = true
}
";
        let palette = super::palette_from_text(text).expect("parse");
        assert_eq!(
            palette.coal,
            (
                0x10 as f64 / 255.0,
                0x14 as f64 / 255.0,
                0x18 as f64 / 255.0
            )
        );
        assert_eq!(
            palette.accent,
            (0.0, 0x66 as f64 / 255.0, 0xcc as f64 / 255.0)
        );
        assert_eq!(palette.on_accent, (1.0, 1.0, 1.0));
        assert!(palette.light);
        let json = palette.json();
        assert!(json.starts_with("{\"coal_r\":0.0627,"), "{json}");
        assert!(json.contains("\"accent_g\":0.4000"), "{json}");
        assert!(json.ends_with(",\"light\":1}"), "{json}");
    }

    #[test]
    fn a_warm_paper_is_warmer_than_a_cool_one() {
        let warm = super::warm_palette(2700.0, "#b4541e");
        let cool = super::warm_palette(6500.0, "#b4541e");
        assert!(warm.coal.0 >= warm.coal.2, "warm paper leans red: {warm:?}");
        assert!(
            cool.coal.2 >= warm.coal.2,
            "cool paper keeps more blue: {cool:?} vs {warm:?}"
        );
        assert!(
            warm.coal.0 > 0.95 && warm.coal.1 > 0.85,
            "paper is bright: {warm:?}"
        );
        assert!(warm.ink.0 < 0.25, "ink stays dark: {warm:?}");
        assert!(warm.light);
        assert_eq!(warm.temperature, Some(2700.0));
        // The accent is the theme's own, in both.
        assert!((warm.accent.0 - 0.7059).abs() < 0.001, "{warm:?}");
    }

    #[test]
    fn the_white_point_is_normalized() {
        for kelvin in [2000.0, 2700.0, 4300.0, 6500.0, 10000.0] {
            let (r, g, b) = super::temperature_rgb(kelvin);
            let peak = r.max(g).max(b);
            assert!((peak - 1.0).abs() < 0.001, "{kelvin} K peak {peak}");
        }
    }

    #[test]
    fn a_theme_without_a_palette_role_says_which() {
        let error = super::palette_from_text("let skin.coal = #000000\n").expect_err("must fail");
        assert!(error.contains("skin.surface"), "{error}");
    }

    #[test]
    fn a_light_theme_is_not_true_by_words() {
        let error = parse("light = yes\n").expect_err("must fail");
        assert!(error.contains("light is true or false"), "{error}");
    }
}

// ======================= the live palette =======================
//
// The scenes that draw with `lib/palette-live.plm` cannot read
// `~/.config/pleamar/theme.plm` — a scene reads only its own data folder — so the
// tool that writes the theme also leaves the numbers where a scene may find
// them: `<data>/pleamar/<scene>/palette.json`, one entry per colour channel.

/// The warmth a light theme's paper can be given, in kelvin: the range the
/// theme drawer's slider covers, and what it starts at.
pub const WARMTH_MIN: f64 = 2700.0;
pub const WARMTH_MAX: f64 = 6500.0;
pub const WARMTH_DEFAULT: f64 = 4300.0;

/// A black-body white for `kelvin`, the usual Tanner Helland approximation
/// (2000–10000 K), normalized so its brightest channel is 1.
pub fn temperature_rgb(kelvin: f64) -> (f64, f64, f64) {
    let k = kelvin.clamp(2000.0, 10000.0) / 100.0;
    let (mut red, mut green, mut blue);
    if k <= 66.0 {
        red = 255.0;
        green = 99.470_802_586_1 * k.ln() - 161.119_568_166_1;
        blue = if k <= 19.0 {
            0.0
        } else {
            138.517_731_223_1 * (k - 10.0).ln() - 305.044_792_730_7
        };
    } else {
        red = 329.698_727_446 * (k - 60.0).powf(-0.133_204_759_2);
        green = 288.122_169_528_3 * (k - 60.0).powf(-0.075_514_849_2);
        blue = 255.0;
    }
    red = (red / 255.0).clamp(0.0, 1.0);
    green = (green / 255.0).clamp(0.0, 1.0);
    blue = (blue / 255.0).clamp(0.0, 1.0);
    let peak = red.max(green).max(blue).max(0.0001);
    (red / peak, green / peak, blue / peak)
}

fn mix(a: (f64, f64, f64), b: (f64, f64, f64), amount: f64) -> (f64, f64, f64) {
    (
        a.0 + (b.0 - a.0) * amount,
        a.1 + (b.1 - a.1) * amount,
        a.2 + (b.2 - a.2) * amount,
    )
}

/// A light theme's palette at `kelvin`: the paper (and the surface under it) comes
/// from the temperature, the ink is its dark counterpart, and only the accent is
/// the theme's own — a theme file for the light side names its accent and its
/// warmth, and the whites are worked out from that number.
pub fn warm_palette(kelvin: f64, accent: &str) -> LivePalette {
    let white = (1.0, 1.0, 1.0);
    let tone = temperature_rgb(kelvin);
    let paper = mix(white, tone, 0.28);
    let surface = (paper.0 * 0.94, paper.1 * 0.94, paper.2 * 0.94);
    let dark = (0.078, 0.078, 0.078);
    let ink = mix(dark, tone, 0.06);
    let ink_dim = mix(ink, paper, 0.55);
    LivePalette {
        coal: paper,
        surface,
        ink,
        ink_dim,
        accent: channels(accent).unwrap_or((0.0, 0.435, 0.8)),
        on_accent: (1.0, 1.0, 1.0),
        light: true,
        temperature: Some(kelvin),
    }
}

/// The palette a converted scene draws with: five colours and `light`, as the
/// channels a `fact` takes (0..1).
#[derive(Clone, Debug, PartialEq)]
pub struct LivePalette {
    pub coal: (f64, f64, f64),
    pub surface: (f64, f64, f64),
    pub ink: (f64, f64, f64),
    pub ink_dim: (f64, f64, f64),
    pub accent: (f64, f64, f64),
    pub on_accent: (f64, f64, f64),
    pub light: bool,
    /// The warmth the palette was worked out at (kelvin), for the drawer's
    /// slider; `None` for a palette that did not come from a temperature.
    pub temperature: Option<f64>,
}

impl LivePalette {
    /// The JSON a scene reads with `sys.ask("files.read", "palette.json", "json")`.
    pub fn json(&self) -> String {
        let mut out = String::with_capacity(1024);
        out.push('{');
        let mut first = true;
        for (name, channels) in [
            ("coal", self.coal),
            ("surface", self.surface),
            ("ink", self.ink),
            ("ink_dim", self.ink_dim),
            ("accent", self.accent),
            ("on_accent", self.on_accent),
        ] {
            for (channel, value) in [("r", channels.0), ("g", channels.1), ("b", channels.2)] {
                if !first {
                    out.push(',');
                }
                first = false;
                out.push_str(&format!("\"{name}_{channel}\":{value:.4}"));
            }
        }
        out.push_str(&format!(",\"light\":{}", if self.light { 1 } else { 0 }));
        if let Some(kelvin) = self.temperature {
            out.push_str(&format!(",\"temperature\":{kelvin:.0}"));
        }
        out.push('}');
        out
    }
}

/// Three channels (0..1) as the `#rrggbb` a `theme.plm` carries.
pub fn hex_of(colour: (f64, f64, f64)) -> String {
    let byte = |value: f64| (value.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!(
        "#{:02x}{:02x}{:02x}",
        byte(colour.0),
        byte(colour.1),
        byte(colour.2)
    )
}

/// `#rrggbb` as the three channels a `fact` takes (0..1), or `None` when it is
/// not a hex colour.
pub fn channels(hex_text: &str) -> Option<(f64, f64, f64)> {
    let hex = hex::normalize(hex_text)?;
    let number = |range: std::ops::Range<usize>| -> f64 {
        u8::from_str_radix(&hex[range], 16).unwrap_or(0) as f64 / 255.0
    };
    Some((number(1..3), number(3..5), number(5..7)))
}

/// Read the palette out of a generated `theme.plm` (`let skin.<role> = <value>`).
pub fn palette_from_theme_file(path: &Path) -> Result<LivePalette, String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("cannot read {}: {error}", path.display()))?;
    palette_from_text(&text).map_err(|error| format!("{}: {error}", path.display()))
}

/// The parse itself, split out so a test can hand it a string.
pub fn palette_from_text(text: &str) -> Result<LivePalette, String> {
    let mut values: Vec<(&str, &str)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        let Some(rest) = line.strip_prefix("let ") else {
            continue;
        };
        let Some((key, value)) = rest.split_once('=') else {
            continue;
        };
        values.push((key.trim(), value.trim()));
    }
    let get = |role: &str| -> Result<&str, String> {
        values
            .iter()
            .find_map(|(key, value)| (*key == role).then_some(*value))
            .ok_or_else(|| format!("theme.plm has no `{role}`"))
    };
    let colour = |role: &str| -> Result<(f64, f64, f64), String> {
        let raw = get(role)?;
        channels(raw).ok_or_else(|| format!("theme.plm's `{role}` is not a hex colour: {raw}"))
    };
    let coal = colour("skin.coal")?;
    let surface = colour("skin.surface")?;
    let ink = colour("skin.ink")?;
    let ink_dim = colour("skin.ink.dim")?;
    let accent = colour("skin.accent")?;
    let on_accent = colour("skin.on.accent")?;
    let light = match get("skin.light")? {
        "true" => true,
        "false" => false,
        other => {
            return Err(format!(
                "theme.plm's `skin.light` is not true/false: {other}"
            ))
        }
    };
    Ok(LivePalette {
        coal,
        surface,
        ink,
        ink_dim,
        accent,
        on_accent,
        light,
        temperature: None,
    })
}
