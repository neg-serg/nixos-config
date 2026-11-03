//! Rust port of `packages/local-bin/bin/wl-restore`.
//!
//! Restores the wallpaper through `wl`, validating the saved state first: a
//! state that names a deleted image makes `wl restore` exit 0 having painted
//! nothing, so the port checks the file itself and falls back to the first path
//! still on disk or a random pick. `systemctl`, `wl` and `sleep` stay
//! subprocesses; the state JSON is read natively.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;

use local_bin_desktop::env;
use local_bin_desktop::json::Json;
use local_bin_desktop::proc::{Cmd, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let _ = arguments;

    // The daemon must be owned by systemd; the unit start is best effort.
    let _ = Cmd::new("systemctl")
        .args(["--user", "start", "wl-daemon.service"])
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .run();

    // Wait for the daemon's IPC socket (the unit start is effectively async).
    let mut attempt = 0;
    while attempt < 10 {
        let probe = Cmd::new("wl")
            .arg("query")
            .stdout(Sink::Null)
            .stderr(Sink::Null)
            .run();
        if probe.code == 0 {
            break;
        }
        let pause = Cmd::new("sleep").arg("0.5").diag(&program, 17).run();
        if pause.code != 0 {
            std::process::exit(pause.code);
        }
        attempt += 1;
    }

    let mut state_file = env::var_or_empty("HOME");
    state_file.extend_from_slice(b"/.local/state/wl/state.json");
    let current = read_wallpaper_path(&state_file);

    if !current.is_empty() && readable(&current) {
        // `wl restore 2> /dev/null`: stdout stays visible.
        let restore = Cmd::new("wl").arg("restore").stderr(Sink::Null).run();
        if restore.code != 0 {
            random_wallpaper(&program, 24);
        }
    } else {
        // The state is stale or there is no previous session: take the first path
        // that is still on disk, the same ladder `wl-restore-retry` (the daemon's
        // ExecStartPost) walks — wl's own last-good, the producer cache the theme and
        // the login layer read (INTERFACES.md §1.2), then the old "current wallpaper"
        // link.
        //
        // It used to ask `/etc/quickshell/scripts/wl-wallpaper-resolve.sh`, the
        // resolver of the shell deleted on 2026-11-02: that path has not existed
        // since, so this branch fell straight through to a random pick and the
        // "same wallpaper as last time" this tool exists for never came back.
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
            random_wallpaper(&program, 33);
        } else {
            let apply = Cmd::new("wl")
                .arg("img")
                .arg_bytes(&candidate)
                .stderr(Sink::Null)
                .run();
            if apply.code != 0 {
                random_wallpaper(&program, 31);
            }
        }
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
        Some(path) => path.raw_or_empty(),
        None => Vec::new(),
    }
}

/// `[ -r PATH ]`: the file can actually be opened for reading.
fn readable(path: &[u8]) -> bool {
    std::fs::File::open(std::ffi::OsStr::from_bytes(path)).is_ok()
}

/// `wl random ~/pic/wl`; the last command's failure is fatal under `set -e`.
fn random_wallpaper(program: &[u8], line: u32) {
    let mut directory = env::var_or_empty("HOME");
    directory.extend_from_slice(b"/pic/wl");
    let outcome = Cmd::new("wl")
        .arg("random")
        .arg_bytes(&directory)
        .diag(program, line)
        .run();
    if outcome.code != 0 {
        std::process::exit(outcome.code);
    }
}
