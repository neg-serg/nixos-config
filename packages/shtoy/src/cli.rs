//! Command-line parsing, matching the shell `case` loop of the original.
//!
//! The shell checked `-h`/`--help`/`help`/`?` only for the first argument, then
//! parsed options until `--` or the end of the list; every argument after that
//! was a positional and a second positional was an error. Options could appear
//! after the shader argument, and the last `--import`/`--mirror`/`--list` won.
//! This module reproduces that order, including the diagnostics.

use std::ffi::{OsStr, OsString};
use std::path::Path;

use crate::Die;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    Run,
    Import,
    Mirror,
    List,
}

#[derive(Debug)]
pub struct Options {
    pub mode: Mode,
    pub save: bool,
    pub legacy: bool,
    pub keyboard: Option<u8>,
    pub arg: Option<OsString>,
    /// Channel bindings in command-line order; each pair becomes `-N FILE`.
    pub channels: Vec<(u8, OsString)>,
    /// Channels bound to a texture, used for the keyboard conflict check.
    pub texture_channels: Vec<u8>,
    /// Every bound channel (texture or keyboard), used by the channel notes.
    pub bound_channels: Vec<u8>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            mode: Mode::Run,
            save: false,
            legacy: false,
            keyboard: None,
            arg: None,
            channels: Vec::new(),
            texture_channels: Vec::new(),
            bound_channels: Vec::new(),
        }
    }
}

pub enum Parsed {
    Help,
    Run(Options),
}

pub fn parse(args: &[OsString]) -> Result<Parsed, Die> {
    if let Some(first) = args.first() {
        if matches!(first.to_str(), Some("-h" | "--help" | "help" | "?")) {
            return Ok(Parsed::Help);
        }
    }

    let mut options = Options::default();
    let mut index = 0;

    while index < args.len() {
        let argument = &args[index];
        let text = argument.to_string_lossy();
        match text.as_ref() {
            "--channel" => {
                if args.len() - index < 3 {
                    return Err(Die::new("--channel needs a number and a file"));
                }
                let number = channel_number(&args[index + 1])?;
                let file = &args[index + 2];
                if !Path::new(file).exists() {
                    return Err(Die::new(format!(
                        "channel texture not found: {}",
                        Path::new(file).display()
                    )));
                }
                options.channels.push((number, file.clone()));
                options.texture_channels.push(number);
                options.bound_channels.push(number);
                index += 3;
            }
            "--keyboard" => {
                if args.len() - index < 2 {
                    return Err(Die::new("--keyboard needs a channel number"));
                }
                let number = channel_number(&args[index + 1])?;
                options.keyboard = Some(number);
                options.bound_channels.push(number);
                index += 2;
            }
            "--legacy" => {
                options.legacy = true;
                index += 1;
            }
            "--save" => {
                options.save = true;
                index += 1;
            }
            "--import" => {
                options.mode = Mode::Import;
                index += 1;
            }
            "--mirror" => {
                options.mode = Mode::Mirror;
                index += 1;
            }
            "--list" => {
                options.mode = Mode::List;
                index += 1;
            }
            "--" => {
                index += 1;
                break;
            }
            _ if text.starts_with('-') && text.len() > 1 => {
                return Err(Die::new(format!("unknown option: {text} (see --help)")));
            }
            _ => {
                set_positional(&mut options, argument)?;
                index += 1;
            }
        }
    }

    for argument in &args[index..] {
        set_positional(&mut options, argument)?;
    }

    if let Some(keyboard) = options.keyboard {
        if options.texture_channels.contains(&keyboard) {
            return Err(Die::new(format!(
                "channel {keyboard} is bound to both a texture and the keyboard"
            )));
        }
    }

    Ok(Parsed::Run(options))
}

fn set_positional(options: &mut Options, argument: &OsStr) -> Result<(), Die> {
    if let Some(previous) = &options.arg {
        return Err(Die::new(format!(
            "more than one shader given: {}, {}",
            previous.to_string_lossy(),
            argument.to_string_lossy()
        )));
    }
    options.arg = Some(argument.to_os_string());
    Ok(())
}

