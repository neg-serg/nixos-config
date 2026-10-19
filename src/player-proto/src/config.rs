//! User skins: a small config file that turns the built-in looks into a starting point.
//!
//! # Why a file and not more built-in skins
//!
//! A skin is already data (`skin.rs`): palette + wallpaper + surface treatment. The only thing
//! missing for "make it look like *that*" is a way to say so without recompiling, so this module
//! reads a deliberately tiny subset of TOML and produces the same structure the built-ins use.
//! The subset is small on purpose — sections, `key = value`, strings, numbers, booleans, and
//! `#` comments — because a schema nobody can guess is not customization, and a full TOML parser
//! would be the only dependency in the crate that exists for a config file.
//!
//! ```toml
//! # $XDG_CONFIG_HOME/player/skins.toml
//! [[skin]]
//! name = "mine"          # required, unique; `:skin mine` selects it
//! theme = "neg-hc"       # base palette: neg | neg-soft | neg-hc
//! backdrop = "plasma"    # none | art | tunnel | plasma | spectrum
//! strength = 0.7         # 0..1, how much of the backdrop survives the dimming sheet
//! glass = true           # frosted slabs instead of opaque panes
//! glass_tint = "#0b0a10"
//! glass_alpha = 0.82
//! refraction = 0.009
//!
//! [[skin]]
//! name = "quiet-plasma"
//! theme = "neg-soft"
//! backdrop = "plasma"
//! strength = 0.35
//! glass = false
//! ```
//!
//! Every key except `name` is optional and falls back to the value the `theme` implies, so the
//! shortest useful skin is three lines. Unknown keys are reported rather than ignored: a typo in
//! a colour name would otherwise silently paint the default, which is the one failure mode that
//! is impossible to notice.

use std::path::{Path, PathBuf};

/// One `[[skin]]` block, before it is resolved against a palette.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SkinSpec {
    pub name: String,
    /// Base palette name; `neg` when absent.
    pub theme: Option<String>,
    /// `none` | `art` | `tunnel` | `plasma` | `spectrum`.
    pub backdrop: Option<String>,
    pub strength: Option<f32>,
    pub glass: Option<bool>,
    pub glass_tint: Option<String>,
    /// `color.<token> = "#rrggbb"`: per-skin palette overrides, applied on top of the base
    /// theme. Any token `Theme` exposes can be replaced without rebuilding the app, which is
    /// what makes a config file a palette and not just a switch.
    pub colors: Vec<(String, String)>,
    pub glass_alpha: Option<f32>,
    pub refraction: Option<f32>,
}

/// A parsed config file: the skins it declares, plus everything that went wrong while reading
/// it. The errors are returned instead of logged so the caller can put them on screen: a config
/// that silently half-applies is worse than one that refuses.
#[derive(Clone, Debug, Default)]
pub struct SkinConfig {
    pub skins: Vec<SkinSpec>,
    pub problems: Vec<String>,
}

/// Where the config lives: `--skins=PATH`, else `$XDG_CONFIG_HOME/player/skins.toml`.
pub fn default_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("player").join("skins.toml"))
}

/// Load the config, or an empty one when the file does not exist. A missing file is the normal
/// state — most runs use the built-in skins — so it is not reported as a problem.
pub fn load(path: Option<&Path>) -> SkinConfig {
    let Some(path) = path.map(Path::to_path_buf).or_else(default_path) else {
        return SkinConfig::default();
    };
    match std::fs::read_to_string(&path) {
        Ok(text) => parse(&text),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => SkinConfig::default(),
        Err(e) => SkinConfig {
            skins: Vec::new(),
            problems: vec![format!("{}: {e}", path.display())],
        },
    }
}

