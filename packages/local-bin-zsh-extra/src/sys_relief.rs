//! Rust port of `packages/local-bin/bin/sys-relief`.
//!
//! Flushes dirty pages, drops the caches, lowers swap/IO pressure through
//! `sudo sysctl`, then leaves a detached copy of itself that sleeps 300
//! seconds, restores the normal sysctl values and sends the second
//! notification. The original's `{ ... } &!` subshell becomes a re-exec with
//! LOCAL_BIN_ZSH_EXTRA_RESTORE set: the child is reparented, so the foreground
//! script still exits immediately.
//!
//! Commands under `set -e` propagate their status; `|| true` commands keep the
//! original's stderr redirection. sysctl/sudo/sync/sleep/notify-send stay
//! subprocesses with the original argv.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::process::{Command, Stdio};

use local_bin_zsh_extra::{report_spawn_failure, run, run_ignored, StdioMode};

const RESTORE_MARKER: &str = "LOCAL_BIN_ZSH_EXTRA_RESTORE";

fn main() {
    if std::env::var_os(RESTORE_MARKER).is_some() {
        restore();
        return;
    }

    notify(&["-u", "low", "Relief...", "Syncing dirty pages..."]);
    checked(&site(14), "sync", &[]);
    checked(&site(17), "sudo", &["sysctl", "-w", "vm.drop_caches=3"]);
    // 2>/dev/null || true
    run_ignored(
        &site(20),
        "sudo",
        &os_args(&["sysctl", "-w", "vm.compact_memory=1"]),
        StdioMode::Null,
    );
    checked(&site(23), "sudo", &["sysctl", "-w", "vm.swappiness=1"]);
    checked(
        &site(24),
        "sudo",
        &["sysctl", "-w", "vm.dirty_background_bytes=16777216"],
    );
    checked(
        &site(25),
        "sudo",
        &["sysctl", "-w", "vm.dirty_bytes=67108864"],
    );

    notify(&[
        "Relief applied",
        "Caches dropped, IO reduced.\\nRestoring in 5 min.",
    ]);

    spawn_restore_child();
}

/// zsh's script diagnostic prefix: the invocation path and the source line.
fn site(line: u32) -> String {
    let argv0 = std::env::args_os().next().unwrap_or_default();
    format!("{}:{line}", argv0.to_string_lossy())
}

fn restore() {
    checked(&site(31), "sleep", &["300"]);
    checked(
        &site(32),
        "sudo",
        &[
            "sysctl",
            "-w",
            "vm.swappiness=10",
            "vm.dirty_background_bytes=67108864",
            "vm.dirty_bytes=268435456",
        ],
    );
    notify(&["-u", "low", "Relief", "Sysctl restored to normal."]);
}

fn os_args(arguments: &[&str]) -> Vec<OsString> {
    arguments.iter().map(OsString::from).collect()
}

fn notify(arguments: &[&str]) {
    let mut argv = vec![OsString::from("-a"), OsString::from("sys-relief")];
    argv.extend(arguments.iter().map(OsString::from));
    run_ignored(&site(9), "notify-send", &argv, StdioMode::Null);
}

fn checked(site: &str, tool: &str, arguments: &[&str]) {
    let status = match run(
        tool,
        &os_args(arguments),
        StdioMode::Inherit,
        StdioMode::Inherit,
    ) {
        Ok(status) => status,
        Err(error) => report_spawn_failure(site, tool, &error, StdioMode::Inherit),
    };
    if status != 0 {
        std::process::exit(status);
    }
}

fn spawn_restore_child() {
    let executable = match std::env::current_exe() {
        Ok(executable) => executable,
        Err(_) => return,
    };
    let _ = Command::new(executable)
        .env(RESTORE_MARKER, "1")
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn();
}
