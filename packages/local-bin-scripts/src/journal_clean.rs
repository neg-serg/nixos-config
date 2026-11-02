//! Rust port of `packages/local-bin/scripts/journal-clean.sh`.
//!
//! Only two things happen without root: the user journal is vacuumed (when
//! journalctl allows it) and Hyprland's runtime log is truncated. The script's
//! own messages, the "insufficient permission" fallback and the `--user`
//! arguments passed to journalctl are preserved byte for byte.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs::OpenOptions;
use std::os::unix::ffi::OsStrExt;
use std::process::{Command, Stdio};

use local_bin_scripts::env;

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv
        .next()
        .unwrap_or_else(|| OsString::from("journal-clean"));
    let program = env::invocation_name(&argv0);
    let mut args = argv;
    let keep_window = args
        .next()
        .map(|arg| arg.as_bytes().to_vec())
        .filter(|arg| !arg.is_empty())
        .unwrap_or_else(|| b"1d".to_vec());

    if env::find_in_path(b"journalctl").is_some() {
        env::out_str("== journalctl --user disk usage (before) ==\n");

        let mut usage = Command::new("journalctl");
        usage
            .arg("--user")
            .arg("--disk-usage")
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        let _ = usage.status();

        let mut vacuum_arg = Vec::from(&b"--vacuum-time="[..]);
        vacuum_arg.extend_from_slice(&keep_window);
        let mut vacuum = Command::new("journalctl");
        vacuum
            .arg("--user")
            .arg(std::ffi::OsStr::from_bytes(&vacuum_arg))
            .stdin(Stdio::inherit())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let vacuumed = vacuum
            .status()
            .map(|status| status.success())
            .unwrap_or(false);
        if vacuumed {
            let mut message = Vec::from(&b"Vacuumed user journal to keep "[..]);
            message.extend_from_slice(&keep_window);
            message.push(b'\n');
            env::out(&message);
        } else {
            env::err_str(
                "Skipping vacuum: insufficient permission to remove system journal files (needs root)\n",
            );
        }

        env::out_str("== journalctl --user disk usage (after) ==\n");
        let mut usage = Command::new("journalctl");
        usage
            .arg("--user")
            .arg("--disk-usage")
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit());
        let _ = usage.status();
    } else {
        env::err_str("journalctl not available; skipping journal vacuum\n");
    }

    if let (Some(runtime_dir), Some(signature)) = (
        env::var_nonempty("XDG_RUNTIME_DIR"),
        env::var_nonempty("HYPRLAND_INSTANCE_SIGNATURE"),
    ) {
        let mut hypr_log = runtime_dir;
        hypr_log.extend_from_slice(b"/hypr/");
        hypr_log.extend_from_slice(&signature);
        hypr_log.extend_from_slice(b"/hyprland.log");

        let path = std::ffi::OsStr::from_bytes(&hypr_log);
        let is_regular_file = std::fs::metadata(path)
            .map(|metadata| metadata.is_file())
            .unwrap_or(false);
        if is_regular_file {
            match OpenOptions::new().write(true).truncate(true).open(path) {
                Ok(_) => {
                    let mut message = Vec::from(&b"Truncated Hyprland log: "[..]);
                    message.extend_from_slice(&hypr_log);
                    message.push(b'\n');
                    env::out(&message);
                }
                Err(error) => {
                    // `: > file` failing under `set -e`: bash prints the
                    // redirection diagnostic and leaves with status 1.
                    let mut message = program.clone();
                    message.extend_from_slice(b": line 29: ");
                    message.extend_from_slice(&hypr_log);
                    message.extend_from_slice(b": ");
                    message.extend_from_slice(env::os_error_text(&error).as_bytes());
                    message.push(b'\n');
                    env::err(&message);
                    std::process::exit(1);
                }
            }
        }
    }

    env::out_str("Done.\n");
}