/// Split a TOML subset into `[[skin]]` specs.
pub fn parse(text: &str) -> SkinConfig {
    let mut config = SkinConfig::default();
    let mut current: Option<SkinSpec> = None;
    let mut saw_any_section = false;

    for (lineno, raw) in text.lines().enumerate() {
        let line = match raw.find('#') {
            // A `#` only starts a comment outside a quoted string; the values below are simple
            // enough that the last quote wins, and a `#` inside a colour is impossible.
            Some(at) if !inside_quotes(&raw[..at]) => raw[..at].trim(),
            _ => raw.trim(),
        };
        if line.is_empty() {
            continue;
        }
        if line.starts_with("[[") {
            saw_any_section = true;
            if let Some(spec) = current.take() {
                config.skins.push(spec);
            }
            if line != "[[skin]]" {
                config.problems.push(format!(
                    "line {}: only [[skin]] sections exist, got {line}",
                    lineno + 1
                ));
            }
            current = Some(SkinSpec::default());
            continue;
        }
        if line.starts_with('[') {
            config.problems.push(format!(
                "line {}: nested tables are not supported ({line}); use the flat keys",
                lineno + 1
            ));
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            config.problems.push(format!(
                "line {}: expected `key = value`, got `{line}`",
                lineno + 1
            ));
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        let Some(spec) = current.as_mut() else {
            config.problems.push(format!(
                "line {}: `{key}` appears before any [[skin]] section",
                lineno + 1
            ));
            continue;
        };
        if let Err(message) = apply(spec, key, value) {
            config
                .problems
                .push(format!("line {}: {message}", lineno + 1));
        }
    }
    if let Some(spec) = current.take() {
        config.skins.push(spec);
    }
    if !saw_any_section && !text.trim().is_empty() {
        config
            .problems
            .push("no [[skin]] sections found; nothing to apply".to_string());
    }
    config
}

fn inside_quotes(text: &str) -> bool {
    text.matches('"').count() % 2 == 1
}

fn unquote(value: &str) -> &str {
    value.trim().trim_matches('"').trim()
}

fn apply(spec: &mut SkinSpec, key: &str, raw: &str) -> Result<(), String> {
    let text = unquote(raw);
    let number = |v: &str| -> Result<f32, String> {
        v.parse::<f32>()
            .map_err(|_| format!("{key} expects a number, got `{v}`"))
    };
    match key {
        "name" => spec.name = text.to_string(),
        "theme" => spec.theme = Some(text.to_string()),
        "backdrop" => spec.backdrop = Some(text.to_string()),
        "strength" => spec.strength = Some(number(text)?.clamp(0.0, 1.0)),
        "glass" => {
            spec.glass = Some(match text {
                "true" | "on" | "yes" => true,
                "false" | "off" | "no" => false,
                other => return Err(format!("glass expects true/false, got `{other}`")),
            })
        }
        "glass_tint" => {
            if crate::color::parse_hex(text).is_none() {
                return Err(format!("glass_tint expects #rrggbb, got `{text}`"));
            }
            spec.glass_tint = Some(text.to_string());
        }
        "glass_alpha" => spec.glass_alpha = Some(number(text)?.clamp(0.0, 1.0)),
        "refraction" => spec.refraction = Some(number(text)?.clamp(0.0, 0.03)),
        other if other.starts_with("color.") => {
            let token = &other["color.".len()..];
            if crate::color::parse_hex(text).is_none() {
                return Err(format!("{other} expects #rrggbb, got `{text}`"));
            }
            spec.colors.push((token.to_string(), text.to_string()));
        }
        other => return Err(format!("unknown key `{other}`")),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_two_skins_with_every_key() {
        let config = parse(
            r##"
# a comment line
[[skin]]
name = "mine"
theme = "neg-hc"
backdrop = "plasma"   # trailing comment
strength = 0.7
glass = true
glass_tint = "#0b0a10"
glass_alpha = 0.82
refraction = 0.009

[[skin]]
name = "flat"
glass = false
"##,
        );
        assert!(config.problems.is_empty(), "{:?}", config.problems);
        assert_eq!(config.skins.len(), 2);
        assert_eq!(config.skins[0].name, "mine");
        assert_eq!(config.skins[0].theme.as_deref(), Some("neg-hc"));
        assert_eq!(config.skins[0].backdrop.as_deref(), Some("plasma"));
        assert_eq!(config.skins[0].strength, Some(0.7));
        assert_eq!(config.skins[0].glass, Some(true));
        assert_eq!(config.skins[0].glass_alpha, Some(0.82));
        assert_eq!(config.skins[1].name, "flat");
        assert_eq!(config.skins[1].glass, Some(false));
    }

    #[test]
    fn values_are_clamped_to_their_ranges() {
        let config = parse("[[skin]]\nname = \"x\"\nstrength = 4.0\nrefraction = 9.0\n");
        assert!(config.problems.is_empty());
        assert_eq!(config.skins[0].strength, Some(1.0));
        assert_eq!(config.skins[0].refraction, Some(0.03));
    }

    #[test]
    fn colour_overrides_are_collected_in_order() {
        let config =
            parse("[[skin]]\nname = \"x\"\ncolor.accent = \"#ff0000\"\ncolor.text = \"#00ff00\"\n");
        assert!(config.problems.is_empty(), "{:?}", config.problems);
        assert_eq!(
            config.skins[0].colors,
            vec![
                ("accent".to_string(), "#ff0000".to_string()),
                ("text".to_string(), "#00ff00".to_string())
            ]
        );
    }

    #[test]
    fn a_non_hex_colour_is_reported() {
        let config = parse("[[skin]]\nname = \"x\"\ncolor.accent = \"red\"\n");
        assert_eq!(config.problems.len(), 1);
        assert!(config.problems[0].contains("color.accent expects #rrggbb"));
    }

    #[test]
    fn mistakes_are_reported_not_ignored() {
        let config = parse("[[skin]]\nname = \"x\"\ncolour = \"#ffffff\"\nglass = maybe\n");
        assert_eq!(config.problems.len(), 2, "{:?}", config.problems);
        assert!(config.problems[0].contains("unknown key `colour`"));
        assert!(config.problems[1].contains("glass expects"));
    }

    #[test]
    fn a_key_outside_a_section_is_an_error() {
        let config = parse("name = \"x\"\n[[skin]]\nname = \"y\"\n");
        assert_eq!(config.problems.len(), 1);
        assert_eq!(config.skins.len(), 1);
        assert_eq!(config.skins[0].name, "y");
    }

    #[test]
    fn an_empty_file_is_not_a_problem() {
        let config = parse("");
        assert!(config.problems.is_empty());
        assert!(config.skins.is_empty());
    }
}
