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
