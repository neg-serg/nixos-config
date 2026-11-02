//! Process helpers: `command -v`, the exit status the shell would report, and
//! the timing loop's `sleep 0.1`. The sleep stays a child process on purpose —
//! it is what the shell did, a fake on PATH can make the timeout tests instant,
//! and the loops keep their ten-steps-a-second shape.

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::process::{Command, ExitStatus};

/// `command -v NAME` for a bare name: the first PATH entry holding something
/// that is not a directory is reported, as bash 5.3 does here (the shell did
/// not require the execute bit; starting the file then fails the same way in
/// both versions).
pub fn command_v(name: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    for directory in std::env::split_paths(&path) {
        let candidate = if directory.as_os_str().is_empty() {
            PathBuf::from(name)
        } else {
            directory.join(name)
        };
        if let Ok(meta) = std::fs::metadata(&candidate) {
            if !meta.is_dir() {
                return Some(candidate);
            }
        }
    }
    None
}

/// `$?` for a finished child: the code, or 128 + the signal.
pub fn exit_code(status: ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    if let Some(code) = status.code() {
        return code;
    }
    status.signal().map(|signal| 128 + signal).unwrap_or(1)
}

/// The loops' `sleep 0.1`. A missing sleep is ignored: the shell printed the
/// bash diagnostic and spun as fast as this.
pub fn sleep_01() {
    let _ = Command::new("sleep").arg("0.1").status();
}

/// A command line for paths and arguments that may not be UTF-8.
pub fn arg_of(bytes: &[u8]) -> &OsStr {
    OsStr::from_bytes(bytes)
}
