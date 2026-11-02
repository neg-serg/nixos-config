//! swayimg IPC: the shell piped `<command>\n` into `socat - UNIX-CONNECT:$sock`
//! (or `ncat -U`). The port connects with a `UnixStream` directly; every
//! failure stays silent, exactly like the `|| true` pipelines it replaces.
//!
//! Socket discovery is also the shell's: `$SWAYIMG_IPC` when it is a socket,
//! otherwise the newest `swayimg-*.sock` (by mtime) in `$XDG_RUNTIME_DIR`, with
//! `/run/user/<uid>` as the fallback runtime directory. Only the first match is
//! checked — a newer non-socket entry makes the lookup fail rather than falling
//! through to an older socket.

use std::fs;
use std::io::Write;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

fn variable(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(|value| value.into_vec())
}

fn non_empty(name: &str) -> Option<Vec<u8>> {
    variable(name).filter(|value| !value.is_empty())
}

fn as_path(bytes: &[u8]) -> PathBuf {
    PathBuf::from(std::ffi::OsStr::from_bytes(bytes))
}

fn is_socket(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_socket())
        .unwrap_or(false)
}

fn current_uid() -> Option<u32> {
    let status = fs::read("/proc/self/status").ok()?;
    for line in status.split(|&b| b == b'\n') {
        if let Some(rest) = line.strip_prefix(b"Uid:") {
            return std::str::from_utf8(rest)
                .ok()?
                .split_whitespace()
                .next()?
                .parse()
                .ok();
        }
    }
    None
}

fn runtime_dir() -> Option<Vec<u8>> {
    if let Some(dir) = non_empty("XDG_RUNTIME_DIR") {
        return Some(dir);
    }
    current_uid().map(|uid| crate::bytes::join(b"/run/user", uid.to_string().as_bytes()))
}

pub fn find_socket() -> Option<PathBuf> {
    if let Some(candidate) = non_empty("SWAYIMG_IPC") {
        let path = as_path(&candidate);
        if is_socket(&path) {
            return Some(path);
        }
    }

    let runtime = runtime_dir()?;
    let runtime_path = as_path(&runtime);
    if !runtime_path.is_dir() {
        return None;
    }

    // zsh: matches=("$rt"/swayimg-*.sock(Nom)) -> sort by modification time,
    // newest first, null-glob when there is no match.
    let mut matches: Vec<(i64, i64, Vec<u8>)> = Vec::new();
    let entries = fs::read_dir(&runtime_path).ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.as_bytes();
        if !name.starts_with(b"swayimg-") || !name.ends_with(b".sock") {
            continue;
        }
        let path = entry.path();
        let Ok(metadata) = fs::metadata(&path) else {
            continue;
        };
        matches.push((
            metadata.mtime(),
            metadata.mtime_nsec(),
            path.into_os_string().into_vec(),
        ));
    }
    // Newest mtime first. zsh's `(om)` leaves equal-mtime order unspecified;
    // the port breaks ties by path (descending) to stay deterministic.
    matches.sort_by(|a, b| (b.0, b.1, &b.2).cmp(&(a.0, a.1, &a.2)));
    let (_, _, first) = matches.into_iter().next()?;
    let path = as_path(&first);
    if is_socket(&path) {
        Some(path)
    } else {
        None
    }
}

/// `_ipc_send <command>`: best effort, never surfaces an error.
pub fn send(command: &[u8]) {
    let Some(socket) = find_socket() else {
        return;
    };
    let Ok(mut stream) = UnixStream::connect(socket) else {
        return;
    };
    let _ = stream.write_all(command);
    let _ = stream.write_all(b"\n");
}