fn channel_number(argument: &OsStr) -> Result<u8, Die> {
    match argument.to_str() {
        Some("0") => Ok(0),
        Some("1") => Ok(1),
        Some("2") => Ok(2),
        Some("3") => Ok(3),
        _ => Err(Die::new(format!(
            "channel number must be 0..3, got: {}",
            argument.to_string_lossy()
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::{parse, Mode, Parsed};
    use crate::Die;
    use std::ffi::OsString;

    fn arguments(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    fn parse_options(values: &[&str]) -> super::Options {
        match parse(&arguments(values)).expect("arguments should parse") {
            Parsed::Run(options) => options,
            Parsed::Help => panic!("unexpected help"),
        }
    }

    fn parse_error(values: &[&str]) -> String {
        match parse(&arguments(values)) {
            Err(Die(message)) => message.to_string(),
            Ok(_) => panic!("expected an error"),
        }
    }

    #[test]
    fn help_is_recognised_only_as_the_first_argument() {
        for first in ["-h", "--help", "help", "?"] {
            assert!(matches!(parse(&arguments(&[first])), Ok(Parsed::Help)));
        }
        assert!(parse(&arguments(&["shader.frag", "--help"])).is_err());
    }

    #[test]
    fn options_are_parsed_until_the_double_dash() {
        let options = parse_options(&["--legacy", "--save", "--mirror", "abc123"]);
        assert!(options.legacy);
        assert!(options.save);
        assert_eq!(options.mode, Mode::Mirror);
        assert_eq!(options.arg.as_deref(), Some(std::ffi::OsStr::new("abc123")));
    }

    #[test]
    fn last_mode_wins() {
        let options = parse_options(&["--import", "--list"]);
        assert_eq!(options.mode, Mode::List);
    }

    #[test]
    fn dash_is_a_positional() {
        let options = parse_options(&["-"]);
        assert_eq!(options.arg.as_deref(), Some(std::ffi::OsStr::new("-")));
    }

    #[test]
    fn unknown_options_are_rejected() {
        assert_eq!(
            parse_error(&["--bogus"]),
            "unknown option: --bogus (see --help)"
        );
        assert_eq!(
            parse_error(&["file.frag", "-h"]),
            "unknown option: -h (see --help)"
        );
    }

    #[test]
    fn two_positionals_are_rejected() {
        assert_eq!(
            parse_error(&["one", "two"]),
            "more than one shader given: one, two"
        );
        assert_eq!(
            parse_error(&["--", "one", "two"]),
            "more than one shader given: one, two"
        );
    }

    #[test]
    fn channel_arguments_require_a_number_and_a_file() {
        assert_eq!(
            parse_error(&["--channel"]),
            "--channel needs a number and a file"
        );
        assert_eq!(
            parse_error(&["--channel", "0"]),
            "--channel needs a number and a file"
        );
        assert_eq!(
            parse_error(&["--channel", "4", "/tmp"]),
            "channel number must be 0..3, got: 4"
        );
        assert_eq!(
            parse_error(&["--channel", "01", "/tmp"]),
            "channel number must be 0..3, got: 01"
        );
    }

    #[test]
    fn keyboard_argument_requires_a_number() {
        assert_eq!(
            parse_error(&["--keyboard"]),
            "--keyboard needs a channel number"
        );
        assert_eq!(
            parse_error(&["--keyboard", "x"]),
            "channel number must be 0..3, got: x"
        );
    }

    #[test]
    fn keyboard_and_texture_on_one_channel_conflict() {
        let directory = std::env::temp_dir();
        let texture = directory.join(format!("shtoy-cli-test-{}", std::process::id()));
        std::fs::write(&texture, b"texture").unwrap();
        let path = texture.to_string_lossy().into_owned();
        assert_eq!(
            parse_error(&["--keyboard", "1", "--channel", "1", &path]),
            "channel 1 is bound to both a texture and the keyboard"
        );
        let _ = std::fs::remove_file(&texture);
    }

    #[test]
    fn repeated_channel_textures_are_allowed() {
        let directory = std::env::temp_dir();
        let texture = directory.join(format!("shtoy-cli-test-two-{}", std::process::id()));
        std::fs::write(&texture, b"texture").unwrap();
        let path = texture.to_string_lossy().into_owned();
        let options = parse_options(&[
            "--channel",
            "2",
            &path,
            "--channel",
            "2",
            &path,
            "--keyboard",
            "0",
        ]);
        assert_eq!(options.channels.len(), 2);
        assert_eq!(options.bound_channels, vec![2, 2, 0]);
        let _ = std::fs::remove_file(&texture);
    }
}
