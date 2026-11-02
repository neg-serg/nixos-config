//! Running `journalctl`/`systemctl` and handling termination signals.
//!
//! The shell ran each source in a pipeline and let bash's default SIGTERM /
//! SIGINT disposition end it: no trap, so the worker was gone at once and the
//! pipeline children were left behind. The port keeps the same exit status
//! (the process dies by the signal, `143`/`130` to a shell) but kills and reaps
//! its child first, which is the lifecycle the helper README asks for.
//!
//! Counted output is streamed, not buffered: `journalctl -o cat` can be tens of
//! megabytes (the reference journal measured ~160k lines/day) and the shell fed
//! it straight into `wc -l`. Only the entries call keeps its output in memory.

use std::ffi::OsStr;
use std::io::{self, Read};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

/// The shell's `wc -l` was fed by a pipe; polling `try_wait` is how this side
/// notices a child that is done without losing the signal check.
const POLL: Duration = Duration::from_millis(5);

/// The signals the shell did not trap (`set -e` does not catch signals).
pub struct Signals {
    pending: Arc<AtomicUsize>,
}

impl Signals {
    pub fn install() -> Self {
        let pending = Arc::new(AtomicUsize::new(0));
        for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
            let _ =
                signal_hook::flag::register_usize(signal, Arc::clone(&pending), signal as usize);
        }
        Self { pending }
    }

    pub fn pending(&self) -> Option<i32> {
        match self.pending.load(Ordering::Relaxed) {
            0 => None,
            signal => Some(signal as i32),
        }
    }
}

/// Die by the signal the caller sent, after the child has been cleaned up.
/// `emulate_default_handler` resets the disposition and raises it, so the
/// parent sees a signal death exactly like it did for the bash script.
pub fn die_by_signal(signal: i32) {
    if signal_hook::low_level::emulate_default_handler(signal).is_err() {
        std::process::exit(128 + signal);
    }
}

/// `command -v <name>`: the first `PATH` entry that holds a regular file with
/// this name. bash's `command -v` does not require the execute bit (a
/// non-executable hit fails later, when the pipeline starts it) and an unset
/// PATH is an empty search path here, which is also what NixOS bash does.
pub fn on_path(name: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|directory| {
        std::fs::metadata(directory.join(name))
            .map(|metadata| metadata.is_file())
            .unwrap_or(false)
    })
}

#[derive(Debug)]
pub enum Failure {
    /// The executable could not be started (missing, permission denied, …).
    Spawn,
    /// `try_wait` failed; the child has been killed and reaped.
    Wait,
    /// SIGTERM/SIGINT arrived; the child has already been killed and reaped.
    Interrupted(i32),
}

pub struct Counted {
    pub status: ExitStatus,
    pub newlines: u64,
}

pub struct Captured {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
}

/// Run a command and count newline bytes on its stdout, like `wc -l`.
pub fn count(program: &str, arguments: &[&OsStr], signals: &Signals) -> Result<Counted, Failure> {
    if let Some(signal) = signals.pending() {
        return Err(Failure::Interrupted(signal));
    }
    let mut child = spawn(program, arguments)?;
    let Some(stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return Err(Failure::Wait);
    };
    let counter = Arc::new(AtomicU64::new(0));
    let reader_counter = Arc::clone(&counter);
    let reader = thread::spawn(move || {
        let mut stdout = stdout;
        let mut buffer = vec![0u8; 64 * 1024];
        loop {
            match stdout.read(&mut buffer) {
                Ok(0) => break,
                Ok(read) => {
                    let newlines =
                        buffer[..read].iter().filter(|byte| **byte == b'\n').count() as u64;
                    reader_counter.fetch_add(newlines, Ordering::Relaxed);
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    });
    let status = wait_for(&mut child, signals);
    let _ = reader.join();
    Ok(Counted {
        status: status?,
        newlines: counter.load(Ordering::Relaxed),
    })
}

/// Run a command and keep its whole stdout (the `journalctl -o json` stream).
pub fn capture(
    program: &str,
    arguments: &[&OsStr],
    signals: &Signals,
) -> Result<Captured, Failure> {
    if let Some(signal) = signals.pending() {
        return Err(Failure::Interrupted(signal));
    }
    let mut child = spawn(program, arguments)?;
    let Some(mut stdout) = child.stdout.take() else {
        let _ = child.kill();
        let _ = child.wait();
        return Err(Failure::Wait);
    };
    let reader = thread::spawn(move || {
        let mut stdout_data = Vec::new();
        let _ = stdout.read_to_end(&mut stdout_data);
        stdout_data
    });
    let status = wait_for(&mut child, signals);
    let stdout = reader.join().unwrap_or_default();
    Ok(Captured {
        status: status?,
        stdout,
    })
}

fn spawn(program: &str, arguments: &[&OsStr]) -> Result<Child, Failure> {
    Command::new(program)
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| Failure::Spawn)
}

fn wait_for(child: &mut Child, signals: &Signals) -> Result<ExitStatus, Failure> {
    loop {
        if let Some(signal) = signals.pending() {
            let _ = child.kill();
            let _ = child.wait();
            return Err(Failure::Interrupted(signal));
        }
        match child.try_wait() {
            Ok(Some(status)) => return Ok(status),
            Ok(None) => thread::sleep(POLL),
            Err(_) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(Failure::Wait);
            }
        }
    }
}
