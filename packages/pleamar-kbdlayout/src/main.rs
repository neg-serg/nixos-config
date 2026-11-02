//! `pleamar-kbdlayout` — the keyboard-layout worker for pleamar.
//!
//! A behaviour-preserving port of `files/pleamar/scripts/helpers/kbd.sh`:
//! the same CLI (`--once`, `--socket`, `--interval-ms`, `switch`), the same §7
//! JSON-lines protocol, the same `hyprctl` queries and the same lifecycle —
//! the `layout` topic auto-subscribed at the heartbeat cadence, `.socket2.sock`
//! events coalesced into one changed sample, a 50 ms stdin poll, closed stdin
//! finishes and SIGTERM/SIGINT clean up and exit 0.

#![forbid(unsafe_code)]

mod caps;
mod cli;
mod hypr;
mod protocol;
mod sample;
mod socket;

use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use protocol::{Control, Session};

/// The shell polled stdin with `read -t 0.05`; one command per iteration.
const STDIN_POLL: Duration = Duration::from_millis(50);

fn main() -> ExitCode {
    let arguments: Vec<std::ffi::OsString> = std::env::args_os().skip(1).collect();
    match cli::parse(arguments) {
        cli::ParseResult::Help => {
            print!("{}", cli::USAGE);
            let _ = io::stdout().flush();
            ExitCode::SUCCESS
        }
        cli::ParseResult::Error(message) => {
            eprintln!("kbd: error: {message}");
            ExitCode::from(2)
        }
        cli::ParseResult::Run(options) => run(options),
    }
}

enum Input {
    Line(String),
    Closed,
}

fn run(options: cli::Options) -> ExitCode {
    let hyprctl = program("PLEAMAR_HYPRCTL", "hyprctl");
    if !hypr::is_executable(&hyprctl) {
        // The shell's `start_error`: the protocol shape, no handshake, exit 1.
        let mut out = io::stdout().lock();
        let _ = protocol::write_start_error("hyprctl not found", &mut out);
        return ExitCode::from(1);
    }

    // The shell installed `trap 'cleanup; exit 0' INT TERM` before the
    // handshake; the flags are checked by the event loop.
    let terminate = Arc::new(AtomicBool::new(false));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGTERM, Arc::clone(&terminate));
    let _ = signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&terminate));

    let stdout = io::stdout();
    let mut out = stdout.lock();
    let hyprctl = hypr::Hyprctl { program: hyprctl };
    let mut session = Session::new(hyprctl, options.interval_ms, PathBuf::from(caps::LED_ROOT));

    if protocol::write_line(&mut out, protocol::HANDSHAKE).is_err() {
        return ExitCode::SUCCESS;
    }

    if let cli::Invocation::Switch(arguments) = &options.invocation {
        let mut command = String::from("switch");
        for argument in arguments {
            command.push(' ');
            command.push_str(argument);
        }
        let _ = session.handle_line(&command, &mut out);
        return ExitCode::SUCCESS;
    }

    if options.once {
        let _ = session.emit_sample(&mut out);
        return ExitCode::SUCCESS;
    }

    let mut events =
        socket::EventSocket::new(options.socket.clone(), program("PLEAMAR_SOCAT", "socat"));
    if let Some(message) = events.start() {
        let _ = protocol::write_error_sample(message, &mut out);
    }

    // Reading stdin on a thread is what lets the loop poll a line, the event
    // channel and the signals on the shell's 50 ms grid.
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let stdin = io::stdin();
        let mut reader = stdin.lock();
        let mut buffer = Vec::new();
        loop {
            buffer.clear();
            match reader.read_until(b'\n', &mut buffer) {
                Ok(0) => break,
                Ok(_) => {
                    // `read -r` drops the delimiter and reports failure for a
                    // final line without one; the shell treats that as EOF
                    // and discards the partial line.
                    if buffer.last() != Some(&b'\n') {
                        break;
                    }
                    buffer.pop();
                    let line = String::from_utf8_lossy(&buffer).into_owned();
                    if sender.send(Input::Line(line)).is_err() {
                        return;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        let _ = sender.send(Input::Closed);
    });

    loop {
        if terminate.load(Ordering::Relaxed) {
            break;
        }
        let action = match receiver.recv_timeout(STDIN_POLL) {
            Ok(Input::Line(line)) => {
                if line.is_empty() {
                    None
                } else {
                    Some(session.handle_line(&line, &mut out))
                }
            }
            // End of stdin: the scene closed the command pipe; finish, never
            // outlive it.
            Ok(Input::Closed) => break,
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => break,
        };
        if let Some(result) = action {
            match result {
                Ok(Control::Continue) => {}
                Ok(Control::Stop) => break,
                Err(_) => break,
            }
        }
        match events.drain() {
            socket::Drain::Closed => {
                if protocol::write_error_sample(socket::SOCKET_CLOSED, &mut out).is_err() {
                    break;
                }
            }
            socket::Drain::Events(lines) => {
                if lines.iter().any(|line| socket::matches_event(line))
                    && session.emit_changed_sample(&mut out).is_err()
                {
                    break;
                }
            }
            socket::Drain::Idle => {}
        }
        if session
            .emit_due_samples(protocol::now_ms(), &mut out)
            .is_err()
        {
            break;
        }
    }

    events.cleanup();
    ExitCode::SUCCESS
}

/// `${PLEAMAR_HYPRCTL:-hyprctl}` and `${PLEAMAR_SOCAT:-socat}`: an empty value
/// means "use the default", like the shell's `:-`.
fn program(variable: &str, fallback: &str) -> String {
    match std::env::var(variable) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}
