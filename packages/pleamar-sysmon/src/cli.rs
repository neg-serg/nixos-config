//! Command-line parsing for the worker.
//!
//! The accepted options and every error string mirror `sysmon.sh`: the shell's
//! `die()` prints `sysmon: error: <message>` to stderr and exits 2, and the
//! usage text is the shell heredoc verbatim (including the `sysmon.sh` name).

use std::ffi::OsString;

/// The shell's `usage()` heredoc, byte for byte.
pub const USAGE: &str = "\
sysmon.sh - system monitor worker (JSON lines, INTERFACES.md §7)

Usage:
  sysmon.sh [options]

Options:
  --interval-ms N      default sample cadence for the `sysmon` topic,
                       100..60000 (default: 1000)
  --once               print the handshake and one sample, then exit
  --io-max-kibps N     disk I/O that counts as 100% (default: 512000)
  --gpu-path PATH      read gpu_busy_percent from PATH instead of discovering
  --no-gpu             report gpu as an error object without looking
  --temp-path PATH     read a millidegree temperature from PATH
  --no-temp            report temp as an error object without looking
  --llm-url URL        also probe llama-swap's /running endpoint (http:// only)
  -h, --help           this text

Topics: sysmon (full sample), cpu, mem, swap, disk, gpu, temp.
Commands: subscribe, unsubscribe, set, sample, stop (one JSON object per
stdin line; every command is answered with an ack or an error line).

Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.
";

