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

Topics: sysmon (full sample), cpu, mem, swap, disk, gpu, temp, llm.
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
