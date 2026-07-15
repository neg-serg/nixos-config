//! Gamemode integration.
//!
//! Optionally wraps a command with `gamemoderun` for automatic
//! CPU governor, GPU performance level, and I/O priority tuning.

use std::process::Command;

/// Check if gamemoderun is available on PATH.
pub fn is_available() -> bool {
    which("gamemoderun").is_some()
}

/// Wrap a command with gamemoderun if available.
pub fn wrap_command(args: &[String]) -> Command {
    let mut cmd = Command::new("gamemoderun");
    if let Some(first) = args.first() {
        cmd.arg(first);
    }
    if args.len() > 1 {
        cmd.args(&args[1..]);
    }
    cmd
}

/// Build a command that may or may not be wrapped with gamemoderun.
pub fn maybe_wrap(args: &[String], enabled: bool) -> Command {
    if enabled && is_available() {
        wrap_command(args)
    } else {
        let mut cmd = Command::new(args.first().map(|s| s.as_str()).unwrap_or(""));
        if args.len() > 1 {
            cmd.args(&args[1..]);
        }
        cmd
    }
}

fn which(name: &str) -> Option<std::path::PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        for dir in std::env::split_paths(&paths) {
            let full = dir.join(name);
            if full.is_file() {
                return Some(full);
            }
        }
        None
    })
}

/// Human-readable gamemode status.
pub fn describe() -> String {
    if is_available() {
        "gamemoderun: available".to_string()
    } else {
        "gamemoderun: not found on PATH".to_string()
    }
}
