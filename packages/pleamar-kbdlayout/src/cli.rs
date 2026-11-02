//! Command-line parsing for the worker.
//!
//! The accepted options and every error string mirror `kbd.sh`: the shell's
//! `die()` prints `kbd: error: <message>` to stderr and exits 2, and the usage
//! text is the shell heredoc verbatim (including the `kbd.sh` name, which is
//! the installed program's historical name in the protocol contract).

use std::ffi::OsString;

/// The shell's `usage()` heredoc, byte for byte.
pub const USAGE: &str = "\
kbd.sh - keyboard-layout worker (JSON lines, INTERFACES.md §7)

Usage:
  kbd.sh [options] [command]

Commands:
  (none)                     run as the worker: handshake, subscribe, samples
  switch [next|prev]         switch the current keyboard's layout once
  switch DEVICE [next|prev]  switch a named keyboard once (default: next)

Options:
  --once               print the handshake and one sample, then exit
  --socket PATH        Hyprland .socket2.sock (default: from
                       $HYPRLAND_INSTANCE_SIGNATURE)
  --interval-ms N      heartbeat cadence of the `layout` topic, 100..60000
                       (default: 5000)
  -h, --help           this text

Topic: layout. Commands (JSON): subscribe, unsubscribe, set, sample, switch,
stop; the plain line `switch …` is accepted too.

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
";

/// Default heartbeat cadence of the auto-subscribed `layout` topic.
pub const DEFAULT_INTERVAL_MS: u64 = 5000;
pub const MIN_INTERVAL_MS: u64 = 100;
pub const MAX_INTERVAL_MS: u64 = 60000;

/// What the arguments ask the program to do.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Invocation {
    /// No `switch`: run the worker (the `status` spelling is the same).
    Worker,
    /// `switch` plus every argument that followed it, verbatim.
    Switch(Vec<String>),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Options {
    pub once: bool,
    pub socket: String,
    pub interval_ms: u64,
    pub invocation: Invocation,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// Message without the `kbd: error: ` prefix; exit code 2.
    Error(String),
}

fn lossy(value: &OsString) -> String {
    value.to_string_lossy().into_owned()
}

