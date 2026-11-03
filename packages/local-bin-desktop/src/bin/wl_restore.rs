//! Rust port of `packages/local-bin/bin/wl-restore`.
//!
//! Restores the wallpaper through `wl`, validating the saved state first: a
//! state that names a deleted image makes `wl restore` exit 0 having painted
//! nothing, so the port checks the file itself and falls back to the greeter's
//! resolver or a random pick. `systemctl`, `wl`, `sleep` and the resolver stay
//! subprocesses; the state JSON and the greeter cache copy are native.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;
use std::path::Path;

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
        // The state is stale or there is no previous session: ask the same
        // resolver the login layer uses.
        let resolver = b"/etc/quickshell/scripts/wl-wallpaper-resolve.sh";
        let mut candidate = Cmd::from_bytes(resolver)
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .run();
        candidate.stdout = text::strip_trailing_newlines(&candidate.stdout).to_vec();
        if !candidate.stdout.is_empty() {
            let apply = Cmd::new("wl")
                .arg("img")
                .arg_bytes(&candidate.stdout)
                .stderr(Sink::Null)
                .run();
            if apply.code != 0 {
                random_wallpaper(&program, 31);
            }
        } else {
            random_wallpaper(&program, 33);
        }
    }

    // Sync the current wallpaper to the greeter cache for smooth transitions.
    let mut notify_file = env::var_or_empty("HOME");
    notify_file.extend_from_slice(b"/.cache/quickshell-wallpaper-path");
    if Path::new(std::ffi::OsStr::from_bytes(&notify_file)).is_file() {
        if let Ok(contents) = std::fs::read(std::ffi::OsStr::from_bytes(&notify_file)) {
            let wallpaper = text::first_line(&contents).to_vec();
            if !wallpaper.is_empty() && Path::new(std::ffi::OsStr::from_bytes(&wallpaper)).is_file()
            {
                let target = Path::new("/home/greeter/.cache/greeter-wallpaper");
                if let Some(parent) = target.parent() {
                    let _ = std::fs::create_dir_all(parent);
                }
                let _ = copy_file_with_mode(
                    Path::new(std::ffi::OsStr::from_bytes(&wallpaper)),
                    target,
                    0o644,
                );
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

fn copy_file_with_mode(source: &Path, target: &Path, mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let contents = std::fs::read(source)?;
    std::fs::write(target, contents)?;
    std::fs::set_permissions(target, std::fs::Permissions::from_mode(mode))?;
    Ok(())
}
