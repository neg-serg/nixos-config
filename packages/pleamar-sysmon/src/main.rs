//! `pleamar-sysmon` — the system monitor worker for pleamar.
//!
//! This is a behaviour-preserving port of `files/pleamar/scripts/helpers/sysmon.sh`:
//! the same CLI, the same §7 JSON-lines protocol, the same awk sampling math and
//! the same lifecycle (auto-subscribed `sysmon` topic, 50 ms stdin poll, closed
//! stdin finishes, SIGTERM/SIGINT remove the counter state file and exit 0).

#![forbid(unsafe_code)]

mod cli;
mod command;
mod llm;
mod sample;
mod state;
#[cfg(test)]
mod testutil;

use std::io::{self, BufRead, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use cli::PathChoice;
use command::{Config, Control, Session, HANDSHAKE};
use sample::ProcPaths;
use state::StateFile;

/// The shell polled stdin with `read -t 0.05`; one command and one emission
/// pass per iteration.
const STDIN_POLL: Duration = Duration::from_millis(50);

pub(crate) fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

pub(crate) fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn main() -> std::process::ExitCode {
    let arguments: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    match cli::parse(arguments) {
        cli::ParseResult::Help => {
            print!("{}", cli::USAGE);
            std::process::ExitCode::SUCCESS
        }
        cli::ParseResult::Error(message) => {
            eprintln!("sysmon: error: {message}");
            std::process::ExitCode::from(2)
        }
        cli::ParseResult::Run(options) => match run(options) {
            Ok(()) => std::process::ExitCode::SUCCESS,
            Err(message) => {
                eprintln!("sysmon: error: {message}");
                std::process::ExitCode::from(1)
            }
        },
    }
}

fn resolve_gpu(choice: &PathChoice) -> Option<String> {
    match choice {
        PathChoice::Discover => sample::discover_gpu(Path::new("/sys/class/drm"))
            .map(|path| path.to_string_lossy().into_owned()),
        PathChoice::Explicit(value) if value.is_empty() => None,
        PathChoice::Explicit(value) => Some(value.clone()),
    }
}

fn resolve_temp(choice: &PathChoice) -> Option<String> {
    match choice {
        PathChoice::Discover => sample::discover_temp(
            Path::new("/sys/class/hwmon"),
            Path::new("/sys/class/thermal/thermal_zone0/temp"),
        )
        .map(|path| path.to_string_lossy().into_owned()),
        PathChoice::Explicit(value) if value.is_empty() => None,
        PathChoice::Explicit(value) => Some(value.clone()),
    }
}

fn run(options: cli::Options) -> Result<(), String> {
    let gpu_path = resolve_gpu(&options.gpu);
    let temp_path = resolve_temp(&options.temp);

    let state =
        StateFile::create().map_err(|error| format!("cannot create state file: {error}"))?;
    let proc_paths = ProcPaths::default();
    // Seed the baseline before the handshake, like the discarded awk run in
    // the shell: the first emitted sample covers a real interval.
    sample::seed_state(&proc_paths, state.path());

    let interrupted = Arc::new(AtomicBool::new(false));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&interrupted));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&interrupted));

    let start_ms = now_ms();
    let stdout = io::stdout();
    let mut out = stdout.lock();
    writeln!(out, "{HANDSHAKE}").map_err(|error| format!("cannot write handshake: {error}"))?;

    let config = Config {
        interval_ms: options.interval_ms,
        io_max_kibps: options.io_max_kibps,
        gpu_path,
        temp_path,
        proc_paths,
        llm_url: options.llm_url,
    };
    let mut session = Session::new(config, state, start_ms);
    session.auto_subscribe(start_ms);

    if options.once {
        sleep_interruptible(Duration::from_millis(options.interval_ms), &interrupted);
        if interrupted.load(Ordering::Relaxed) {
            return Ok(());
        }
        session
            .step(None, now_ms(), &mut out)
            .map_err(|error| format!("cannot write sample: {error}"))?;
        out.flush()
            .map_err(|error| format!("cannot flush stdout: {error}"))?;
        return Ok(());
    }

    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || read_stdin(sender));

    loop {
        let line = match receiver.recv_timeout(STDIN_POLL) {
            Ok(line) => Some(line),
            Err(RecvTimeoutError::Timeout) => None,
            // End of stdin: the scene closed the command pipe; finish.
            Err(RecvTimeoutError::Disconnected) => break,
        };
        if interrupted.load(Ordering::Relaxed) {
            break;
        }
        match session.step(line.as_deref(), now_ms(), &mut out) {
            Ok(Control::Continue) => {}
            Ok(Control::Stop) => break,
            Err(error) => return Err(format!("cannot write sample: {error}")),
        }
    }

    out.flush()
        .map_err(|error| format!("cannot flush stdout: {error}"))?;
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
                // jq decodes invalid UTF-8 inside a JSON string as U+FFFD and
                // rejects it elsewhere; the lossy conversion gives serde the
                // same text, so the reply stays the same.
                let line = String::from_utf8_lossy(&buffer).into_owned();
                if sender.send(line).is_err() {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}

fn sleep_interruptible(duration: Duration, interrupted: &AtomicBool) {
    let deadline = Instant::now() + duration;
    while Instant::now() < deadline {
        if interrupted.load(Ordering::Relaxed) {
            return;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        thread::sleep(remaining.min(Duration::from_millis(20)));
    }
}
