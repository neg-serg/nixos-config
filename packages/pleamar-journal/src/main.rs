//! `pleamar-journal` — the pleamar journal snapshot worker.
//!
//! A behaviour-preserving port of `files/pleamar/scripts/helpers/journal.sh`.
//! Unlike the sampling helpers it is not a §7 stream: the panels scene runs it
//! with `run(...)` when the system drawer opens and reads one JSON line
//! (INTERFACES.md §7 lists the install name; the data schema is the shell's):
//!
//! ```text
//! {"ok":true,"worker":"journal","version":1,
//!  "data":{"logs":N,"errors":N,"services":N,
//!          "entries":[{"time":"14:32","service":"x.service","msg":"…"}]}}
//! ```
//!
//! It has no handshake and no stdin commands on purpose — adding them would
//! put a line before the snapshot that `panels.luau` would try to decode as one.

#![forbid(unsafe_code)]

mod cli;
mod jq;
mod process;
mod snapshot;
mod timefmt;

use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    match cli::parse(arguments) {
        cli::ParseResult::Help => {
            let stdout = io::stdout();
            let mut out = stdout.lock();
            let _ = out
                .write_all(cli::USAGE.as_bytes())
                .and_then(|_| out.flush());
            ExitCode::SUCCESS
        }
        // The shell's failed `shift 2` under `set -e`: status 1, no output.
        cli::ParseResult::MissingValue => ExitCode::from(1),
        cli::ParseResult::Unknown(argument) => {
            let mut stderr = io::stderr().lock();
            let _ = stderr.write_all(b"journal: unknown argument '");
            let _ = stderr.write_all(argument.as_bytes());
            let _ = stderr.write_all(b"'\n");
            ExitCode::from(2)
        }
        cli::ParseResult::Run(options) => run(&options),
    }
}

fn run(options: &cli::Options) -> ExitCode {
    let signals = process::Signals::install();
    match snapshot::build(options, &signals) {
        Ok(line) => {
            let stdout = io::stdout();
            let mut out = stdout.lock();
            let written = out
                .write_all(line.as_bytes())
                .and_then(|_| out.write_all(b"\n"))
                .and_then(|_| out.flush());
            if let Err(error) = written {
                eprintln!("journal: error: cannot write snapshot: {error}");
                return ExitCode::from(1);
            }
            ExitCode::SUCCESS
        }
        // `command -v journalctl` failed in the shell; no `error:` prefix there.
        Err(snapshot::Failure::JournalctlNotFound) => {
            eprintln!("journal: journalctl not found");
            ExitCode::from(1)
        }
        // The shell's entries pipeline ended in a failing `jq --argjson`.
        Err(snapshot::Failure::EntriesPipeline) => {
            let mut stderr = io::stderr().lock();
            let _ = stderr.write_all(snapshot::ENTRIES_FAILURE_STDERR.as_bytes());
            ExitCode::from(2)
        }
        Err(snapshot::Failure::Interrupted(signal)) => {
            process::die_by_signal(signal);
            ExitCode::from(128 + signal as u8)
        }
    }
}
