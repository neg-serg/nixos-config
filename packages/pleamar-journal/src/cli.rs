//! Command-line parsing for the journal snapshot.
//!
//! The shell parsed its line with one `while`/`case` loop, and that loop's
//! failure modes are part of the interface: a value-taking option at the end
//! of the line made `shift 2` fail and `set -e` exited 1 **without a message**;
//! `-h`/`--help` printed lines 2-20 of the script and exited 0; anything else
//! printed `journal: unknown argument '<arg>'` and exited 2. Options are
//! consumed left to right, so the last `--since`/`--entries` wins and `--help`
//! wins only if it is reached before an unknown argument.

use std::ffi::OsString;

/// `sed -n '2,20p' journal.sh`, byte for byte (including the header's trailing
/// blank line). The text still names `journal.sh`: it is the frozen `--help`
/// output the port has to reproduce, not a new page.
pub const USAGE: &str = include_str!("usage.txt");

#[derive(Debug, PartialEq, Eq)]
pub struct Options {
    /// `--since` value, forwarded as one `journalctl` argument (`-24h` default).
    pub since: OsString,
    /// `--entries` value, forwarded to `journalctl -n` (`8` default). The
    /// shell never validated it; journalctl does.
    pub entries: OsString,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// A value-taking option was the last argument: the shell's `shift 2`
    /// failed, `set -e` exited 1, and nothing was written to either stream.
    MissingValue,
    /// The whole argument as the shell's `$1` had it (byte-exact on stderr).
    Unknown(OsString),
}

pub fn parse<I: IntoIterator<Item = OsString>>(arguments: I) -> ParseResult {
    let arguments: Vec<OsString> = arguments.into_iter().collect();
    let mut since = OsString::from("-24h");
    let mut entries = OsString::from("8");

    let mut index = 0;
    while index < arguments.len() {
        match arguments[index].to_str() {
            Some("--since") => {
                let Some(value) = arguments.get(index + 1) else {
                    return ParseResult::MissingValue;
                };
                since = value.clone();
                index += 2;
            }
            Some("--entries") => {
                let Some(value) = arguments.get(index + 1) else {
                    return ParseResult::MissingValue;
                };
                entries = value.clone();
                index += 2;
            }
            Some("-h") | Some("--help") => return ParseResult::Help,
            _ => return ParseResult::Unknown(arguments[index].clone()),
        }
    }

    ParseResult::Run(Options { since, entries })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_list(arguments: &[&str]) -> ParseResult {
        parse(arguments.iter().map(OsString::from))
    }

    #[test]
    fn defaults_match_the_shell() {
        assert_eq!(
            parse_list(&[]),
            ParseResult::Run(Options {
                since: OsString::from("-24h"),
                entries: OsString::from("8"),
            })
        );
    }

    #[test]
    fn last_value_wins_and_values_may_look_like_flags() {
        assert_eq!(
            parse_list(&["--since", "-1h", "--entries", "3", "--since", "--help"]),
            ParseResult::Run(Options {
                since: OsString::from("--help"),
                entries: OsString::from("3"),
            })
        );
    }

    #[test]
    fn help_stops_at_its_position() {
        assert_eq!(parse_list(&["--help", "--bogus"]), ParseResult::Help);
        assert_eq!(
            parse_list(&["--bogus", "--help"]),
            ParseResult::Unknown(OsString::from("--bogus"))
        );
    }

    #[test]
    fn a_missing_value_is_the_shell_shift_failure() {
        assert_eq!(parse_list(&["--since"]), ParseResult::MissingValue);
        assert_eq!(parse_list(&["--entries"]), ParseResult::MissingValue);
        assert_eq!(
            parse_list(&["--entries", "3", "--since"]),
            ParseResult::MissingValue
        );
    }

    #[test]
    fn any_other_argument_is_unknown_verbatim() {
        assert_eq!(
            parse_list(&["--bogus"]),
            ParseResult::Unknown(OsString::from("--bogus"))
        );
        assert_eq!(
            parse_list(&["-x"]),
            ParseResult::Unknown(OsString::from("-x"))
        );
    }

    #[test]
    fn usage_is_the_journal_header() {
        assert_eq!(USAGE.lines().count(), 19);
        assert!(USAGE.starts_with("# journal.sh - journal snapshot worker"));
        assert!(USAGE.contains("# Usage: journal.sh [--since \"-24h\"] [--entries N] [--help]"));
        // sed printed line 20 of the script, which is empty.
        assert!(USAGE.ends_with("systemctl is missing.\n\n"));
    }
}