/// How the GPU/temperature source was selected on the command line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PathChoice {
    /// No flag: discover through sysfs at start-up.
    Discover,
    /// `--gpu-path`/`--temp-path` (`--no-gpu`/`--no-temp` store an empty string).
    Explicit(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Options {
    pub interval_ms: u64,
    pub once: bool,
    pub io_max_kibps: u64,
    pub gpu: PathChoice,
    pub temp: PathChoice,
    pub llm_url: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ParseResult {
    Run(Options),
    Help,
    /// Message without the `sysmon: error: ` prefix; exit code 2.
    Error(String),
}

fn lossy(value: &OsString) -> String {
    value.to_string_lossy().into_owned()
}

fn is_uint(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

/// Parse the arguments in order, exactly as the shell `while` loop did: a
/// value-taking option consumes the next argument even when it looks like a
/// flag, `--help` wins wherever it appears, and validation happens only after
/// every option has been read.
pub fn parse<I: IntoIterator<Item = OsString>>(args: I) -> ParseResult {
    let args: Vec<OsString> = args.into_iter().collect();
    let mut interval_raw = String::from("1000");
    let mut once = false;
    let mut io_max_raw = String::from("512000");
    let mut gpu = PathChoice::Discover;
    let mut temp = PathChoice::Discover;
    let mut llm_url: Option<String> = None;

    let mut index = 0;
    while index < args.len() {
        let option = lossy(&args[index]);
        match option.as_str() {
            "--interval-ms" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--interval-ms needs a value".to_string());
                }
                interval_raw = lossy(&args[index + 1]);
                index += 2;
            }
            "--once" => {
                once = true;
                index += 1;
            }
            "--io-max-kibps" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--io-max-kibps needs a value".to_string());
                }
                io_max_raw = lossy(&args[index + 1]);
                index += 2;
            }
            "--gpu-path" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--gpu-path needs a value".to_string());
                }
                gpu = PathChoice::Explicit(lossy(&args[index + 1]));
                index += 2;
            }
            "--no-gpu" => {
                gpu = PathChoice::Explicit(String::new());
                index += 1;
            }
            "--temp-path" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--temp-path needs a value".to_string());
                }
                temp = PathChoice::Explicit(lossy(&args[index + 1]));
                index += 2;
            }
            "--no-temp" => {
                temp = PathChoice::Explicit(String::new());
                index += 1;
            }
            "--llm-url" => {
                if index + 1 >= args.len() {
                    return ParseResult::Error("--llm-url needs a value".to_string());
                }
                llm_url = Some(lossy(&args[index + 1]));
                index += 2;
            }
            "-h" | "--help" => return ParseResult::Help,
            _ => {
                return ParseResult::Error(format!("unknown option '{option}' (see --help)"));
            }
        }
    }

    if !is_uint(&interval_raw) {
        return ParseResult::Error(format!(
            "--interval-ms must be an integer (got '{interval_raw}')"
        ));
    }
    let Ok(interval_ms) = interval_raw.parse::<u64>() else {
        return ParseResult::Error("--interval-ms must be 100..60000".to_string());
    };
    if !(100..=60000).contains(&interval_ms) {
        return ParseResult::Error("--interval-ms must be 100..60000".to_string());
    }

    if !is_uint(&io_max_raw) {
        return ParseResult::Error("--io-max-kibps must be a positive integer".to_string());
    }
    let Ok(io_max_kibps) = io_max_raw.parse::<u64>() else {
        return ParseResult::Error("--io-max-kibps must be a positive integer".to_string());
    };
    if io_max_kibps < 1 {
        return ParseResult::Error("--io-max-kibps must be a positive integer".to_string());
    }

    if let Some(url) = llm_url.as_deref() {
        if !url.starts_with("http://") || url.len() == "http://".len() {
            return ParseResult::Error("--llm-url must be an http:// URL".to_string());
        }
    }

    ParseResult::Run(Options {
        interval_ms,
        once,
        io_max_kibps,
        gpu,
        temp,
        llm_url,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    fn run(values: &[&str]) -> Options {
        match parse(args(values)) {
            ParseResult::Run(options) => options,
            other => panic!("expected Run, got {other:?}"),
        }
    }

    fn error(values: &[&str]) -> String {
        match parse(args(values)) {
            ParseResult::Error(message) => message,
            other => panic!("expected Error, got {other:?}"),
        }
    }

    #[test]
    fn defaults_match_the_shell() {
        let options = run(&[]);
        assert_eq!(options.interval_ms, 1000);
        assert!(!options.once);
        assert_eq!(options.io_max_kibps, 512000);
        assert_eq!(options.gpu, PathChoice::Discover);
        assert_eq!(options.temp, PathChoice::Discover);
        assert_eq!(options.llm_url, None);
    }

    #[test]
    fn every_option_is_parsed() {
        let options = run(&[
            "--interval-ms",
            "250",
            "--once",
            "--io-max-kibps",
            "1024",
            "--gpu-path",
            "/tmp/gpu",
            "--temp-path",
            "/tmp/temp",
            "--llm-url",
            "http://127.0.0.1:9292/running",
        ]);
        assert_eq!(options.interval_ms, 250);
        assert!(options.once);
        assert_eq!(options.io_max_kibps, 1024);
        assert_eq!(options.gpu, PathChoice::Explicit("/tmp/gpu".to_string()));
        assert_eq!(options.temp, PathChoice::Explicit("/tmp/temp".to_string()));
        assert_eq!(
            options.llm_url.as_deref(),
            Some("http://127.0.0.1:9292/running")
        );
    }

    #[test]
    fn no_gpu_and_no_temp_disable_discovery() {
        let options = run(&["--no-gpu", "--no-temp"]);
        assert_eq!(options.gpu, PathChoice::Explicit(String::new()));
        assert_eq!(options.temp, PathChoice::Explicit(String::new()));
    }

    #[test]
    fn last_source_flag_wins() {
        let options = run(&["--gpu-path", "/tmp/a", "--no-gpu"]);
        assert_eq!(options.gpu, PathChoice::Explicit(String::new()));
        let options = run(&["--no-gpu", "--gpu-path", "/tmp/b"]);
        assert_eq!(options.gpu, PathChoice::Explicit("/tmp/b".to_string()));
    }

    #[test]
    fn help_short_and_long() {
        assert_eq!(parse(args(&["-h"])), ParseResult::Help);
        assert_eq!(parse(args(&["--help"])), ParseResult::Help);
        assert_eq!(
            parse(args(&["--gpu-path", "/tmp/a", "--help"])),
            ParseResult::Help
        );
    }

    #[test]
    fn usage_is_the_shell_text() {
        assert!(
            USAGE.starts_with("sysmon.sh - system monitor worker (JSON lines, INTERFACES.md §7)\n")
        );
        assert!(USAGE
            .contains("Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"));
        assert!(USAGE.ends_with("cannot start.\n"));
        // The heredoc ends with exactly one newline.
        assert!(!USAGE.ends_with("\n\n"));
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
        assert_eq!(error(&["--interval-ms"]), "--interval-ms needs a value");
        assert_eq!(error(&["--io-max-kibps"]), "--io-max-kibps needs a value");
        assert_eq!(error(&["--gpu-path"]), "--gpu-path needs a value");
        assert_eq!(error(&["--temp-path"]), "--temp-path needs a value");
    }

    #[test]
    fn a_flag_can_be_swallowed_as_a_value() {
        assert_eq!(
            error(&["--interval-ms", "--once"]),
            "--interval-ms must be an integer (got '--once')"
        );
    }

    #[test]
    fn interval_errors_match_the_shell() {
        assert_eq!(
            error(&["--interval-ms", "abc"]),
            "--interval-ms must be an integer (got 'abc')"
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
        // A value too large for u64 is still an out-of-range interval.
        assert_eq!(
            error(&["--interval-ms", "999999999999999999999999"]),
            "--interval-ms must be 100..60000"
        );
    }

    #[test]
    fn interval_bounds_are_inclusive() {
        assert_eq!(run(&["--interval-ms", "100"]).interval_ms, 100);
        assert_eq!(run(&["--interval-ms", "60000"]).interval_ms, 60000);
    }

    #[test]
    fn io_max_errors_match_the_shell() {
        assert_eq!(
            error(&["--io-max-kibps", "0"]),
            "--io-max-kibps must be a positive integer"
        );
        assert_eq!(
            error(&["--io-max-kibps", "x"]),
            "--io-max-kibps must be a positive integer"
        );
        assert_eq!(
            error(&["--io-max-kibps", "-1"]),
            "--io-max-kibps must be a positive integer"
        );
        assert_eq!(run(&["--io-max-kibps", "1"]).io_max_kibps, 1);
    }
}
