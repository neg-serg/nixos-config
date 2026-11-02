//! Rust port of `packages/local-bin/scripts/tty-log`.
//!
//! The script keeps the last ~200 KiB of a per-name log and then replaces
//! itself with `script -f [-c COMMAND] LOGFILE`. Both behaviours are preserved:
//! `tail`/`mv` are still the real commands (so their diagnostics are the same)
//! and `exec` hands the terminal to `script` unchanged.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs::File;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

use local_bin_scripts::env;
use local_bin_scripts::text;

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv.next().unwrap_or_else(|| OsString::from("tty-log"));
    let program = env::invocation_name(&argv0);
    let mut args: Vec<OsString> = argv.collect();

    if args.is_empty() || args[0].is_empty() {
        let mut message = program.clone();
        message.extend_from_slice(b": line 9: 1: Usage: tty-log <name> [command...]\n");
        env::err(&message);
        std::process::exit(1);
    }
    let name = args.remove(0);

    let Some(home) = env::var_os("HOME") else {
        let mut message = program.clone();
        message.extend_from_slice(b": line 11: HOME: unbound variable\n");
        env::err(&message);
        std::process::exit(1);
    };

    let mut log_dir = home.as_bytes().to_vec();
    log_dir.extend_from_slice(b"/.cache/quickshell/tty-logs");

    let mut mkdir = Command::new("mkdir");
    mkdir
        .arg("-p")
        .arg(std::ffi::OsStr::from_bytes(&log_dir))
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    match mkdir.status() {
        Ok(status) => {
            if !status.success() {
                std::process::exit(env::status_code(status));
            }
        }
        Err(_) => {
            env::command_not_found(&program, 12, b"mkdir");
            std::process::exit(127);
        }
    }

    let mut logfile = log_dir.clone();
    logfile.push(b'/');
    logfile.extend_from_slice(name.as_bytes());
    logfile.extend_from_slice(b".log");
    let mut tmp = logfile.clone();
    tmp.extend_from_slice(b".tmp");

    // `tail -c 204800 "$LOGFILE" 2>/dev/null > "$LOGFILE.tmp" && mv ...`:
    // the redirection happens even when the log does not exist yet, leaving
    // an empty .tmp behind on the first run. Keep that observable detail.
    match File::create(std::ffi::OsStr::from_bytes(&tmp)) {
        Ok(file) => {
            let mut tail = Command::new("tail");
            tail.arg("-c")
                .arg("204800")
                .arg(std::ffi::OsStr::from_bytes(&logfile))
                .stdin(Stdio::inherit())
                .stdout(Stdio::from(file))
                .stderr(Stdio::null());
            match tail.status() {
                Ok(status) if status.success() => {
                    let mut mv = Command::new("mv");
                    mv.arg(std::ffi::OsStr::from_bytes(&tmp))
                        .arg(std::ffi::OsStr::from_bytes(&logfile))
                        .stdin(Stdio::inherit())
                        .stdout(Stdio::inherit())
                        .stderr(Stdio::inherit());
                    match mv.status() {
                        Ok(_) => {}
                        Err(_) => env::command_not_found(&program, 16, b"mv"),
                    }
                }
                Ok(_) => {}
                // `2>/dev/null` covers the whole command, including bash's
                // "tail: command not found"; the `|| true` keeps going.
                Err(_) => {}
            }
        }
        Err(_) => {
            // The stderr redirection is applied before stdout is opened, so
            // bash's own "Is a directory" diagnostic goes to /dev/null too.
            // The `|| true` keeps the script going; `script` still runs.
        }
    }

    let mut script = Command::new("script");
    script.arg("-f");
    let line = if args.is_empty() {
        script.arg(std::ffi::OsStr::from_bytes(&logfile));
        21
    } else {
        let joined = text::join_args(
            &args
                .iter()
                .map(|arg| arg.as_bytes().to_vec())
                .collect::<Vec<_>>(),
        );
        script
            .arg("-c")
            .arg(OsString::from_vec(joined))
            .arg(std::ffi::OsStr::from_bytes(&logfile));
        19
    };
    script.stdin(Stdio::inherit());
    script.stdout(Stdio::inherit());
    script.stderr(Stdio::inherit());
    let error = script.exec();
    env::exec_failure(&program, line, b"script", &error);
}
