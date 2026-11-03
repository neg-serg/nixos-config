//! Rust port of `packages/local-bin/bin/pic-info`.
//!
//! Shows screenshot metadata by forwarding to `pic-notify` (`~/.local/bin`).
//! Without arguments it picks the newest file in `$PIC_INFO_DIR` (or
//! `$GRIM_DEFAULT_DIR`, else `$XDG_PICTURES_DIR/shots`). `pic-notify` stays a
//! subprocess; the directory scan, the mtime ordering and the `~` expansion are
//! native.

#![forbid(unsafe_code)]

use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_desktop::env;
use local_bin_desktop::helptext::PIC_INFO_USAGE;
use local_bin_desktop::proc::Cmd;
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let mut files: Vec<Vec<u8>> = arguments
        .map(|value| env::os_bytes(&value).to_vec())
        .collect();

    // The original resolves pic-notify before it looks at the arguments, so
    // `--help` also fails without it in PATH.
    let notify = match env::find_in_path(b"pic-notify") {
        Some(path) => env::os_bytes(path.as_os_str()).to_vec(),
        None => {
            env::err_str("pic-info: pic-notify not found in PATH\n");
            std::process::exit(1);
        }
    };

    if matches!(
        files.first().map(Vec::as_slice),
        Some(b"-h") | Some(b"--help")
    ) {
        env::out_str(PIC_INFO_USAGE);
        std::process::exit(0);
    }

    if files.is_empty() {
        let shots_dir = default_shots_dir();
        match pick_latest(&shots_dir) {
            Some(latest) => files.push(latest),
            None => {
                let mut message = b"pic-info: no screenshots found in ".to_vec();
                message.extend_from_slice(&shots_dir);
                message.push(b'\n');
                env::err(&message);
                std::process::exit(1);
            }
        }
    }

    let mut status = 0;
    for file in &files {
        let path = expand_path(file);
        if !Path::new(std::ffi::OsStr::from_bytes(&path)).exists() {
            let mut message = b"pic-info: skip missing ".to_vec();
            message.extend_from_slice(&path);
            message.push(b'\n');
            env::err(&message);
            status = 0;
            continue;
        }
        let outcome = Cmd::from_bytes(&notify)
            .arg_bytes(&path)
            .diag(&program, 75)
            .run();
        status = outcome.code;
    }
    std::process::exit(status);
}

/// `expand_path` as the shell spells it:
///
///     case "$1" in
///       "~")   printf '%s\n' "$HOME" ;;
///       "~/"*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
///
/// The `"~/"*` pattern is quoted, so it matches the literal two characters, but
/// the `#` pattern is *not* quoted: bash tilde-expands it to `$HOME/` before
/// matching. A literal `~/shot.png` therefore never matches the strip and comes
/// out as `$HOME/~/shot.png` — the original's behaviour, kept verbatim (only a
/// bare `~` is really expanded).
fn expand_path(path: &[u8]) -> Vec<u8> {
    let home = env::var_or_empty("HOME");
    if path == b"~" {
        return home;
    }
    if path.starts_with(b"~/") {
        let mut pattern = home.clone();
        pattern.push(b'/');
        let rest = path.strip_prefix(pattern.as_slice()).unwrap_or(path);
        let mut result = home;
        result.push(b'/');
        result.extend_from_slice(rest);
        return result;
    }
    path.to_vec()
}

/// `default_shots_dir`: `$PIC_INFO_DIR`, else `$GRIM_DEFAULT_DIR`, else
/// `$XDG_PICTURES_DIR/shots` (`$HOME/pic/shots`), with `expand_path` applied.
fn default_shots_dir() -> Vec<u8> {
    let base = match env::var_nonempty("PIC_INFO_DIR") {
        Some(value) => value,
        None => match env::var_nonempty("GRIM_DEFAULT_DIR") {
            Some(value) => value,
            None => {
                let pictures = match env::var_nonempty("XDG_PICTURES_DIR") {
                    Some(value) => value,
                    None => {
                        let mut value = env::var_or_empty("HOME");
                        value.extend_from_slice(b"/pic");
                        value
                    }
                };
                let mut base = text::strip_one_trailing_slash(&pictures).to_vec();
                base.extend_from_slice(b"/shots");
                base
            }
        },
    };
    expand_path(&base)
}

/// `find DIR -maxdepth 1 -type f -printf '%T@ %p\0' | sort -zr -n` — newest
/// first, ties broken by the reversed full line, as GNU sort does.
fn pick_latest(dir: &[u8]) -> Option<Vec<u8>> {
    let path = Path::new(std::ffi::OsStr::from_bytes(dir));
    if !path.is_dir() {
        return None;
    }
    let entries = std::fs::read_dir(path).ok()?;
    let mut candidates: Vec<(i64, i64, Vec<u8>)> = Vec::new();
    for entry in entries.flatten() {
        let metadata = match entry.metadata() {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        if !metadata.is_file() {
            continue;
        }
        let (seconds, nanos) = match metadata.modified() {
            Ok(time) => unix_time(time),
            Err(_) => continue,
        };
        candidates.push((
            seconds,
            nanos,
            entry.file_name().as_os_str().as_bytes().to_vec(),
        ));
    }
    candidates.sort_by(|left, right| {
        right
            .0
            .cmp(&left.0)
            .then(right.1.cmp(&left.1))
            // `sort -zr -n` reverses the last-resort whole-line comparison too.
            .then_with(|| right.2.cmp(&left.2))
    });
    candidates.into_iter().next().map(|(_, _, name)| {
        let mut full = dir.to_vec();
        if !full.is_empty() && !full.ends_with(b"/") {
            full.push(b'/');
        }
        full.extend_from_slice(&name);
        full
    })
}

pub fn unix_time(time: std::time::SystemTime) -> (i64, i64) {
    match time.duration_since(std::time::UNIX_EPOCH) {
        Ok(duration) => (duration.as_secs() as i64, duration.subsec_nanos() as i64),
        Err(error) => {
            let duration = error.duration();
            (
                -(duration.as_secs() as i64),
                -(duration.subsec_nanos() as i64),
            )
        }
    }
}
