//! Rust port of `packages/local-bin/bin/screenshot-toast`.
//!
//! Forwards a finished capture to `pic-info` (and from there to the toast).
//! With an explicit FILE the toast is shown unconditionally; without one, only a
//! file that landed in the last 20 seconds is announced, after its size settles.
//! `date` and `pic-info` stay subprocesses; the directory scan, the PNG
//! completeness check, the settle loop and the "already announced" stamp are
//! native.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

use local_bin_desktop::env;
use local_bin_desktop::proc::{Cmd, Sink};
use local_bin_desktop::text;

/// 40 x 150 ms bounds the wait at 6 s (the original's comment).
const SETTLE_STEPS: usize = 40;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let mut file = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_default();

    if file.is_empty() {
        let dir = shots_dir();
        let mut newest: Option<Vec<u8>> = None;
        if let Some((_, path)) = newest_file(&dir) {
            newest = Some(path);
        }
        let Some(candidate) = newest else {
            std::process::exit(0);
        };
        file = candidate;
        settle_capture(&file, &program);
        let modified = file_mtime(&file);
        let now = current_epoch(&program);
        if now - modified > 20 {
            std::process::exit(0);
        }
        let size = file_size(&file);
        let mut key = file.clone();
        key.extend_from_slice(format!(" {modified} {size}").as_bytes());
        let mut stamp = env::var_or("XDG_RUNTIME_DIR", b"/tmp");
        stamp.extend_from_slice(b"/screenshot-toast-last");
        let stamp_path = std::ffi::OsStr::from_bytes(&stamp);
        if let Ok(previous) = std::fs::read(stamp_path) {
            if text::strip_trailing_newlines(&previous) == key.as_slice() {
                std::process::exit(0);
            }
        }
        let _ = std::fs::write(stamp_path, &key);
    }

    if !Path::new(OsStr::from_bytes(&file)).exists() {
        std::process::exit(0);
    }

    // `exec pic-info "$file"`: the toast process is replaced by the helper.
    let error = Command::new("pic-info")
        .arg(OsStr::from_bytes(&file))
        .exec();
    env::exec_failure(&program, 86, b"pic-info", &error);
}

/// `PIC_INFO_DIR`, else `GRIM_DEFAULT_DIR`, else `$XDG_PICTURES_DIR/shots`.
fn shots_dir() -> Vec<u8> {
    if let Some(dir) = env::var_nonempty("PIC_INFO_DIR") {
        return dir;
    }
    if let Some(dir) = env::var_nonempty("GRIM_DEFAULT_DIR") {
        return dir;
    }
    let mut pictures = match env::var_nonempty("XDG_PICTURES_DIR") {
        Some(value) => value,
        None => {
            let mut value = env::var_or_empty("HOME");
            value.extend_from_slice(b"/pic");
            value
        }
    };
    let mut dir = text::strip_one_trailing_slash(&pictures).to_vec();
    dir.extend_from_slice(b"/shots");
    pictures = dir;
    pictures
}

/// `find DIR -maxdepth 1 -type f -printf '%T@ %p\n' | sort -rn | head -n 1`.
fn newest_file(dir: &[u8]) -> Option<((i64, i64), Vec<u8>)> {
    let path = Path::new(OsStr::from_bytes(dir));
    let entries = std::fs::read_dir(path).ok()?;
    let mut candidates: Vec<((i64, i64), Vec<u8>)> = Vec::new();
    for entry in entries.flatten() {
        let metadata = match entry.metadata() {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        if !metadata.is_file() {
            continue;
        }
        let time = match metadata.modified() {
            Ok(time) => unix_time(time),
            Err(_) => continue,
        };
        let mut full = dir.to_vec();
        if !full.ends_with(b"/") {
            full.push(b'/');
        }
        full.extend_from_slice(entry.file_name().as_os_str().as_bytes());
        candidates.push((time, full));
    }
    candidates.sort_by(|left, right| {
        right
            .0
             .0
            .cmp(&left.0 .0)
            .then(right.0 .1.cmp(&left.0 .1))
            // sort -rn reverses the last-resort whole-line comparison as well.
            .then_with(|| right.1.cmp(&left.1))
    });
    candidates.into_iter().next()
}

/// A PNG ends with the fixed IEND chunk; other formats fall back to two size
/// samples.
fn capture_complete(file: &[u8]) -> bool {
    let lowercase = file.ends_with(b".png") || file.ends_with(b".PNG");
    if !lowercase {
        return false;
    }
    match std::fs::read(OsStr::from_bytes(file)) {
        Ok(contents) => text::tail_bytes(&contents, 8) == b"IEND\xaeB`\x82",
        Err(_) => false,
    }
}

fn is_png(file: &[u8]) -> bool {
    file.ends_with(b".png") || file.ends_with(b".PNG")
}

fn settle_capture(file: &[u8], program: &[u8]) {
    let mut previous: i64 = -1;
    for _ in 0..SETTLE_STEPS {
        let size = file_size(file);
        if size > 0 {
            if capture_complete(file) {
                return;
            }
            let current = size;
            if !is_png(file) && current == previous {
                return;
            }
            previous = current;
        }
        let pause = Cmd::new("sleep").arg("0.15").diag(program, 65).run();
        if pause.code != 0 {
            std::process::exit(pause.code);
        }
    }
}

fn file_size(file: &[u8]) -> i64 {
    std::fs::metadata(OsStr::from_bytes(file))
        .map(|metadata| metadata.len() as i64)
        .unwrap_or(-1)
}

fn file_mtime(file: &[u8]) -> i64 {
    match std::fs::metadata(OsStr::from_bytes(file)) {
        Ok(metadata) => match metadata.modified() {
            Ok(time) => unix_time(time).0,
            Err(_) => 0,
        },
        Err(_) => 0,
    }
}

/// `now=$(date +%s)`; an empty or unparsable answer counts as 0 like bash
/// arithmetic does.
fn current_epoch(program: &[u8]) -> i64 {
    let date = Cmd::new("date")
        .arg("+%s")
        .stdout(Sink::Capture)
        .diag(program, 76)
        .run();
    let value = text::strip_trailing_newlines(&date.stdout);
    std::str::from_utf8(value)
        .ok()
        .and_then(|text| text.trim().parse::<i64>().ok())
        .unwrap_or(0)
}

fn unix_time(time: std::time::SystemTime) -> (i64, i64) {
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
