//! Rust port of `packages/local-bin/bin/pb`.
//!
//! The service table, curl argv, user-agent default, stdin redirection and the
//! `pb: no such file` warning are those of the shell original. Service
//! matching is the shell `case` glob list evaluated in order; the usage text is
//! a byte copy of the original heredoc (`src/pb_usage.txt`).

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::fs::File;
use std::os::unix::ffi::OsStrExt;
use std::process::{Command, Stdio};

use local_bin_misc::{
    err_line, invocation_name, need, out_str, prog_name, raw_args, redirect_failure, spawn_failure,
    status_code, var_nonempty,
};

const DEFAULT_UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.157 Safari/537.36";

const USAGE: &str = include_str!("pb_usage.txt");

#[derive(Clone, Copy)]
enum Service {
    Temp,
    Iotek,
    Uguu,
    Catbox,
}

fn is_help(argument: Option<&OsString>) -> bool {
    match argument {
        Some(value) => matches!(value.as_bytes(), b"-h" | b"--help" | b"help" | b"?"),
        None => false,
    }
}

/// The `case "$SERVICE"` table; patterns are matched in source order.
fn classify(service: &[u8]) -> Option<(Service, u32)> {
    if service == b"temp" || service == b"tmp" || service == b"temp.sh" {
        Some((Service::Temp, 63))
    } else if service == b"iotek"
        || service == b"iopaste"
        || service == b"p.iotek.org"
        || service.starts_with(b"iop")
    {
        Some((Service::Iotek, 65))
    } else if service == b"uguu" || service == b"uguu.se" || service.starts_with(b"u") {
        Some((Service::Uguu, 67))
    } else if service == b"catbox" || service == b"catbox.moe" || service.starts_with(b"cat") {
        Some((Service::Catbox, 69))
    } else {
        None
    }
}

fn push(argv: &mut Vec<OsString>, argument: &str) {
    argv.push(OsString::from(argument));
}

/// The exact curl argv of each case arm.
fn curl_argv(service: Service, user_agent: &OsStr) -> Vec<OsString> {
    let mut argv = Vec::new();
    push(&mut argv, "-fsS");
    push(&mut argv, "-A");
    argv.push(user_agent.to_os_string());
    match service {
        Service::Temp => {
            push(&mut argv, "-F");
            push(&mut argv, "file=@-");
            push(&mut argv, "https://temp.sh/upload");
        }
        Service::Iotek => {
            push(&mut argv, "-T");
            push(&mut argv, "-");
            push(&mut argv, "https://p.iotek.org");
        }
        Service::Uguu => {
            push(&mut argv, "-F");
            push(&mut argv, "files[]=@-");
            push(&mut argv, "https://uguu.se/upload?output=text");
        }
        Service::Catbox => {
            push(&mut argv, "-F");
            push(&mut argv, "reqtype=fileupload");
            push(&mut argv, "-F");
            push(&mut argv, "fileToUpload=@-");
            push(&mut argv, "https://catbox.moe/user/api.php");
        }
    }
    argv
}

fn main() {
    let arguments = raw_args();
    if is_help(arguments.first()) {
        out_str(USAGE);
        return;
    }

    let program = prog_name();
    need(&program, "curl");

    let service = arguments.first().cloned().unwrap_or_default();
    // ARG="${2:-/dev/stdin}" — an empty second argument is the default too.
    let arg = match arguments.get(1) {
        Some(value) if !value.is_empty() => value.clone(),
        _ => OsString::from("/dev/stdin"),
    };
    let user_agent = var_nonempty("UA").unwrap_or_else(|| OsString::from(DEFAULT_UA));

    // Accept '-' as stdin: the original skips the existence warning for it,
    // but still lets the shell open a file literally named '-' below.
    if arg.as_bytes() != b"/dev/stdin" && arg.as_bytes() != b"-" {
        let is_file = std::fs::metadata(&arg)
            .map(|meta| meta.is_file())
            .unwrap_or(false);
        if !is_file {
            let mut message = b"pb: no such file: ".to_vec();
            message.extend_from_slice(arg.as_bytes());
            err_line(&message);
        }
    }

    let Some((service, line)) = classify(service.as_bytes()) else {
        out_str(USAGE);
        return;
    };

    let stdin = match File::open(&arg) {
        Ok(file) => file,
        Err(error) => redirect_failure(&invocation_name(), line, &arg, &error),
    };

    let mut command = Command::new("curl");
    command
        .args(curl_argv(service, &user_agent))
        .stdin(Stdio::from(stdin));
    match command.status() {
        Ok(status) => std::process::exit(status_code(status)),
        Err(error) => spawn_failure(&invocation_name(), line, "curl", &error),
    }
}
