//! `pleamar-picker [toggle|open|close|reload|current]` — the wallpaper deck's
//! command line, ported from `files/pleamar/scripts/helpers/picker-toggle.sh`.
//!
//! - `toggle` opens the deck, or closes it when it is open (the compositor
//!   bind's verb);
//! - `open` opens it, starting the scene if it is not running;
//! - `close` closes it (nothing happens when it is not running);
//! - `reload` reads the wallpaper folder again;
//! - `current` prints the wallpaper set last, the file the theme pipeline
//!   reads.
//!
//! The scene is an on-demand unit, so a fresh session has no picker process:
//! the first verb that needs it starts the unit and waits for its socket, and
//! every later one is a single `pleamar --say`. A running deck answers through
//! `get open`, one word (`true`/`false`, empty when the scene does not
//! answer); `toggle` waits for that word to change before deciding whether to
//! stop the unit, exactly 20 times 0.1 s as the shell did. The start path
//! tries `emit open_picker` 30 times with the same step.
//!
//! Environment: `PLEAMAR` and `SYSTEMCTL` override the programs, as in the
//! shell; otherwise they come from PATH with the same
//! `/run/current-system/sw/bin/...` fallback.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::process::{Command, Stdio};

use crate::{env, proc, text};

/// The on-demand scene unit.
const SERVICE: &str = "pleamar-picker.service";
const FALLBACK_PLEAMAR: &str = "/run/current-system/sw/bin/pleamar";
const FALLBACK_SYSTEMCTL: &str = "/run/current-system/sw/bin/systemctl";
const POLL_STEPS: usize = 20;
const START_STEPS: usize = 30;

pub fn run() -> i32 {
    let arguments: Vec<OsString> = std::env::args_os().collect();
    let pleamar = env::nonempty("PLEAMAR")
        .or_else(|| proc::command_v("pleamar").map(|path| path.into_os_string()))
        .unwrap_or_else(|| OsString::from(FALLBACK_PLEAMAR));
    let systemctl = env::nonempty("SYSTEMCTL")
        .or_else(|| proc::command_v("systemctl").map(|path| path.into_os_string()))
        .unwrap_or_else(|| OsString::from(FALLBACK_SYSTEMCTL));

    // `${1:-toggle}`: an absent or empty verb is the toggle.
    let verb = arguments
        .get(1)
        .filter(|argument| !argument.is_empty())
        .cloned()
        .unwrap_or_else(|| OsString::from("toggle"));

    match verb.as_bytes() {
        b"toggle" => {
            let was = deck_open(&pleamar);
            if say(&pleamar, "emit toggle_picker") {
                // The close runs through the scene's own animation, so the
                // fact flips a moment after `emit` returns: wait for the
                // value to change, then decide. A swallowed toggle changes
                // nothing, and then the unit stays up (the safe direction).
                for _ in 0..POLL_STEPS {
                    let now = deck_open(&pleamar);
                    if !now.is_empty() && now != was {
                        if now == b"false" {
                            let _ = systemctl_call(&systemctl, "stop");
                        }
                        return 0;
                    }
                    proc::sleep_01();
                }
                return 0;
            }
            // A dead deck swallowed nothing: start it below.
        }
        b"open" => {}
        b"close" => {
            let _ = say(&pleamar, "emit close_picker");
            // Nothing on screen means nothing to keep running.
            let _ = systemctl_call(&systemctl, "stop");
            return 0;
        }
        b"reload" => {
            let _ = say(&pleamar, "emit reload");
            return 0;
        }
        b"current" => {
            return current();
        }
        _ => {
            text::write_stderr(&[b"usage: pleamar-picker [toggle|open|close|reload|current]\n"]);
            return 2;
        }
    }

    // Not running yet: start the unit and wait for the socket to answer (a
    // scene takes a moment to come up, and its first frame longer).
    if !systemctl_call(&systemctl, "start") {
        return 1;
    }
    for _ in 0..START_STEPS {
        if say(&pleamar, "emit open_picker") {
            return 0;
        }
        proc::sleep_01();
    }

    text::write_stderr(&[b"pleamar-picker: the wallpaper deck did not come up\n"]);
    1
}

/// `say() { "$PLEAMAR" --say picker "$1" >/dev/null 2>&1; }`.
fn say(pleamar: &OsStr, message: &str) -> bool {
    Command::new(pleamar)
        .arg("--say")
        .arg("picker")
        .arg(message)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// `deck_open() { "$PLEAMAR" --say picker "get open" 2>/dev/null | tail -n 1; }`
/// — the pipeline stays a pipeline: pleamar's stdout is tail's stdin, and a
/// failed pleamar leaves tail with an empty stream (so the answer is empty).
fn deck_open(pleamar: &OsStr) -> Vec<u8> {
    let mut child = Command::new(pleamar)
        .args(["--say", "picker", "get open"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok();
    let stdin = match child.as_mut() {
        Some(child) => match child.stdout.take() {
            Some(stdout) => Stdio::from(stdout),
            None => Stdio::null(),
        },
        None => Stdio::null(),
    };
    let tail = Command::new("tail")
        .arg("-n")
        .arg("1")
        .stdin(stdin)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    if let Some(mut child) = child {
        let _ = child.wait();
    }
    match tail {
        Ok(output) => text::trim_trailing_newlines(&output.stdout).to_vec(),
        Err(_) => Vec::new(),
    }
}

/// `"$SYSTEMCTL" --user <verb> pleamar-picker.service`, output inherited.
fn systemctl_call(program: &OsStr, verb: &str) -> bool {
    Command::new(program)
        .args(["--user", verb, SERVICE])
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// `cat "${XDG_CACHE_HOME:-$HOME/.cache}/pleamar/wallpaper-path" 2>/dev/null`;
/// a missing file is an empty answer and a zero exit, as before.
fn current() -> i32 {
    let Some(cache) = env::cache_required() else {
        return 1;
    };
    let path = cache.join("pleamar").join("wallpaper-path");
    if let Ok(mut file) = fs::File::open(path) {
        let stdout = io::stdout();
        let mut out = stdout.lock();
        let _ = io::copy(&mut file, &mut out);
        let _ = std::io::Write::flush(&mut out);
    }
    0
}
