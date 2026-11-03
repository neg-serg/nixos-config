//! Rust port of `packages/local-bin/bin/v`.
//!
//! Attached mode keeps the original order: optional `nvr` remote-open, then
//! `hyprctl dispatch focuswindow`, then the status line; helper failures are
//! reported and do not change the exit status. Fresh mode runs `rm -f` and
//! exec's `nvim --listen`, so the editor replaces the wrapper process.
//!
//! Two deliberate differences from the shell original:
//! - `. /etc/profile` is not evaluated. A compiled binary cannot source shell
//!   state, and in a normal user session the profile has already run in the
//!   parent shell (the nixos `set-environment` guard makes the source a no-op).
//! - `LOCAL_BIN_MISC_V_SOCKET` overrides the hard-coded `/tmp/nvim.sock`. It is
//!   a test seam so the tests never create or remove a socket at the host's
//!   live path; unset behaviour is identical to the original.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::os::unix::fs::FileTypeExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use local_bin_misc::{
    exec_failure, invocation_name, out_str, raw_args, report_spawn_failure, var_nonempty,
};

const DEFAULT_SOCKET: &str = "/tmp/nvim.sock";
const SOCKET_ENV: &str = "LOCAL_BIN_MISC_V_SOCKET";
const ATTACHED: &str = "\u{2197}  nvim (attached)\n";

fn socket_path() -> PathBuf {
    PathBuf::from(var_nonempty(SOCKET_ENV).unwrap_or_else(|| DEFAULT_SOCKET.into()))
}

/// `[ -S "$SOCKET" ] && nc -zU "$SOCKET" >/dev/null 2>&1`.
fn is_responsive_socket(path: &Path) -> bool {
    let is_socket = std::fs::metadata(path)
        .map(|meta| meta.file_type().is_socket())
        .unwrap_or(false);
    if !is_socket {
        return false;
    }
    Command::new("nc")
        .arg("-zU")
        .arg(path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn attached(socket: &Path, arguments: &[OsString]) {
    let invocation = invocation_name();
    if !arguments.is_empty() {
        let error = Command::new("nvr")
            .arg("--servername")
            .arg(socket)
            .arg("--remote-silent")
            .args(arguments)
            .status();
        if let Err(error) = error {
            report_spawn_failure(&invocation, 13, "nvr", &error);
        }
    }

    let error = Command::new("hyprctl")
        .args(["dispatch", "focuswindow", "class:nwim"])
        .stdout(Stdio::null())
        .status();
    if let Err(error) = error {
        report_spawn_failure(&invocation, 17, "hyprctl", &error);
    }

    out_str(ATTACHED);
}

fn start(socket: &Path, arguments: &[OsString]) {
    let invocation = invocation_name();
    if let Err(error) = Command::new("rm").arg("-f").arg(socket).status() {
        report_spawn_failure(&invocation, 21, "rm", &error);
    }
    let error = Command::new("nvim")
        .arg("--listen")
        .arg(socket)
        .args(arguments)
        .exec();
    exec_failure(&invocation, 23, "nvim", &error);
}

fn main() {
    // `export NVIM_APPNAME=` — an empty value, not an unset variable.
    std::env::set_var("NVIM_APPNAME", "");

    let arguments = raw_args();
    let socket = socket_path();
    if is_responsive_socket(&socket) {
        attached(&socket, &arguments);
    } else {
        start(&socket, &arguments);
    }
}