/// `[ "$value" -ge 100 ]`-style integers: ASCII digits only (the shell's
/// `*[!0-9]*` case pattern).
pub fn is_uint(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

/// Parse the arguments in order, exactly as the shell `while` loop did.
///
/// A value-taking option consumes the next argument even when it looks like a
/// flag, `-h`/`--help` wins wherever it appears, and `switch` swallows every
/// remaining argument into its own command line (`kbd.sh switch --help` is a
/// switch request for the device `--help`, not help). Validation happens only
/// after the whole argument list has been read.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> ParseResult {
    let args: Vec<OsString> = args.into_iter().collect();
    let mut once = false;
    let mut socket = String::new();
    let mut interval_raw = DEFAULT_INTERVAL_MS.to_string();
    let mut invocation = Invocation::Worker;

    let mut index = 0;
    while index < args.len() {
        let argument = lossy(&args[index]);
        match argument.as_str() {
            "--once" => {
                once = true;
                index += 1;
            }
            "--socket" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--socket needs a value".to_string());
                }
                socket = lossy(&args[index + 1]);
                index += 2;
            }
            "--interval-ms" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--interval-ms needs a value".to_string());
                }
                interval_raw = lossy(&args[index + 1]);
                index += 2;
            }
            "-h" | "--help" => return ParseResult::Help,
            "status" => {
                // `status` is the default command; the shell still consumed
                // every following argument into the unused switch list.
                invocation = Invocation::Worker;
                index = args.len();
            }
            "switch" => {
                let mut switch_arguments = Vec::new();
                index += 1;
                while index < args.len() {
                    switch_arguments.push(lossy(&args[index]));
                    index += 1;
                }
                invocation = Invocation::Switch(switch_arguments);
            }
            other => {
                return ParseResult::Error(format!("unknown argument '{other}' (see --help)"));
            }
        }
    }

    // The interval is validated for every command, including `switch` and
    // `--once`; the shell's `die()` came after the argument loop.
    if !is_uint(&interval_raw) {
        return ParseResult::Error(format!(
            "--interval-ms must be an integer (got '{interval_raw}')"
        ));
    }
    // The shell compared with `test`, which reports an error for values past
    // the 64-bit range; the `&& … || die` chain then died with this message.
    let interval_ms = match interval_raw.parse::<u64>() {
        Ok(value) if (MIN_INTERVAL_MS..=MAX_INTERVAL_MS).contains(&value) => value,
        _ => return ParseResult::Error("--interval-ms must be 100..60000".to_string()),
    };

    ParseResult::Run(Options {
        once,
        socket,
        interval_ms,
        invocation,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_str(args: &[&str]) -> ParseResult {
        parse(args.iter().map(OsString::from))
    }

    fn run(args: &[&str]) -> Options {
        match parse_str(args) {
            ParseResult::Run(options) => options,
            other => panic!("expected a run, got {other:?}"),
        }
    }

    fn error(args: &[&str]) -> String {
        match parse_str(args) {
            ParseResult::Error(message) => message,
            other => panic!("expected an error, got {other:?}"),
        }
    }

    #[test]
    fn defaults_match_the_shell() {
        let options = run(&[]);
        assert!(!options.once);
        assert_eq!(options.socket, "");
        assert_eq!(options.interval_ms, DEFAULT_INTERVAL_MS);
        assert_eq!(options.invocation, Invocation::Worker);
    }

    #[test]
    fn help_wins_where_it_appears() {
        assert_eq!(parse_str(&["--help"]), ParseResult::Help);
        assert_eq!(parse_str(&["-h"]), ParseResult::Help);
        assert_eq!(
            parse_str(&["--once", "--socket", "x", "-h"]),
            ParseResult::Help
        );
    }

    #[test]
    fn flag_values_are_consumed_even_when_they_look_like_flags() {
        let options = run(&["--socket", "--once"]);
        assert_eq!(options.socket, "--once");
        assert!(!options.once);
        let options = run(&["--interval-ms", "100"]);
        assert_eq!(options.interval_ms, 100);
    }

    #[test]
    fn missing_values_are_errors() {
        assert_eq!(error(&["--socket"]), "--socket needs a value");
        assert_eq!(error(&["--interval-ms"]), "--interval-ms needs a value");
    }

    #[test]
    fn unknown_arguments_are_errors() {
        assert_eq!(
            error(&["--bogus"]),
            "unknown argument '--bogus' (see --help)"
        );
        assert_eq!(
            error(&["--once", "nonsense"]),
            "unknown argument 'nonsense' (see --help)"
        );
    }

    #[test]
    fn interval_validation_matches_the_shell() {
        assert_eq!(
            error(&["--interval-ms", "x"]),
            "--interval-ms must be an integer (got 'x')"
        );
        assert_eq!(
            error(&["--interval-ms", ""]),
            "--interval-ms must be an integer (got '')"
        );
        assert_eq!(
            error(&["--interval-ms", "-5"]),
            "--interval-ms must be an integer (got '-5')"
        );
        assert_eq!(
            error(&["--interval-ms", "99"]),
            "--interval-ms must be 100..60000"
        );
        assert_eq!(
            error(&["--interval-ms", "60001"]),
            "--interval-ms must be 100..60000"
        );
        // `test` overflows past i64::MAX and fails, so the shell's `||` fired.
        assert_eq!(
            error(&["--interval-ms", "999999999999999999999"]),
            "--interval-ms must be 100..60000"
        );
        // Leading zeros are plain decimal for both parsers.
        assert_eq!(run(&["--interval-ms", "0100"]).interval_ms, 100);
        assert_eq!(run(&["--interval-ms", "60000"]).interval_ms, 60000);
    }

    #[test]
    fn switch_swallows_the_rest_of_the_line() {
        let options = run(&["switch"]);
        assert_eq!(options.invocation, Invocation::Switch(vec![]));
        let options = run(&["switch", "next"]);
        assert_eq!(options.invocation, Invocation::Switch(vec!["next".into()]));
        let options = run(&["switch", "kbd-main", "prev"]);
        assert_eq!(
            options.invocation,
            Invocation::Switch(vec!["kbd-main".into(), "prev".into()])
        );
        // Options after `switch` are device/direction words, not flags.
        let options = run(&["switch", "--once", "--help"]);
        assert!(!options.once);
        assert_eq!(
            options.invocation,
            Invocation::Switch(vec!["--once".into(), "--help".into()])
        );
        // A swallowed `--interval-ms` is a device word, not an option.
        let options = run(&["switch", "--interval-ms", "x"]);
        assert_eq!(options.interval_ms, DEFAULT_INTERVAL_MS);
        assert_eq!(
            options.invocation,
            Invocation::Switch(vec!["--interval-ms".into(), "x".into()])
        );
        // The interval is validated after the argument loop.
        assert_eq!(
            error(&["--interval-ms", "x", "switch"]),
            "--interval-ms must be an integer (got 'x')"
        );
    }

    #[test]
    fn status_is_the_worker_and_consumes_the_rest() {
        let options = run(&["status", "--bogus"]);
        assert_eq!(options.invocation, Invocation::Worker);
    }
}
