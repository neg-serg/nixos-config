//! Filesystem checks and the two operations the shell got from coreutils:
//! `dirname` (for the still helper beside the apply binary) and `ln -sfn`.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};

/// `[ -f ]`: a regular file, following a symlink.
pub fn is_regular(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_file())
        .unwrap_or(false)
}

/// `[ -x ]`: any execute bit, whatever the file type (a directory counts, and
/// so does a non-executable-for-this-user file with an execute bit elsewhere —
/// the exec attempt then reports the truth, exactly as the shell's did).
pub fn is_executable(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// `[ -s ]`: exists and has a non-zero size.
pub fn is_nonempty(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.len() > 0)
        .unwrap_or(false)
}

/// `[ a -nt b ]`: `a` exists and is newer than `b`, or `b` does not exist.
/// Bash compares the full modification time, nanoseconds included.
pub fn is_newer_than(newer: &Path, older: &Path) -> bool {
    let Ok(newer_time) = fs::metadata(newer).and_then(|meta| meta.modified()) else {
        return false;
    };
    match fs::metadata(older).and_then(|meta| meta.modified()) {
        Ok(older_time) => newer_time > older_time,
        Err(_) => true,
    }
}

/// `dirname`, including the root, trailing slashes and the no-slash cases the
/// shell used on `$0`.
pub fn dirname(argv0: &OsStr) -> PathBuf {
    let bytes = argv0.as_bytes();
    if bytes.is_empty() {
        return PathBuf::from(".");
    }
    let mut end = bytes.len();
    while end > 1 && bytes[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &bytes[..end];
    if trimmed == b"/" {
        return PathBuf::from("/");
    }
    let Some(last_slash) = trimmed.iter().rposition(|&byte| byte == b'/') else {
        return PathBuf::from(".");
    };
    let mut head = &trimmed[..last_slash];
    while head.len() > 1 && head.ends_with(b"/") {
        head = &head[..head.len() - 1];
    }
    if head.is_empty() {
        PathBuf::from("/")
    } else {
        PathBuf::from(OsString::from_vec(head.to_vec()))
    }
}

/// `ln -sfn TARGET LINK`: replace a symlink (or a file) named LINK, fail on a
/// real directory as `ln` does.
pub fn force_symlink(target: &Path, link: &Path) -> io::Result<()> {
    match fs::symlink_metadata(link) {
        Ok(meta) => {
            if meta.is_dir() {
                return Err(io::Error::new(
                    io::ErrorKind::AlreadyExists,
                    "the destination is a directory",
                ));
            }
            fs::remove_file(link)?;
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    symlink(target, link)
}

/// `printf '%s\n' "$still" > PATH`: create or truncate, default mode/umask.
pub fn write_line(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut content = Vec::with_capacity(bytes.len() + 1);
    content.extend_from_slice(bytes);
    content.push(b'\n');
    fs::write(path, content)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirname_matches_the_shell() {
        let cases: &[(&str, &str)] = &[
            ("", "."),
            ("a", "."),
            ("a/b", "a"),
            ("a/b/", "a"),
            ("/", "/"),
            ("/a", "/"),
            ("/a/", "/"),
            ("a//b", "a"),
            ("./x", "."),
            ("..", "."),
            ("/usr/bin/foo", "/usr/bin"),
            ("///", "/"),
            ("//a", "/"),
        ];
        for (input, expected) in cases {
            assert_eq!(
                dirname(OsStr::new(input)),
                PathBuf::from(expected),
                "dirname({input:?})"
            );
        }
    }
}
