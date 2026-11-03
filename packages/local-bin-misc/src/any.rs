//! Rust port of `packages/local-bin/bin/any`.
//!
//! `pgrep -f -- "$@"` is still spawned; joining the PIDs (`paste -sd,`) and the
//! "no matches" decision are native. The final `ps` is exec'd exactly like the
//! original, so its status and streams are the script's.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

use local_bin_misc::{err_line, exec_failure, invocation_name, need, prog_name, raw_args};

fn is_help(argument: Option<&OsString>) -> bool {
    match argument {
        Some(value) => matches!(value.as_bytes(), b"-h" | b"--help" | b"help" | b"?"),
        None => false,
    }
}

fn usage() -> ! {
    err_line(b"Usage: any [PGREP_OPTS...] PATTERN");
    std::process::exit(1);
}

/// `$( )` strips every trailing newline, nothing else.
fn trim_trailing_newlines(bytes: &[u8]) -> &[u8] {
    let mut end = bytes.len();
    while end > 0 && bytes[end - 1] == b'\n' {
        end -= 1;
    }
    &bytes[..end]
}

/// `printf '%s' "$pids" | paste -sd, -`: every line break becomes a comma.
fn paste_lines(pids: &[u8]) -> OsString {
    let mut list = Vec::with_capacity(pids.len());
    for byte in pids {
        match byte {
            b'\n' => list.push(b','),
            other => list.push(*other),
        }
    }
    OsString::from_vec(list)
}

fn main() {
    let arguments = raw_args();
    if is_help(arguments.first()) {
        usage();
    }

    let program = prog_name();
    need(&program, "pgrep");
    need(&program, "ps");

    // `pids="$(pgrep -f -- "$@" 2>/dev/null || true)"`: stderr is discarded,
    // a missing pgrep behaves like an empty match list.
    let pids = {
        let mut command = Command::new("pgrep");
        command
            .arg("-f")
            .arg("--")
            .args(&arguments)
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        match command.spawn() {
            Ok(child) => child.wait_with_output().map(|output| output.stdout),
            Err(_) => Ok(Vec::new()),
        }
        .unwrap_or_default()
    };

    // Bash drops NUL bytes from command substitution output; a shell
    // variable cannot carry them anyway.
    let pids: Vec<u8> = pids.into_iter().filter(|byte| *byte != 0).collect();
    let pids = trim_trailing_newlines(&pids);
    if pids.is_empty() {
        err_line(b"any: no matches");
        std::process::exit(1);
    }

    // `exec ps uwww -p "$list"`.
    let error = Command::new("ps")
        .arg("uwww")
        .arg("-p")
        .arg(paste_lines(pids))
        .exec();
    exec_failure(&invocation_name(), 28, "ps", &error);
}
