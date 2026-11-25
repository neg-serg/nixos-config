//! Environment, PATH lookup, stream and diagnostic helpers shared by the ports.
//!
//! Diagnostics reproduce the text bash prints for the originals, including the
//! original source line. The five scripts are small; matching the interpreter
//! diagnostics keeps logs and the parity harness byte-comparable.
//!
//! The stream, exit-status and `strerror` helpers are identical to the ones in
//! `local-bin-core` and are re-exported from there. What stays here is the part
//! whose *text* is specific to these five ports: bash's `line N:` prefix and the
//! `exec:`/`command not found` wording.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io;
use std::os::unix::ffi::OsStrExt;

use std::path::{Path, PathBuf};

// Byte-identical helpers: one implementation, used by every local-bin port.
pub use local_bin_core::env::{
    err, err_line, err_str, is_executable, os_error_text, out, out_str, status_code,
};

/// `"$@"` with Unix byte fidelity.
pub fn raw_args() -> Vec<OsString> {
    std::env::args_os().skip(1).collect()
}

fn argv0() -> OsString {
    std::env::args_os().next().unwrap_or_default()
}

/// `PROG=${LOCALBIN_PATH##*/}` — the basename `_localbin.sh` uses.
pub fn prog_name() -> Vec<u8> {
    let program = argv0();
    match Path::new(&program).file_name() {
        Some(name) => name.as_bytes().to_vec(),
        None => program.as_bytes().to_vec(),
    }
}

/// The name bash uses in `line N:` diagnostics: `$0`, with a bare command
/// resolved through PATH the way the invoking shell resolved it.
pub fn invocation_name() -> Vec<u8> {
    let raw = argv0();
    if raw.as_bytes().contains(&b'/') {
        return raw.as_bytes().to_vec();
    }
    find_in_path(&raw)
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| raw.as_bytes().to_vec())
}

/// `${NAME:-default}`: unset and empty both select the default.
pub fn var_nonempty(name: &str) -> Option<OsString> {
    std::env::var_os(name).filter(|value| !value.is_empty())
}

fn search_path(tool: &OsStr, require_executable: bool) -> Option<PathBuf> {
    let search = std::env::var_os("PATH").unwrap_or_default();
    std::env::split_paths(&search)
        .map(|directory| {
            if directory.as_os_str().is_empty() {
                PathBuf::from(".")
            } else {
                directory
            }
        })
        .map(|directory| directory.join(tool))
        .find(|candidate| {
            if require_executable {
                is_executable(candidate)
            } else {
                fs::metadata(candidate).is_ok()
            }
        })
}

/// `command -v`: an executable file on `PATH`, or an explicit path.
pub fn find_in_path(tool: &OsStr) -> Option<PathBuf> {
    let path = Path::new(tool);
    if tool.as_bytes().contains(&b'/') {
        return is_executable(path).then(|| path.to_path_buf());
    }
    search_path(tool, true)
}

/// The resolved path of a command that exists but may not be executable; used
/// for the `Permission denied` diagnostics bash prints with the full path.
fn resolved_tool(tool: &str) -> Vec<u8> {
    search_path(OsStr::new(tool), false)
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| tool.as_bytes().to_vec())
}

pub fn which(tool: &str) -> Option<PathBuf> {
    find_in_path(OsStr::new(tool))
}

/// `need CMD` from `_localbin.sh`: warn on stderr and continue.
pub fn need(prog: &[u8], tool: &str) {
    if which(tool).is_none() {
        let mut message = prog.to_vec();
        message.extend_from_slice(b": missing ");
        message.extend_from_slice(tool.as_bytes());
        message.push(b'\n');
        err(&message);
    }
}

fn diagnostic_prefix(prog: &[u8], line: u32) -> Vec<u8> {
    let mut message = prog.to_vec();
    message.extend_from_slice(b": line ");
    message.extend_from_slice(line.to_string().as_bytes());
    message.extend_from_slice(b": ");
    message
}

/// Report a failed `Command::status()`/`Command::output()` without exiting;
/// `v` keeps going after its optional helpers fail.
pub fn report_spawn_failure(prog: &[u8], line: u32, tool: &str, error: &io::Error) {
    let mut message = diagnostic_prefix(prog, line);
    match error.kind() {
        io::ErrorKind::NotFound => {
            message.extend_from_slice(tool.as_bytes());
            message.extend_from_slice(b": command not found\n");
            err(&message);
        }
        io::ErrorKind::PermissionDenied => {
            message.extend_from_slice(&resolved_tool(tool));
            message.extend_from_slice(b": Permission denied\n");
            err(&message);
        }
        _ => {
            message.extend_from_slice(tool.as_bytes());
            message.extend_from_slice(b": ");
            message.extend_from_slice(os_error_text(error).as_bytes());
            message.push(b'\n');
            err(&message);
        }
    }
}

fn failure_status(error: &io::Error) -> i32 {
    if error.kind() == io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

/// A non-`exec` command that could not be started: bash's `command not found`
/// (127) or `Permission denied` (126) diagnostic.
pub fn spawn_failure(prog: &[u8], line: u32, tool: &str, error: &io::Error) -> ! {
    report_spawn_failure(prog, line, tool, error);
    std::process::exit(failure_status(error));
}

/// A failed `exec`: bash prefixes the tool with `exec: ` only for a missing
/// command; a permission failure is reported with the resolved path.
pub fn exec_failure(prog: &[u8], line: u32, tool: &str, error: &io::Error) -> ! {
    let mut message = diagnostic_prefix(prog, line);
    match error.kind() {
        io::ErrorKind::NotFound => {
            message.extend_from_slice(b"exec: ");
            message.extend_from_slice(tool.as_bytes());
            message.extend_from_slice(b": not found\n");
            err(&message);
        }
        io::ErrorKind::PermissionDenied => {
            message.extend_from_slice(&resolved_tool(tool));
            message.extend_from_slice(b": Permission denied\n");
            err(&message);
        }
        _ => {
            message.extend_from_slice(b"exec: ");
            message.extend_from_slice(tool.as_bytes());
            message.extend_from_slice(b": ");
            message.extend_from_slice(os_error_text(error).as_bytes());
            message.push(b'\n');
            err(&message);
        }
    }
    std::process::exit(failure_status(error));
}

/// A failed shell input redirection: `<"$ARG"` printed by bash, status 1.
pub fn redirect_failure(prog: &[u8], line: u32, path: &OsStr, error: &io::Error) -> ! {
    let mut message = diagnostic_prefix(prog, line);
    message.extend_from_slice(path.as_bytes());
    message.extend_from_slice(b": ");
    message.extend_from_slice(os_error_text(error).as_bytes());
    message.push(b'\n');
    err(&message);
    std::process::exit(1);
}
