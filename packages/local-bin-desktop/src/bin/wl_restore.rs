//! Rust port of `packages/local-bin/bin/wl-restore`.
//!
//! Restores the wallpaper through `wl` on Hyprland start. The saved state is
//! validated first: a state that names a deleted image makes `wl restore` exit 0
//! having painted nothing, so the port checks the file itself and falls back to
//! the first path that is still on disk. `systemctl`, `wl` and `sleep` stay
//! subprocesses; the state JSON is read natively.
//!
//! The port never picks a wallpaper of its own. The shell original ended in
//! `wl random ~/pic/wl` whenever the restore did not go through, and after a
//! compositor crash that is exactly the path taken: this tool runs from the
//! session-start hook while wl-daemon is still coming up, `wl restore` loses the
//! race, and the desktop returned on a random picture instead of the one that was
//! on screen. A failed restore is retried here and then repainted from the state
//! itself; a state that cannot be trusted walks the same fallback ladder as
//! `wl-restore-retry`, the daemon's ExecStartPost (wl's last-good, the producer
//! cache, the legacy link). When nothing usable is on disk, nothing is painted.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;

use crate::env;
use crate::json::Json;
use crate::proc::{Cmd, Sink};
use crate::text;

/// `wl restore` attempts before the saved file is painted directly. The daemon
/// answers `query` before its own auto-restore is done (~0.4 s), so the first
/// commands after a compositor restart can be refused.
const RESTORE_ATTEMPTS: u32 = 5;
/// Pause between those attempts.
const RETRY_PAUSE: &str = "0.3";

pub fn entry() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name_of(&argv0);
    let _ = arguments;

    // The daemon must be owned by systemd; the unit start is best effort.
    let _ = Cmd::new("systemctl")
        .args(["--user", "start", "wl-daemon.service"])
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .run();

    // Wait for the daemon's IPC socket (the unit start is effectively async).
    wait_for_daemon(&program);

    let mut state_file = env::var_or_empty("HOME");
    state_file.extend_from_slice(b"/.local/state/wl/state.json");
    let current = read_wallpaper_path(&state_file);

    if !current.is_empty() && readable(&current) {
        for _ in 0..RESTORE_ATTEMPTS {
            // `wl restore 2> /dev/null`: stdout stays visible.
            let restore = Cmd::new("wl").arg("restore").stderr(Sink::Null).run();
            if restore.code == 0 {
                return;
            }
            let _ = Cmd::new("sleep").arg(RETRY_PAUSE).run();
        }
        // The daemon kept refusing the command: paint the very file the state
        // names, so the desktop still comes back on the user's wallpaper.
        exit_on_failure(apply(&program, &current));
    }

    // The state names a file that is not there: restoring it would leave the
    // screen empty. Ask the files the rest of the stack already writes what is
    // actually on disk and apply that: wl's own last-good, the picker's
    // canonical cache, then the legacy "current wallpaper" link. (The old
    // /etc/quickshell/scripts/wl-wallpaper-resolve.sh went away with the shell it
    // belonged to, on 2026-11-02.)
    let mut candidate: Vec<u8> = Vec::new();
    for relative in [
        ".local/state/wl/last-good",
        ".cache/pleamar/wallpaper-path",
        ".cache/current_wallpaper_source",
    ] {
        let mut path = env::var_or_empty("HOME");
        path.push(b'/');
        path.extend_from_slice(relative.as_bytes());
        let Ok(contents) = std::fs::read(std::ffi::OsStr::from_bytes(&path)) else {
            continue;
        };
        let first = text::first_line(&contents).to_vec();
        if !first.is_empty() && readable(&first) {
            candidate = first;
            break;
        }
    }
    if candidate.is_empty() {
        // Nothing on disk can be restored. Leave the screen alone: the daemon's
        // own restore still paints the previous wallpaper, and a random pick
        // must never replace what the user chose.
        return;
    }
    exit_on_failure(apply(&program, &candidate));
}

fn wait_for_daemon(program: &[u8]) {
    let mut attempt = 0;
    while attempt < 10 {
        let probe = Cmd::new("wl")
            .arg("query")
            .stdout(Sink::Null)
            .stderr(Sink::Null)
            .run();
        if probe.code == 0 {
            return;
        }
        let pause = Cmd::new("sleep").arg("0.5").diag(program, 17).run();
        if pause.code != 0 {
            std::process::exit(pause.code);
        }
        attempt += 1;
    }
}

/// `wl img PATH`; the shell original was fatal here under `set -e`, so the exit
/// status is kept — but the path is always one the stack already recorded, never
/// a random pick.
fn apply(program: &[u8], path: &[u8]) -> i32 {
    Cmd::new("wl")
        .arg("img")
        .arg_bytes(path)
        .stderr(Sink::Null)
        .diag(program, 62)
        .run()
        .code
}

fn exit_on_failure(code: i32) {
    if code != 0 {
        std::process::exit(code);
    }
}

/// `jq -r '.outputs | to_entries | .[0].value.wallpaper_path // empty'`.
fn read_wallpaper_path(state_file: &[u8]) -> Vec<u8> {
    let contents = match std::fs::read(std::ffi::OsStr::from_bytes(state_file)) {
        Ok(contents) => contents,
        Err(_) => return Vec::new(),
    };
    let value = match Json::parse(&contents) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };
    let outputs = match value.get("outputs") {
        Some(Json::Obj(fields)) => fields,
        _ => return Vec::new(),
    };
    let Some((_, first)) = outputs.first() else {
        return Vec::new();
    };
    match first.get("wallpaper_path") {
        Some(path) => path.raw_or_empty().into_bytes(),
        None => Vec::new(),
    }
}

/// `[ -r PATH ]`: the file can actually be opened for reading.
fn readable(path: &[u8]) -> bool {
    std::fs::File::open(std::ffi::OsStr::from_bytes(path)).is_ok()
}
