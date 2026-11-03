//! Rust port of `packages/local-bin/bin/qe`.
//!
//! Prints the most recently modified direct subdirectory (dot-directories are
//! allowed, `.git*` is not), with the same fallbacks as the original:
//! an unusable start directory is printed verbatim, and an empty result falls
//! back to the start directory. The `find | sort -nr | head -1 | cut` pipeline
//! is native: directory mtimes are compared exactly (seconds then nanoseconds),
//! ties fall back to the reversed line order `sort` uses (`LC_ALL=C` byte
//! order), and the printed path is the logical `$PWD` bash would print, not the
//! physical `getcwd` path.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

use local_bin_audio::env;

fn main() {
    let mut arguments = std::env::args_os();
    let _argv0 = arguments.next();
    let start = match arguments.next() {
        Some(value) => {
            let bytes = env::os_bytes(&value).to_vec();
            if bytes.is_empty() {
                b".".to_vec()
            } else {
                bytes
            }
        }
        None => b".".to_vec(),
    };

    let previous = logical_pwd();
    if std::env::set_current_dir(Path::new(OsStr::from_bytes(&start))).is_err() {
        env::out_line(&start);
        std::process::exit(0);
    }

    let here = if start.first() == Some(&b'/') {
        normalize(&start)
    } else {
        let mut joined = previous;
        joined.push(b'/');
        joined.extend_from_slice(&start);
        normalize(&joined)
    };

    let latest = newest_directory();
    match latest {
        Some(name) => {
            if std::env::set_current_dir(Path::new(OsStr::from_bytes(&name))).is_err() {
                env::out_line(&name);
                std::process::exit(0);
            }
            let mut joined = here;
            joined.push(b'/');
            joined.extend_from_slice(&name);
            env::out_line(&normalize(&joined));
        }
        None => env::out_line(&here),
    }
}

/// bash's logical `$PWD`: the exported value when it names the current
/// directory, otherwise the physical path.
fn logical_pwd() -> Vec<u8> {
    if let Some(pwd) = env::var_nonempty("PWD") {
        if pwd.first() == Some(&b'/') && same_directory(Path::new(OsStr::from_bytes(&pwd))) {
            return pwd;
        }
    }
    match std::env::current_dir() {
        Ok(path) => env::os_bytes(path.as_os_str()).to_vec(),
        Err(_) => b"/".to_vec(),
    }
}

fn same_directory(path: &Path) -> bool {
    let here = fs::metadata(".");
    let there = fs::metadata(path);
    match (here, there) {
        (Ok(here), Ok(there)) => here.dev() == there.dev() && here.ino() == there.ino(),
        _ => false,
    }
}

/// `find . -mindepth 1 -maxdepth 1 -type d ! -name '.git*' -printf '%T@ %P\n'`
/// then `sort -nr` and `head -1`: newest mtime wins; for identical mtimes the
/// reversed whole-line order picks the greatest name.
fn newest_directory() -> Option<Vec<u8>> {
    let entries = fs::read_dir(".").ok()?;
    let mut best: Option<(i64, i64, Vec<u8>)> = None;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let bytes = env::os_bytes(&name);
        if bytes.starts_with(b".git") {
            continue;
        }
        let is_directory = entry
            .file_type()
            .map(|file_type| file_type.is_dir())
            .unwrap_or(false);
        if !is_directory {
            continue;
        }
        let metadata = match entry.metadata() {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        let candidate = (metadata.mtime(), metadata.mtime_nsec(), bytes.to_vec());
        let replace = match &best {
            None => true,
            Some(current) => compare_candidate(&candidate, current).is_gt(),
        };
        if replace {
            best = Some(candidate);
        }
    }
    best.map(|(_, _, name)| name)
}

fn compare_candidate(
    left: &(i64, i64, Vec<u8>),
    right: &(i64, i64, Vec<u8>),
) -> std::cmp::Ordering {
    left.0
        .cmp(&right.0)
        .then_with(|| left.1.cmp(&right.1))
        .then_with(|| left.2.cmp(&right.2))
}

/// bash's lexical canonicalisation for `$PWD`: collapses slashes, drops `.`,
/// resolves `..` without looking at symlinks, and clamps at the root.
fn normalize(path: &[u8]) -> Vec<u8> {
    let absolute = path.first() == Some(&b'/');
    let mut parts: Vec<&[u8]> = Vec::new();
    for part in path.split(|byte| *byte == b'/') {
        if part.is_empty() || part == b"." {
            continue;
        }
        if part == b".." {
            match parts.last() {
                Some(last) if *last != b".." => {
                    parts.pop();
                }
                _ => {
                    if !absolute {
                        parts.push(part);
                    }
                }
            }
            continue;
        }
        parts.push(part);
    }
    let mut result = Vec::new();
    if absolute {
        result.push(b'/');
    }
    for (index, part) in parts.iter().enumerate() {
        if index > 0 {
            result.push(b'/');
        }
        result.extend_from_slice(part);
    }
    if result.is_empty() {
        result.push(b'.');
    }
    result
}
