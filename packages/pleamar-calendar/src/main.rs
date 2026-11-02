//! `pleamar-calendar` — the calendar worker for pleamar.
//!
//! This is a behaviour-preserving port of
//! `files/pleamar/scripts/helpers/calendar.sh`: the same CLI, environment
//! defaults, usage text and exit codes; the same §7 JSON-lines protocol with
//! the script's `month` domain argument; the same data pipeline (`khal list`
//! with the ISO → dd.mm.yyyy retry, the 120 s month cache, date.nager.at
//! holidays and the isdayoff.ru production calendar with their 24 h caches)
//! and the same lifecycle (the `calendar` topic auto-subscribed with `next=0`,
//! a 50 ms stdin poll, a closed stdin finishing the worker, SIGTERM/SIGINT
//! exiting 0 and aborting an in-flight request).
//!
//! Two shell start checks are gone because their tools are compiled in: jq and
//! curl. The one remaining start error is a missing `khal`, which stays a
//! subprocess because it owns the user's calendars and config.
//!
//! Modules: `cli` (options), `date` (month/date arithmetic), `khal` (the
//! subprocess and its event lines), `holidays`/`workdays` (the two HTTP
//! sources), `cache` (atomic byte caches), `payload` (the data object),
//! `pills` (the pill tracker's file), `worker` (the pipeline), `protocol` (the
//! lines), `http` (curl-equivalent requests), `json` (jq-compatible strings).

#![forbid(unsafe_code)]

mod cache;
mod cli;
mod date;
mod failure;
mod holidays;
mod http;
mod json;
mod khal;
mod payload;
mod pills;
mod protocol;
mod workdays;
mod worker;

#[cfg(test)]
mod testutil;

use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use date::Month;
use worker::Outcome;

/// The shell polled stdin with `read -t 0.05`; one command and one emission
/// pass per iteration.
const STDIN_POLL: Duration = Duration::from_millis(50);

pub(crate) fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

pub(crate) fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

fn main() -> std::process::ExitCode {
    let arguments: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    let environment = cli::Env::from_process();
    let options = match cli::parse(arguments, &environment) {
        cli::ParseResult::Help => {
            print!("{}", cli::USAGE);
            return std::process::ExitCode::SUCCESS;
        }
        cli::ParseResult::Error(message) => {
            eprintln!("calendar: error: {message}");
            return std::process::ExitCode::from(2);
        }
        cli::ParseResult::Run(options) => options,
    };

    // The shell's start checks ran after option parsing: jq (now compiled in),
    // then khal, then the initial month. A worker that cannot start says so in
    // the protocol shape and exits 1.
    if !khal::installed() {
        println!("{}", protocol::start_error("khal not installed"));
        return std::process::ExitCode::from(1);
    }
    let month = match initial_month(&options) {
        Ok(month) => month,
        Err(raw) => {
            eprintln!("calendar: error: --month must be YYYY-MM or YYYY-MM-DD (got '{raw}')");
            return std::process::ExitCode::from(2);
        }
    };

    match run(options, month) {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("calendar: error: {message}");
            std::process::ExitCode::from(1)
        }
    }
}

/// `${MONTH:-$(date +%Y-%m)}`, then `set_month`.
fn initial_month(options: &cli::Options) -> Result<Month, String> {
    let raw = if options.month.is_empty() {
        date::current_month()
    } else {
        options.month.clone()
    };
    Month::parse(&raw).ok_or(raw)
}

fn run(options: cli::Options, month: Month) -> Result<(), String> {
    let once = options.once;
    let interval_ms = options.interval_ms;

    let interrupted = Arc::new(AtomicBool::new(false));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&interrupted));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&interrupted));

    let worker = worker::Worker::new(options, Arc::clone(&interrupted));
    let stdout = io::stdout();
    let mut out = stdout.lock();
    protocol::write_handshake(&mut out)
        .map_err(|error| format!("cannot write handshake: {error}"))?;
    // bash flushes stdout before it forks khal or curls, so a scene sees the
    // handshake while the first sample is still being fetched.
    out.flush()
        .map_err(|error| format!("cannot flush stdout: {error}"))?;

    if once {
        // A signal may cut the sample short; the shell's trap also exited 0
        // without writing one.
        worker
            .emit_sample(&month, &mut out)
            .map_err(|error| format!("cannot write sample: {error}"))?;
        out.flush()
            .map_err(|error| format!("cannot flush stdout: {error}"))?;
        return Ok(());
    }

    let mut session = protocol::Session::new(interval_ms, month);
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || read_stdin(sender));

    'worker: loop {
        let line = match receiver.recv_timeout(STDIN_POLL) {
            Ok(line) => Some(line),
            Err(RecvTimeoutError::Timeout) => None,
            // End of stdin: the scene closed the command pipe; finish.
            Err(RecvTimeoutError::Disconnected) => break,
        };
        if let Some(line) = &line {
            if !line.is_empty() {
                let control = session
                    .handle_line(line, &mut out)
                    .map_err(|error| format!("cannot write reply: {error}"))?;
                // The ack goes out before any khal/HTTP work the command
                // triggered, like bash flushing before the next fork.
                out.flush()
                    .map_err(|error| format!("cannot flush stdout: {error}"))?;
                if control == protocol::Control::Stop {
                    break;
                }
            }
        }
        if interrupted.load(Ordering::Relaxed) {
            break;
        }
        let now = now_ms();
        while session.due(now) {
            session.advance(now);
            let month = session.month().clone();
            match worker
                .emit_sample(&month, &mut out)
                .map_err(|error| format!("cannot write sample: {error}"))?
            {
                Outcome::Continue => {}
                Outcome::Interrupted => break 'worker,
            }
            out.flush()
                .map_err(|error| format!("cannot flush stdout: {error}"))?;
        }
    }

    // A signal on the way out is not a write error: the process is finishing
    // cleanly on the same signals the shell trapped.
    let _ = out.flush();
    Ok(())
}

/// Read complete stdin lines and hand them to the event loop. A final line
/// without a newline is dropped without being handled: bash's `read` fails at
/// EOF and the shell exits before `handle_command` sees the partial text.
fn read_stdin(sender: mpsc::Sender<String>) {
    let stdin = io::stdin();
    let mut reader = stdin.lock();
    let mut buffer = Vec::new();
    loop {
        buffer.clear();
        match reader.read_until(b'\n', &mut buffer) {
            Ok(0) => break,
            Ok(_) => {
                if !buffer.ends_with(b"\n") {
                    break;
                }
                buffer.pop();
                // jq decodes invalid UTF-8 only inside strings; the lossy
                // conversion gives the same text for the command fields.
                let line = String::from_utf8_lossy(&buffer).into_owned();
                if sender.send(line).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}
