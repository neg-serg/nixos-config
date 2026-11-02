//! Command-line parsing for the theme pipeline.
//!
//! The options, their missing-value messages and the usage text are the shell
//! script's, byte for byte (`sysmon.sh`'s port kept its own name in the usage
//! text for the same reason: the help reads as the drop-in documentation that
//! was already deployed). `--help` wins wherever it appears, a value-taking
//! option consumes the next argument even when it looks like a flag, and an
//! empty value is kept as an empty string because the shell treats
//! `--accent ''`, `--wallpaper ''` and `--from-json ''` as absent.

use std::ffi::{OsStr, OsString};

/// The shell's `usage()` heredoc, byte for byte.
pub const USAGE: &str = "\
theme.sh — build ~/.config/pleamar/theme.plm from the wallpaper.

Usage:
  theme.sh [--wallpaper FILE] [--accent '#RRGGBB'] [--from-json FILE]
           [--mode auto|light|dark]
  theme.sh --help

Where the wallpaper is found, in this order:
  --wallpaper FILE
  $XDG_CACHE_HOME/pleamar/wallpaper-path      (canonical; INTERFACES.md §1.2, first line)
  $XDG_CACHE_HOME/quickshell-wallpaper-path   (legacy fallback, first line)

What is written: ~/.config/pleamar/theme.plm, a strict `library Skin { … }`
with skin.coal/surface/ink/ink.dim/accent/accent.hover/accent.deep/on.accent.
Scenes import it after lib/palette.plm and read the skin.* names; copying one
into the repo is never needed. The file is replaced atomically (a temp file in
the same directory, then mv). Nothing else under ~/.config/pleamar is touched.

Colours:
  * tones come from a 48x48 ImageMagick sample of the wallpaper: weighted
    k-means in Oklab (the greeter's algorithm, k=4), darkest to lightest;
  * the accent is the legacy AccentSampler mean of the saturated pixels,
    hue-matched onto #006FCC (Settings/Theme.qml's accentPrimary);
  * --accent overrides the extracted accent; --from-json FILE reads a JSON
    object and overrides any of coal, surface, ink, accent that it gives
    (\"#RRGGBB\" strings, \"#RGB\" accepted). --accent wins over the file;
  * no wallpaper to sample and no colour given is an error — the file is left
    as it was. A colour given without a wallpaper keeps the QS base palette
    for the tones it did not name (colors.background #000000,
    colors.surfaceVariant #242A35, colors.text.primary #CBD6E5,
    colors.accent.primary #006FCC); skin.ink.dim is the static #AEB9C8 (colors.text.secondary), as
    the reference draws its secondary text — not a mix of two tones it no longer samples
    text/surface tones above.

The theme is light or dark: `--mode auto` (the default) follows the wallpaper — its mean
WCAG luminance over the reference's own 0.5 threshold — and `--mode light|dark` forces one.
The default mode is read from `~/.config/pleamar/theme.mode` (one word, `auto` when the
file is absent), so the switch is a file, not a rebuild.

Environment: MAGICK_BIN (magick), AWK_BIN (awk), JQ_BIN (jq, --from-json only).

Exit: 0 written, 1 nothing to write or a bad input, 2 usage or missing tool.
";

/// The values the pipeline reads from the command line.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Options {
    /// `--wallpaper`: empty means "resolve from the cache" (the shell's `-n`).
    pub wallpaper: OsString,
    /// `--accent`: empty means "not given" (the shell's `-n`).
    pub accent: String,
    /// `--from-json`: empty means "not given".
    pub from_json: OsString,
    /// `--mode`: empty means "read `theme.mode`, then `auto`".
    pub mode: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// The message after `theme: `; the caller adds `see --help` and exits 2.
    UsageError(String),
}

fn lossy(value: &OsStr) -> String {
    value.to_string_lossy().into_owned()
}

/// Parse arguments in order, exactly as the shell's `while` loop did.
pub fn parse<I: IntoIterator<Item = OsString>>(arguments: I) -> ParseResult {
    let arguments: Vec<OsString> = arguments.into_iter().collect();
    let mut options = Options::default();
    let mut index = 0;
    while index < arguments.len() {
        let argument = &arguments[index];
        match argument.to_str() {
            Some("--wallpaper") => {
                if index + 1 >= arguments.len() {
                    return ParseResult::UsageError("--wallpaper needs a FILE".to_string());
                }
                options.wallpaper = arguments[index + 1].clone();
                index += 2;
            }
            Some("--accent") => {
                if index + 1 >= arguments.len() {
                    return ParseResult::UsageError("--accent needs a '#RRGGBB' value".to_string());
                }
                options.accent = lossy(&arguments[index + 1]);
                index += 2;
            }
            Some("--from-json") => {
                if index + 1 >= arguments.len() {
                    return ParseResult::UsageError("--from-json needs a FILE".to_string());
                }
                options.from_json = arguments[index + 1].clone();
                index += 2;
            }
            Some("--mode") => {
                if index + 1 >= arguments.len() {
                    return ParseResult::UsageError("--mode needs auto, light or dark".to_string());
                }
                options.mode = lossy(&arguments[index + 1]);
                index += 2;
            }
            Some("--help" | "-h") => return ParseResult::Help,
            _ => {
                return ParseResult::UsageError(format!("unknown argument: {}", lossy(argument)));
            }
        }
    }
    ParseResult::Run(options)
}

#[cfg(test)]
mod tests {
    use super::{parse, Options, ParseResult};
    use std::ffi::OsString;

    fn run(values: &[&str]) -> ParseResult {
        parse(values.iter().map(OsString::from))
    }

    #[test]
    fn options_take_the_next_argument_verbatim() {
        let ParseResult::Run(options) = run(&[
            "--wallpaper",
            "--accent",
            "--accent",
            "#AbC",
            "--from-json",
            "pal.json",
            "--mode",
            "light",
        ]) else {
            panic!("expected a run");
        };
        assert_eq!(options.wallpaper, OsString::from("--accent"));
        assert_eq!(options.accent, "#AbC");
        assert_eq!(options.from_json, OsString::from("pal.json"));
        assert_eq!(options.mode, "light");
        assert_eq!(
            Options {
                wallpaper: OsString::from("--accent"),
                accent: "#AbC".to_string(),
                from_json: OsString::from("pal.json"),
                mode: "light".to_string(),
            },
            options
        );
    }

    #[test]
    fn help_wins_wherever_it_appears() {
        assert_eq!(
            run(&["--wallpaper", "x", "--help", "--bad"]),
            ParseResult::Help
        );
        assert_eq!(run(&["-h"]), ParseResult::Help);
    }

    #[test]
    fn missing_values_are_usage_errors() {
        for (arguments, message) in [
            (vec!["--wallpaper"], "--wallpaper needs a FILE"),
            (vec!["--accent"], "--accent needs a '#RRGGBB' value"),
            (vec!["--from-json"], "--from-json needs a FILE"),
            (vec!["--mode"], "--mode needs auto, light or dark"),
            (
                vec!["--mode", "auto", "--wallpaper"],
                "--wallpaper needs a FILE",
            ),
        ] {
            assert_eq!(
                run(&arguments),
                ParseResult::UsageError(message.to_string()),
                "{arguments:?}"
            );
        }
    }

    #[test]
    fn unknown_arguments_are_reported() {
        assert_eq!(
            run(&["--nope"]),
            ParseResult::UsageError("unknown argument: --nope".to_string())
        );
        assert_eq!(
            run(&["positional"]),
            ParseResult::UsageError("unknown argument: positional".to_string())
        );
    }
}
