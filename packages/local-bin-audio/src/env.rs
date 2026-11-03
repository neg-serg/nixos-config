//! Shell-facing environment helpers shared by the ports.
//!
//! The ports keep the observable behaviour of their shell originals: identical
//! argv for every external tool, the same stdout/stderr split, the same exit
//! codes, and the same environment defaults. This module holds the pieces that
//! deal with that environment: PATH lookup (`command -v`), the program name a
//! shell would print in a diagnostic, and the helpers that reproduce bash's own
//! messages (they carry the original script's line numbers, so log-scraping
//! callers see the same text).

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;

/// Raw bytes of an `OsStr`: argv, environment and file names are byte strings.
pub fn os_bytes(value: &OsStr) -> &[u8] {
    value.as_bytes()
}

pub fn os_string(bytes: &[u8]) -> OsString {
    OsString::from_vec(bytes.to_vec())
}

/// Value of an environment variable as bytes (unset and non-UTF-8 both work).
pub fn var_bytes(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(|value| value.as_bytes().to_vec())
}

/// `${NAME:-default}`: unset and empty both select the default.
pub fn var_nonempty(name: &str) -> Option<Vec<u8>> {
    var_bytes(name).filter(|value| !value.is_empty())
}

/// `${NAME:-default}` with the default always applied, as bytes.
pub fn var_or(name: &str, default: &[u8]) -> Vec<u8> {
    var_nonempty(name).unwrap_or_else(|| default.to_vec())
}

/// `$NAME` without a default; an unset variable expands to nothing.
pub fn var_or_empty(name: &str) -> Vec<u8> {
    var_bytes(name).unwrap_or_default()
}

pub fn is_executable(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `command -v <tool>`: PATH lookup for a bare name, direct check for a path.
pub fn find_in_path(tool: &[u8]) -> Option<PathBuf> {
    let tool_path = Path::new(OsStr::from_bytes(tool));
    if tool.contains(&b'/') {
        return is_executable(tool_path).then(|| tool_path.to_path_buf());
    }
    let path = var_bytes("PATH").unwrap_or_default();
    for component in path.split(|byte| *byte == b':') {
        let base = if component.is_empty() {
            PathBuf::from(".")
        } else {
            PathBuf::from(os_string(component))
        };
        let candidate = base.join(tool_path);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

/// `command -v <tool> >/dev/null 2>&1` in a boolean form.
pub fn which(tool: &[u8]) -> bool {
    find_in_path(tool).is_some()
}

/// The name a shell script would use in a diagnostic: the path passed to exec.
///
/// A kernel-executed script gets `$0` set to the resolved file path, while a
/// Rust binary started through PATH keeps the bare name in `argv[0]`; resolving
/// a bare name through PATH reproduces the script's text.
pub fn invocation_name(argv0: &OsStr) -> Vec<u8> {
    let raw = argv0.as_bytes();
    if raw.contains(&b'/') {
        return raw.to_vec();
    }
    find_in_path(raw)
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| raw.to_vec())
}

/// Exit code for a finished child: the code itself, or 128 + signal.
pub fn status_code(status: ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        code
    } else if let Some(signal) = status.signal() {
        128 + signal
    } else {
        1
    }
}

fn write_stream(mut stream: impl Write, bytes: &[u8]) {
    match stream.write_all(bytes) {
        Ok(()) => {}
        // A consumer that went away is the shell's SIGPIPE, not an error path.
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => std::process::exit(141),
        Err(_) => std::process::exit(1),
    }
}

pub fn out(bytes: &[u8]) {
    write_stream(io::stdout(), bytes);
}

pub fn err(bytes: &[u8]) {
    write_stream(io::stderr(), bytes);
}

pub fn out_line(bytes: &[u8]) {
    let mut line = Vec::with_capacity(bytes.len() + 1);
    line.extend_from_slice(bytes);
    line.push(b'\n');
    out(&line);
}

pub fn err_line(bytes: &[u8]) {
    let mut line = Vec::with_capacity(bytes.len() + 1);
    line.extend_from_slice(bytes);
    line.push(b'\n');
    err(&line);
}

pub fn out_str(text: &str) {
    out(text.as_bytes());
}

pub fn err_str(text: &str) {
    err(text.as_bytes());
}

/// bash: `<program>: line N: <tool>: command not found`.
pub fn not_found_message(program: &[u8], line: u32, tool: &[u8]) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(tool);
    message.extend_from_slice(b": command not found\n");
    message
}

/// bash: `<program>: line N: <path>: No such file or directory` (a command that
/// contains a slash is executed directly, so the diagnostic names the path).
pub fn path_failure_message(program: &[u8], line: u32, path: &[u8], error: &io::Error) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(path);
    message.extend_from_slice(b": ");
    message.extend_from_slice(error_text(error).as_bytes());
    message.push(b'\n');
    message
}

/// A redirection that could not be opened: bash names the target path.
/// `<program>: line N: <path>: Permission denied`.
pub fn redirect_failure_message(
    program: &[u8],
    line: u32,
    path: &[u8],
    error: &io::Error,
) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(path);
    message.extend_from_slice(b": ");
    message.extend_from_slice(error_text(error).as_bytes());
    message.push(b'\n');
    message
}

/// `${1:?MESSAGE}` diagnostic, exit status 1. bash spells the parameter name
/// in the message: `<program>: line N: 1: <message>`.
pub fn parameter_error(program: &[u8], line: u32, name: &[u8], message: &[u8]) -> ! {
    let mut text = Vec::new();
    text.extend_from_slice(program);
    text.extend_from_slice(format!(": line {line}: ").as_bytes());
    text.extend_from_slice(name);
    text.extend_from_slice(b": ");
    text.extend_from_slice(message);
    text.push(b'\n');
    err(&text);
    std::process::exit(1);
}

/// `exec` diagnostic, exit 127 (missing) or 126 (not executable). bash does not
/// spell the word `exec`: `<program>: line N: <path>: No such file or directory`.
pub fn exec_failure(program: &[u8], line: u32, tool: &[u8], error: &io::Error) -> ! {
    err(&path_failure_message(program, line, tool, error));
    std::process::exit(if error.raw_os_error() == Some(2) {
        127
    } else {
        126
    });
}

/// `strerror` text without Rust's "(os error N)" suffix, matching bash.
pub fn error_text(error: &io::Error) -> String {
    let text = error.to_string();
    match text.find(" (os error ") {
        Some(position) => text[..position].to_string(),
        None => text,
    }
}
