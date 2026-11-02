//! Environment, PATH lookup and stdout/stderr helpers shared by the ports.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;

/// Raw bytes of an `OsStr` (Unix argv/environment is byte-oriented).
pub fn os_bytes(value: &OsStr) -> &[u8] {
    value.as_bytes()
}

pub fn os_string(bytes: &[u8]) -> OsString {
    OsString::from_vec(bytes.to_vec())
}

pub fn var_os(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

pub fn var_bytes(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(|value| value.as_bytes().to_vec())
}

/// `${NAME:-default}` for bytes: unset and empty both mean "use the default".
pub fn var_nonempty(name: &str) -> Option<Vec<u8>> {
    var_bytes(name).filter(|value| !value.is_empty())
}

pub fn is_executable(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `command -v <tool>` for a plain command name or a path containing a slash.
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

/// The name bash would put in a script diagnostic: the path used to exec the
/// script. Rust binaries get argv[0] (possibly just `tty-log` from PATH), so a
/// bare name is resolved through PATH to match the shebang invocation.
pub fn invocation_name(argv0: &OsStr) -> Vec<u8> {
    let raw = argv0.as_bytes();
    if raw.contains(&b'/') {
        return raw.to_vec();
    }
    find_in_path(raw)
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| raw.to_vec())
}

/// Exit code for a status: the code itself, or 128 + signal for a killed child.
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

/// Message bash prints for a simple command that cannot be found. The port
/// keeps the original line number so log-scraping callers see the same text.
pub fn command_not_found(program: &[u8], line: u32, tool: &[u8]) {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(tool);
    message.extend_from_slice(b": command not found\n");
    err(&message);
}

/// `exec`-specific diagnostic (bash: `line N: exec: tool: not found`).
pub fn exec_failure(program: &[u8], line: u32, tool: &[u8], error: &io::Error) -> ! {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: exec: ").as_bytes());
    message.extend_from_slice(tool);
    match error.raw_os_error() {
        Some(2) => message.extend_from_slice(b": not found\n"),
        Some(13) => message.extend_from_slice(b": cannot execute: Permission denied\n"),
        _ => {
            message.extend_from_slice(b": ");
            message.extend_from_slice(error.to_string().as_bytes());
            message.push(b'\n');
        }
    }
    err(&message);
    std::process::exit(if error.raw_os_error() == Some(2) {
        127
    } else {
        126
    });
}

/// `strerror` text without Rust's "(os error N)" suffix, for the shell-style
/// redirection diagnostics the originals let bash print.
pub fn os_error_text(error: &io::Error) -> String {
    let text = error.to_string();
    match text.find(" (os error ") {
        Some(position) => text[..position].to_string(),
        None => text,
    }
}
