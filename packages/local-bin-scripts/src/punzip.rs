//! Rust port of `packages/local-bin/scripts/punzip`.
//!
//! The shell wrapper only parses `[-d DIR] FILE.zip` and hands the archive to
//! `unzip`; `unzip` (and `mkdir`) stay subprocesses with the original argv.
//! `exec` is preserved through `CommandExt::exec`, so signals and the exit
//! status are the archive tool's own.

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::process::Command;

use local_bin_scripts::env;

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv.next().unwrap_or_else(|| OsString::from("punzip"));
    let program = env::invocation_name(&argv0);
    let args: Vec<OsString> = argv.collect();

    let mut index = 0usize;
    let mut destination: Option<Vec<u8>> = None;
    if args
        .first()
        .map(|arg| arg.as_bytes() == b"-d")
        .unwrap_or(false)
    {
        let dest = args
            .get(1)
            .map(|arg| arg.as_bytes().to_vec())
            .unwrap_or_default();
        if dest.is_empty() {
            env::err_str("punzip: missing DIR for -d\n");
            std::process::exit(2);
        }
        destination = Some(dest);
        index = 2;
    } else if args.is_empty() {
        env::err_str("punzip: missing FILE.zip\n");
        std::process::exit(2);
    }

    let Some(zipfile) = args.get(index) else {
        env::err_str("punzip: missing FILE.zip\n");
        std::process::exit(2);
    };
    if zipfile.is_empty() {
        env::err_str("punzip: missing FILE.zip\n");
        std::process::exit(2);
    }
    let zip_bytes = zipfile.as_bytes();
    if !(zip_bytes.ends_with(b".zip") || zip_bytes.ends_with(b".ZIP")) {
        let mut message = Vec::from(&b"punzip: not a zip: "[..]);
        message.extend_from_slice(zip_bytes);
        message.push(b'\n');
        env::err(&message);
        std::process::exit(2);
    }

    if let Some(dest) = &destination {
        let mut mkdir = Command::new("mkdir");
        mkdir
            .arg("-p")
            .arg("--")
            .arg(OsStr::from_bytes(dest))
            .stdin(std::process::Stdio::inherit())
            .stdout(std::process::Stdio::inherit())
            .stderr(std::process::Stdio::inherit());
        match mkdir.status() {
            Ok(status) => {
                if !status.success() {
                    std::process::exit(env::status_code(status));
                }
            }
            Err(_) => {
                env::command_not_found(&program, 19, b"mkdir");
                std::process::exit(127);
            }
        }
    }

    let mut unzip = Command::new("unzip");
    unzip.arg("-o").arg(OsStr::from_bytes(zip_bytes));
    let line = if let Some(dest) = &destination {
        unzip.arg("-d").arg(OsStr::from_bytes(dest));
        20
    } else {
        22
    };
    let error = unzip.exec();
    env::exec_failure(&program, line, b"unzip", &error);
}
