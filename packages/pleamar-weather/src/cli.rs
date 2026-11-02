//! Command-line parsing for the worker.
//!
//! Every option, default, message and exit code mirrors `weather.sh`:
//! `die()` printed `weather: error: <message>` to stderr and exited 2, and the
//! usage text is that script's heredoc verbatim (including the `weather.sh`
//! name, which is the string the old worker printed).

use std::ffi::OsString;
use std::path::PathBuf;

use crate::number;

/// The shell's `usage()` heredoc, byte for byte.
pub const USAGE: &str = "\
weather.sh - weather worker (JSON lines, INTERFACES.md §7)

Usage:
  weather.sh [options]

Options:
  --city NAME          place to geocode (default: $PLEAMAR_WEATHER_CITY)
  --lat N --lon N      coordinates; skips geocoding (both required together)
  --cache-file PATH    cache file (default: $XDG_CACHE_HOME/pleamar/helpers/weather.json)
  --ttl SECONDS        serve a cached payload younger than this (default: 300)
  --force              ignore a fresh cache for the next fetch
  --interval-ms N      default cadence of the `weather` topic, 100..3600000
                       (default: 600000)
  --once               print the handshake and one sample, then exit
  --forecast-days N    daily entries to ask for, 1..16 (default: 5)
  --timeout SECONDS    curl timeout per request (default: 8)
  --api-base URL       Open-Meteo forecast base (default: https://api.open-meteo.com/v1)
  --geocoding-base URL Open-Meteo geocoding base
  --wttr-base URL      wttr.in fallback base (default: https://wttr.in)
  --metno-base URL     MET Norway forecast base (default:
                       https://api.met.no/weatherapi/locationforecast/2.0)
  --no-fallback        do not use wttr.in when Open-Meteo fails
  -h, --help           this text

Topic: weather. Commands: subscribe, unsubscribe, set, sample, stop (one JSON
object per stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
";

/// Environment defaults the shell read. Kept in one struct so the parser can
/// be tested without touching the process environment.
#[derive(Clone, Debug, Default)]
pub struct Env {
    pub city: Option<String>,
    pub api_base: Option<String>,
    pub geocoding_base: Option<String>,
    pub wttr_base: Option<String>,
    pub metno_base: Option<String>,
    pub user_agent: Option<String>,
    pub xdg_cache_home: Option<String>,
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
            city: text("PLEAMAR_WEATHER_CITY"),
            api_base: text("PLEAMAR_WEATHER_API_BASE"),
            geocoding_base: text("PLEAMAR_WEATHER_GEOCODING_BASE"),
            wttr_base: text("PLEAMAR_WEATHER_WTTR_BASE"),
            metno_base: text("PLEAMAR_WEATHER_METNO_BASE"),
            user_agent: text("PLEAMAR_WEATHER_USER_AGENT"),
            xdg_cache_home: text("XDG_CACHE_HOME"),
            home: text("HOME"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Options {
    pub city: String,
    /// Raw `--lat` text, empty when not given (the shell tested `-n`).
    pub latitude: String,
    /// Raw `--lon` text, empty when not given.
    pub longitude: String,
    pub cache_file: PathBuf,
    pub ttl: u64,
    pub force: bool,
    pub interval_ms: u64,
    pub once: bool,
    pub forecast_days: u64,
    pub timeout: u64,
    pub api_base: String,
    pub geocoding_base: String,
    pub wttr_base: String,
    pub metno_base: String,
    pub fallback: bool,
    pub user_agent: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// Message without the `weather: error: ` prefix; exit code 2.
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

/// Parse the arguments in order, exactly as the shell's `while` loop did: a
/// value-taking option consumes the next argument even when it looks like a
/// flag, `--help` wins wherever it appears, and validation happens only after
/// every option has been read.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I, env: &Env) -> ParseResult {
    let args: Vec<OsString> = args.into_iter().collect();

    let mut city = env.city.clone().unwrap_or_default();
    let mut latitude = String::new();
    let mut longitude = String::new();
    let mut cache_file: Option<OsString> = None;
    let mut ttl_raw = String::from("300");
    let mut force = false;
    let mut interval_raw = String::from("600000");
    let mut once = false;
    let mut forecast_raw = String::from("5");
    let mut timeout_raw = String::from("8");
    let mut api_base = env
        .api_base
        .clone()
        .unwrap_or_else(|| "https://api.open-meteo.com/v1".to_string());
    let mut geocoding_base = env
        .geocoding_base
        .clone()
        .unwrap_or_else(|| "https://geocoding-api.open-meteo.com/v1".to_string());
    let mut wttr_base = env
        .wttr_base
        .clone()
        .unwrap_or_else(|| "https://wttr.in".to_string());
    let mut metno_base = env
        .metno_base
        .clone()
        .unwrap_or_else(|| "https://api.met.no/weatherapi/locationforecast/2.0".to_string());
    let mut fallback = true;
    let user_agent = env
        .user_agent
        .clone()
        .unwrap_or_else(|| "pleamar-weather/1.0".to_string());

    let mut index = 0;
    while index < args.len() {
        let option = lossy(&args[index]);
        match option.as_str() {
            "--city" => {
                city = lossy(&option_value!(&args, index, "--city"));
                index += 2;
            }
            "--lat" => {
                latitude = lossy(&option_value!(&args, index, "--lat"));
                index += 2;
            }
            "--lon" => {
                longitude = lossy(&option_value!(&args, index, "--lon"));
                index += 2;
            }
            "--cache-file" => {
                cache_file = Some(option_value!(&args, index, "--cache-file"));
                index += 2;
            }
            "--ttl" => {
                ttl_raw = lossy(&option_value!(&args, index, "--ttl"));
                index += 2;
            }
            "--force" => {
                force = true;
                index += 1;
            }
            "--interval-ms" => {
                interval_raw = lossy(&option_value!(&args, index, "--interval-ms"));
                index += 2;
            }
            "--once" => {
                once = true;
                index += 1;
            }
            "--forecast-days" => {
                forecast_raw = lossy(&option_value!(&args, index, "--forecast-days"));
                index += 2;
            }
            "--timeout" => {
                timeout_raw = lossy(&option_value!(&args, index, "--timeout"));
                index += 2;
            }
            "--api-base" => {
                api_base = lossy(&option_value!(&args, index, "--api-base"));
                index += 2;
            }
            "--geocoding-base" => {
                geocoding_base = lossy(&option_value!(&args, index, "--geocoding-base"));
                index += 2;
            }
            "--metno-base" => {
                metno_base = lossy(&option_value!(&args, index, "--metno-base"));
                index += 2;
            }
            "--wttr-base" => {
                wttr_base = lossy(&option_value!(&args, index, "--wttr-base"));
                index += 2;
            }
            "--no-fallback" => {
                fallback = false;
                index += 1;
            }
            "-h" | "--help" => return ParseResult::Help,
            _ => {
                return ParseResult::Error(format!("unknown option '{option}' (see --help)"));
            }
        }
    }

    if !latitude.is_empty() || !longitude.is_empty() {
        if latitude.is_empty() || longitude.is_empty() {
            return ParseResult::Error("--lat and --lon must be given together".to_string());
        }
        if !number::is_number(&latitude) {
            return ParseResult::Error(format!("--lat must be a number (got '{latitude}')"));
        }
        if !number::is_number(&longitude) {
            return ParseResult::Error(format!("--lon must be a number (got '{longitude}')"));
        }
    }

    if !number::is_uint(&ttl_raw) {
        return ParseResult::Error(format!(
            "--ttl must be a non-negative integer (got '{ttl_raw}')"
        ));
    }
    // The shell's arithmetic is 64-bit; an address beyond that is accepted by
    // `is_uint` but no cache age can satisfy it, so it behaves as "forever".
    let ttl = ttl_raw.parse::<u64>().unwrap_or(u64::MAX);

    if !number::is_uint(&interval_raw) {
        return ParseResult::Error(format!(
            "--interval-ms must be an integer (got '{interval_raw}')"
        ));
    }
    let interval_ms = match interval_raw.parse::<u64>() {
        Ok(value) if (100..=3_600_000).contains(&value) => value,
        _ => return ParseResult::Error("--interval-ms must be 100..3600000".to_string()),
    };

    if !number::is_uint(&forecast_raw) {
        return ParseResult::Error("--forecast-days must be 1..16".to_string());
    }
    let forecast_days = match forecast_raw.parse::<u64>() {
        Ok(value) if (1..=16).contains(&value) => value,
        _ => return ParseResult::Error("--forecast-days must be 1..16".to_string()),
    };

    if !number::is_uint(&timeout_raw) {
        return ParseResult::Error("--timeout must be 1..120".to_string());
    }
    let timeout = match timeout_raw.parse::<u64>() {
        Ok(value) if (1..=120).contains(&value) => value,
        _ => return ParseResult::Error("--timeout must be 1..120".to_string()),
    };

    let cache_file = match cache_file {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => {
            let base = match env.xdg_cache_home.as_deref() {
                Some(directory) => PathBuf::from(directory),
                None => PathBuf::from(env.home.as_deref().unwrap_or("")).join(".cache"),
            };
            base.join("pleamar/helpers/weather.json")
        }
    };

    ParseResult::Run(Options {
        city,
        latitude,
        longitude,
        cache_file,
        ttl,
        force,
        interval_ms,
        once,
        forecast_days,
        timeout,
        api_base,
        geocoding_base,
        wttr_base,
        metno_base,
        fallback,
        user_agent,
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
        assert_eq!(options.city, "");
        assert_eq!(options.latitude, "");
        assert_eq!(options.longitude, "");
        assert_eq!(options.ttl, 300);
        assert!(!options.force);
        assert_eq!(options.interval_ms, 600_000);
        assert!(!options.once);
        assert_eq!(options.forecast_days, 5);
        assert_eq!(options.timeout, 8);
        assert_eq!(options.api_base, "https://api.open-meteo.com/v1");
        assert_eq!(
            options.geocoding_base,
            "https://geocoding-api.open-meteo.com/v1"
        );
        assert_eq!(options.wttr_base, "https://wttr.in");
        assert_eq!(
            options.metno_base,
            "https://api.met.no/weatherapi/locationforecast/2.0"
        );
        assert!(options.fallback);
        assert_eq!(options.user_agent, "pleamar-weather/1.0");
        assert_eq!(
            options.cache_file,
            PathBuf::from(".cache/pleamar/helpers/weather.json")
        );
    }

    #[test]
    fn environment_defaults_and_overrides() {
        let env = Env {
            city: Some("Saint Petersburg".to_string()),
            api_base: Some("http://api.test/v1".to_string()),
            geocoding_base: Some("http://geo.test/v1".to_string()),
            wttr_base: Some("http://wttr.test".to_string()),
            metno_base: Some("http://metno.test".to_string()),
            user_agent: Some("agent/2".to_string()),
            xdg_cache_home: Some("/cache".to_string()),
            home: Some("/home/u".to_string()),
        };
        let options = run_with(&env, &[]);
        assert_eq!(options.city, "Saint Petersburg");
        assert_eq!(options.api_base, "http://api.test/v1");
        assert_eq!(options.geocoding_base, "http://geo.test/v1");
        assert_eq!(options.wttr_base, "http://wttr.test");
        assert_eq!(options.metno_base, "http://metno.test");
        assert_eq!(options.user_agent, "agent/2");
        assert_eq!(
            options.cache_file,
            PathBuf::from("/cache/pleamar/helpers/weather.json")
        );

        let options = run_with(&env, &["--city", "Moscow"]);
        assert_eq!(options.city, "Moscow");
    }

    #[test]
    fn cache_file_default_uses_home_without_xdg() {
        let env = Env {
            home: Some("/home/u".to_string()),
            ..Env::default()
        };
        let options = run_with(&env, &[]);
        assert_eq!(
            options.cache_file,
            PathBuf::from("/home/u/.cache/pleamar/helpers/weather.json")
        );
        let options = run_with(&env, &["--cache-file", "/tmp/w.json"]);
        assert_eq!(options.cache_file, PathBuf::from("/tmp/w.json"));
        // An empty --cache-file behaves as if it were not given.
        let options = run_with(&env, &["--cache-file", ""]);
        assert_eq!(
            options.cache_file,
            PathBuf::from("/home/u/.cache/pleamar/helpers/weather.json")
        );
    }

    #[test]
    fn every_option_is_parsed() {
        let options = run(&[
            "--city",
            "Oslo",
            "--lat",
            "59.9",
            "--lon",
            "10.7",
            "--cache-file",
            "/tmp/cache.json",
            "--ttl",
            "0",
            "--force",
            "--interval-ms",
            "100",
            "--once",
            "--forecast-days",
            "16",
            "--timeout",
            "120",
            "--api-base",
            "http://a",
            "--geocoding-base",
            "http://g",
            "--wttr-base",
            "http://w",
            "--metno-base",
            "http://m",
            "--no-fallback",
        ]);
        assert_eq!(options.city, "Oslo");
        assert_eq!(options.latitude, "59.9");
        assert_eq!(options.longitude, "10.7");
        assert_eq!(options.cache_file, PathBuf::from("/tmp/cache.json"));
        assert_eq!(options.ttl, 0);
        assert!(options.force);
        assert_eq!(options.interval_ms, 100);
        assert!(options.once);
        assert_eq!(options.forecast_days, 16);
        assert_eq!(options.timeout, 120);
        assert_eq!(options.api_base, "http://a");
        assert_eq!(options.geocoding_base, "http://g");
        assert_eq!(options.wttr_base, "http://w");
        assert_eq!(options.metno_base, "http://m");
        assert!(!options.fallback);
    }

    #[test]
    fn help_short_and_long_wins_anywhere() {
        assert_eq!(parse(args(&["-h"]), &Env::default()), ParseResult::Help);
        assert_eq!(parse(args(&["--help"]), &Env::default()), ParseResult::Help);
        assert_eq!(
            parse(args(&["--city", "x", "--help"]), &Env::default()),
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
        assert!(USAGE.starts_with("weather.sh - weather worker (JSON lines, INTERFACES.md §7)\n"));
        assert!(USAGE.contains("\n  --metno-base URL     MET Norway forecast base (default:\n"));
        assert!(USAGE
            .contains("Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"));
        assert!(!USAGE.ends_with("\n\n"));
        // The heredoc has 28 lines.
        assert_eq!(USAGE.lines().count(), 28);
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
            ("--city", "--city needs a value"),
            ("--lat", "--lat needs a value"),
            ("--lon", "--lon needs a value"),
            ("--cache-file", "--cache-file needs a value"),
            ("--ttl", "--ttl needs a value"),
            ("--interval-ms", "--interval-ms needs a value"),
            ("--forecast-days", "--forecast-days needs a value"),
            ("--timeout", "--timeout needs a value"),
            ("--api-base", "--api-base needs a value"),
            ("--geocoding-base", "--geocoding-base needs a value"),
            ("--metno-base", "--metno-base needs a value"),
            ("--wttr-base", "--wttr-base needs a value"),
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
        // --force is swallowed as the city and nothing else fails.
        assert_eq!(run(&["--city", "--force"]).city, "--force");
        // The last occurrence wins.
        assert_eq!(run(&["--city", "a", "--city", "b"]).city, "b");
    }

    #[test]
    fn lat_lon_pair_and_number_errors() {
        assert_eq!(
            error(&["--lat", "59.9"]),
            "--lat and --lon must be given together"
        );
        assert_eq!(
            error(&["--lon", "10.7"]),
            "--lat and --lon must be given together"
        );
        assert_eq!(
            error(&["--lat", "", "--lon", "10.7"]),
            "--lat and --lon must be given together"
        );
        assert_eq!(
            error(&["--lat", "x", "--lon", "1"]),
            "--lat must be a number (got 'x')"
        );
        assert_eq!(
            error(&["--lat", "1", "--lon", "x"]),
            "--lon must be a number (got 'x')"
        );
        for value in [".5", "5.", "1e3", "+-1"] {
            assert!(error(&["--lat", value, "--lon", "1"]).starts_with("--lat must be a number"));
        }
        assert_eq!(run(&["--lat", "+59.9", "--lon", "-10.7"]).latitude, "+59.9");
    }

    #[test]
    fn ttl_errors_match_the_shell() {
        assert_eq!(
            error(&["--ttl", "-1"]),
            "--ttl must be a non-negative integer (got '-1')"
        );
        assert_eq!(
            error(&["--ttl", "x"]),
            "--ttl must be a non-negative integer (got 'x')"
        );
        assert_eq!(
            error(&["--ttl", ""]),
            "--ttl must be a non-negative integer (got '')"
        );
        assert_eq!(run(&["--ttl", "0"]).ttl, 0);
    }

    #[test]
    fn interval_errors_match_the_shell() {
        assert_eq!(
            error(&["--interval-ms", "abc"]),
            "--interval-ms must be an integer (got 'abc')"
        );
        assert_eq!(
            error(&["--interval-ms", "-5"]),
            "--interval-ms must be an integer (got '-5')"
        );
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
        assert_eq!(run(&["--interval-ms", "3600000"]).interval_ms, 3_600_000);
    }

    #[test]
    fn forecast_and_timeout_errors_match_the_shell() {
        for value in ["0", "17", "x", "", "-1"] {
            assert_eq!(
                error(&["--forecast-days", value]),
                "--forecast-days must be 1..16"
            );
        }
        for value in ["0", "121", "x", "", "-1"] {
            assert_eq!(error(&["--timeout", value]), "--timeout must be 1..120");
        }
        assert_eq!(run(&["--forecast-days", "1"]).forecast_days, 1);
        assert_eq!(run(&["--forecast-days", "16"]).forecast_days, 16);
        assert_eq!(run(&["--timeout", "1"]).timeout, 1);
        assert_eq!(run(&["--timeout", "120"]).timeout, 120);
    }
}
