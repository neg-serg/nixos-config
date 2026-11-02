//! Command-line parsing for the worker.
//!
//! Every option, default, message and exit code mirrors `calendar.sh`:
//! `die()` printed `calendar: error: <message>` to stderr and exited 2, and
//! the usage text is that script's heredoc verbatim (including the
//! `calendar.sh` name, which is the string the old worker printed).

use std::ffi::OsString;
use std::path::PathBuf;

/// The shell's `usage()` heredoc, byte for byte.
pub const USAGE: &str = "\
calendar.sh - calendar worker (JSON lines, INTERFACES.md §7)

Usage:
  calendar.sh [options]

Options:
  --month YYYY-MM      month to list first (default: the current one)
  --country CC         also fetch public holidays for this ISO country code
  --cache-dir DIR      where month/holiday caches live
                       (default: $XDG_CACHE_HOME/pleamar/helpers)
  --interval-ms N      default cadence of the `calendar` topic, 100..3600000
                       (default: 300000)
  --once               print the handshake and one sample, then exit
  --holidays-base URL  holidays API base (default: https://date.nager.at/api/v3)
  --workdays-base URL  production calendar base (default: https://isdayoff.ru/api/getdata)
  -h, --help           this text

Topic: calendar. Commands: subscribe, unsubscribe, set, sample, stop, with an
optional `month` field on subscribe/sample/set for month navigation (one JSON
object per stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
";

pub const USER_AGENT: &str = "pleamar-calendar/1.0";

const DEFAULT_HOLIDAYS_BASE: &str = "https://date.nager.at/api/v3";
const DEFAULT_WORKDAYS_BASE: &str = "https://isdayoff.ru/api/getdata";

/// Environment defaults the shell read. Kept in one struct so the parser can
/// be tested without touching the process environment.
#[derive(Clone, Debug, Default)]
pub struct Env {
    pub holidays_base: Option<String>,
    pub workdays_base: Option<String>,
    pub xdg_cache_home: Option<String>,
    pub xdg_data_home: Option<String>,
    pub home: Option<String>,
}

impl Env {
    /// `VAR` unset or empty is the same thing for the shell's `${VAR:-default}`.
    pub fn from_process() -> Self {
        fn text(name: &str) -> Option<String> {
            std::env::var_os(name)
                .filter(|value| !value.is_empty())
                .map(|value| value.to_string_lossy().into_owned())
        }
        Self {
            holidays_base: text("PLEAMAR_HOLIDAYS_BASE"),
            workdays_base: text("PLEAMAR_WORKDAYS_BASE"),
            xdg_cache_home: text("XDG_CACHE_HOME"),
            xdg_data_home: text("XDG_DATA_HOME"),
            home: text("HOME"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Options {
    /// Raw `--month` text; empty means "the current month", like the shell's
    /// `${MONTH:-$(date +%Y-%m)}`.
    pub month: String,
    pub country: String,
    pub cache_dir: PathBuf,
    pub interval_ms: u64,
    pub once: bool,
    pub holidays_base: String,
    pub workdays_base: String,
    /// `${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/Pill/state.json`.
    pub pill_state: PathBuf,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// Message without the `calendar: error: ` prefix; exit code 2.
    Error(String),
}

fn lossy(value: &OsString) -> String {
    value.to_string_lossy().into_owned()
}

fn value_of(args: &[OsString], index: usize, name: &str) -> Result<OsString, ParseResult> {
    match args.get(index + 1) {
        Some(value) => Ok(value.clone()),
        None => Err(ParseResult::Error(format!("{name} needs a value"))),
    }
}

/// The shell's `[ $# -ge 2 ] || die "… needs a value"`, used as an expression:
/// the missing-value early return leaves the calling parser immediately.
macro_rules! option_value {
    ($args:expr, $index:expr, $name:literal) => {
        match value_of($args, $index, $name) {
            Ok(value) => value,
            Err(result) => return result,
        }
    };
}

/// `XDG_*`-then-`HOME` defaults, exactly the shell's
/// `${XDG_CACHE_HOME:-$HOME/.cache}` and
/// `${XDG_DATA_HOME:-$HOME/.local/share}`.
fn base_directory(xdg: &Option<String>, home: &Option<String>, fallback: &str) -> PathBuf {
    match xdg {
        Some(directory) => PathBuf::from(directory),
        None => PathBuf::from(home.as_deref().unwrap_or("")).join(fallback),
    }
}

/// Parse the arguments in order, exactly as the shell's `while` loop did: a
/// value-taking option consumes the next argument even when it looks like a
/// flag, `--help` wins wherever it appears, and validation happens only after
/// every option has been read.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I, env: &Env) -> ParseResult {
    let args: Vec<OsString> = args.into_iter().collect();

    let mut month = String::new();
    let mut country = String::new();
    let mut cache_dir: Option<OsString> = None;
    let mut interval_raw = String::from("300000");
    let mut once = false;
    // `${PLEAMAR_HOLIDAYS_BASE:-default}`: unset and empty are the same.
    let mut holidays_base = env
        .holidays_base
        .clone()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_HOLIDAYS_BASE.to_string());
    let mut workdays_base = env
        .workdays_base
        .clone()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_WORKDAYS_BASE.to_string());

    let mut index = 0;
    while index < args.len() {
        let option = lossy(&args[index]);
        match option.as_str() {
            "--month" => {
                month = lossy(&option_value!(&args, index, "--month"));
                index += 2;
            }
            "--country" => {
                country = lossy(&option_value!(&args, index, "--country"));
                index += 2;
            }
            "--cache-dir" => {
                cache_dir = Some(option_value!(&args, index, "--cache-dir"));
                index += 2;
            }
            "--interval-ms" => {
                interval_raw = lossy(&option_value!(&args, index, "--interval-ms"));
                index += 2;
            }
            "--once" => {
                once = true;
                index += 1;
            }
            "--workdays-base" => {
                workdays_base = lossy(&option_value!(&args, index, "--workdays-base"));
                index += 2;
            }
            "--holidays-base" => {
                holidays_base = lossy(&option_value!(&args, index, "--holidays-base"));
                index += 2;
            }
            "-h" | "--help" => return ParseResult::Help,
            _ => {
                return ParseResult::Error(format!("unknown option '{option}' (see --help)"));
            }
        }
    }

    // The shell's `case "$COUNTRY" in '' | [A-Za-z][A-Za-z])`.
    if !country.is_empty()
        && !(country.len() == 2 && country.bytes().all(|byte| byte.is_ascii_alphabetic()))
    {
        return ParseResult::Error(format!(
            "--country must be a two-letter code (got '{country}')"
        ));
    }

    if interval_raw.is_empty() || !interval_raw.bytes().all(|byte| byte.is_ascii_digit()) {
        return ParseResult::Error(format!(
            "--interval-ms must be an integer (got '{interval_raw}')"
        ));
    }
    let interval_ms = match interval_raw.parse::<u128>() {
        Ok(value) if (100..=3_600_000).contains(&value) => value as u64,
        _ => return ParseResult::Error("--interval-ms must be 100..3600000".to_string()),
    };

    let cache_dir = match cache_dir {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => base_directory(&env.xdg_cache_home, &env.home, ".cache").join("pleamar/helpers"),
    };
    let pill_state = base_directory(&env.xdg_data_home, &env.home, ".local/share")
        .join("pleamar/Pill/state.json");

    ParseResult::Run(Options {
        month,
        country,
        cache_dir,
        interval_ms,
        once,
        holidays_base,
        workdays_base,
        pill_state,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    fn run_with(env: &Env, values: &[&str]) -> Options {
        match parse(args(values), env) {
            ParseResult::Run(options) => options,
            other => panic!("expected Run, got {other:?}"),
        }
    }

    fn run(values: &[&str]) -> Options {
        run_with(&Env::default(), values)
    }

    fn error(values: &[&str]) -> String {
        match parse(args(values), &Env::default()) {
            ParseResult::Error(message) => message,
            other => panic!("expected Error, got {other:?}"),
        }
    }

    #[test]
    fn defaults_match_the_shell() {
        let options = run(&[]);
        assert_eq!(options.month, "");
        assert_eq!(options.country, "");
        assert_eq!(
            options.cache_dir,
            PathBuf::from(".cache/pleamar/helpers"),
            "no HOME in a cleared environment"
        );
        assert_eq!(options.interval_ms, 300_000);
        assert!(!options.once);
        assert_eq!(options.holidays_base, "https://date.nager.at/api/v3");
        assert_eq!(options.workdays_base, "https://isdayoff.ru/api/getdata");
        assert_eq!(
            options.pill_state,
            PathBuf::from(".local/share/pleamar/Pill/state.json")
        );
    }

    #[test]
    fn environment_defaults_and_overrides() {
        let env = Env {
            holidays_base: Some("http://holidays.test/v3".to_string()),
            workdays_base: Some("http://work.test/getdata".to_string()),
            xdg_cache_home: Some("/cache".to_string()),
            xdg_data_home: Some("/data".to_string()),
            home: Some("/home/u".to_string()),
        };
        let options = run_with(&env, &[]);
        assert_eq!(options.holidays_base, "http://holidays.test/v3");
        assert_eq!(options.workdays_base, "http://work.test/getdata");
        assert_eq!(options.cache_dir, PathBuf::from("/cache/pleamar/helpers"));
        assert_eq!(
            options.pill_state,
            PathBuf::from("/data/pleamar/Pill/state.json")
        );

        // An empty base behaves as if it were not set (`${VAR:-default}`).
        let env = Env {
            holidays_base: Some(String::new()),
            ..Env::default()
        };
        assert_eq!(
            run_with(&env, &[]).holidays_base,
            "https://date.nager.at/api/v3"
        );

        let options = run_with(&env, &["--holidays-base", "http://cli.test"]);
        assert_eq!(options.holidays_base, "http://cli.test");
    }

    #[test]
    fn cache_dir_default_uses_home_without_xdg() {
        let env = Env {
            home: Some("/home/u".to_string()),
            ..Env::default()
        };
        let options = run_with(&env, &[]);
        assert_eq!(
            options.cache_dir,
            PathBuf::from("/home/u/.cache/pleamar/helpers")
        );
        assert_eq!(
            options.pill_state,
            PathBuf::from("/home/u/.local/share/pleamar/Pill/state.json")
        );
        let options = run_with(&env, &["--cache-dir", "/tmp/cache"]);
        assert_eq!(options.cache_dir, PathBuf::from("/tmp/cache"));
        // An empty --cache-dir behaves as if it were not given.
        let options = run_with(&env, &["--cache-dir", ""]);
        assert_eq!(
            options.cache_dir,
            PathBuf::from("/home/u/.cache/pleamar/helpers")
        );
    }

    #[test]
    fn every_option_is_parsed() {
        let options = run(&[
            "--month",
            "2026-11-05",
            "--country",
            "RU",
            "--cache-dir",
            "/tmp/cache",
            "--interval-ms",
            "100",
            "--once",
            "--holidays-base",
            "http://h",
            "--workdays-base",
            "http://w",
        ]);
        assert_eq!(options.month, "2026-11-05");
        assert_eq!(options.country, "RU");
        assert_eq!(options.cache_dir, PathBuf::from("/tmp/cache"));
        assert_eq!(options.interval_ms, 100);
        assert!(options.once);
        assert_eq!(options.holidays_base, "http://h");
        assert_eq!(options.workdays_base, "http://w");
    }

    #[test]
    fn help_short_and_long_wins_anywhere() {
        assert_eq!(parse(args(&["-h"]), &Env::default()), ParseResult::Help);
        assert_eq!(parse(args(&["--help"]), &Env::default()), ParseResult::Help);
        assert_eq!(
            parse(args(&["--month", "2026-11", "--help"]), &Env::default()),
            ParseResult::Help
        );
        // The shell's option loop dies on the first bad option, so a later
        // --help is never reached.
        assert_eq!(
            parse(args(&["--bogus", "--help"]), &Env::default()),
            ParseResult::Error("unknown option '--bogus' (see --help)".to_string())
        );
    }

    #[test]
    fn usage_is_the_shell_text() {
        assert!(USAGE.starts_with("calendar.sh - calendar worker (JSON lines, INTERFACES.md §7)\n"));
        assert!(USAGE.contains(
            "\n  --workdays-base URL  production calendar base (default: https://isdayoff.ru/api/getdata)\n"
        ));
        assert!(USAGE
            .contains("Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"));
        assert!(!USAGE.ends_with("\n\n"));
        // The heredoc has 22 lines.
        assert_eq!(USAGE.lines().count(), 22);
    }

    #[test]
    fn unknown_option_message() {
        assert_eq!(error(&["--bogus"]), "unknown option '--bogus' (see --help)");
        assert_eq!(
            error(&["positional"]),
            "unknown option 'positional' (see --help)"
        );
    }

    #[test]
    fn missing_values() {
        for (option, message) in [
            ("--month", "--month needs a value"),
            ("--country", "--country needs a value"),
            ("--cache-dir", "--cache-dir needs a value"),
            ("--interval-ms", "--interval-ms needs a value"),
            ("--workdays-base", "--workdays-base needs a value"),
            ("--holidays-base", "--holidays-base needs a value"),
        ] {
            assert_eq!(error(&[option]), message, "{option}");
        }
    }

    #[test]
    fn a_flag_can_be_swallowed_as_a_value() {
        assert_eq!(
            error(&["--interval-ms", "--once"]),
            "--interval-ms must be an integer (got '--once')"
        );
        assert_eq!(run(&["--month", "--once"]).month, "--once");
        assert_eq!(run(&["--month", "a", "--month", "b"]).month, "b");
    }

    #[test]
    fn country_errors_match_the_shell() {
        for value in ["RUS", "R", "R1", "12", "R U"] {
            assert_eq!(
                error(&["--country", value]),
                format!("--country must be a two-letter code (got '{value}')"),
                "{value}"
            );
        }
        assert_eq!(run(&["--country", "ru"]).country, "ru");
        assert_eq!(run(&["--country", ""]).country, "");
    }

    #[test]
    fn interval_errors_match_the_shell() {
        for value in ["abc", "-5", "", "10 0", "1.0"] {
            assert_eq!(
                error(&["--interval-ms", value]),
                format!("--interval-ms must be an integer (got '{value}')"),
                "{value}"
            );
        }
        assert_eq!(
            error(&["--interval-ms", "99"]),
            "--interval-ms must be 100..3600000"
        );
        assert_eq!(
            error(&["--interval-ms", "3600001"]),
            "--interval-ms must be 100..3600000"
        );
        assert_eq!(
            error(&["--interval-ms", "999999999999999999999999"]),
            "--interval-ms must be 100..3600000"
        );
        assert_eq!(run(&["--interval-ms", "100"]).interval_ms, 100);
        assert_eq!(run(&["--interval-ms", "3600000"]).interval_ms, 3_600_000);
    }
}
