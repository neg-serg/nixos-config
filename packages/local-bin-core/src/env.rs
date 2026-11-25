//! Shell-facing environment helpers shared by every local-bin port.
//!
//! The ports keep the observable behaviour of their shell originals: identical
//! argv for every external tool, the same stdout/stderr split, the same exit
//! codes, and the same environment defaults. This module holds the pieces that
//! deal with that environment: PATH lookup (`command -v`), the program name a
//! shell would print in a diagnostic, process status decoding and the helpers
//! that reproduce bash's own messages.
//!
//! The desktop, audio, scripts and misc ports each grew a copy of these
//! helpers, and the copies drifted in three ways: the same function with a
//! different argument type, a message written for a different shell original,
//! or a helper only one crate needed. The first is resolved here (one canonical
//! signature); the second keeps every wording, because the text is what the
//! originals printed; the third is simply the union. Command modules use this
//! module directly, so `which` answers the bool question, `which_path` returns
//! where the command was found, and `find_in_path` returns the `PathBuf`.

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

pub fn var_os(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

/// Value of an environment variable as bytes (unset and non-UTF-8 both work).
pub fn var_bytes(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name).map(|value| value.as_bytes().to_vec())
}

/// `${NAME:-default}`: unset and empty both select the default.
pub fn var_nonempty(name: &str) -> Option<Vec<u8>> {
    var_bytes(name).filter(|value| !value.is_empty())
}

/// `${NAME:-default}` as an `OsString`, for callers that hand it to a child process.
pub fn var_nonempty_os(name: &str) -> Option<OsString> {
    std::env::var_os(name).filter(|value| !value.is_empty())
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

fn which_path(tool: &str) -> Option<PathBuf> {
    find_in_path(tool.as_bytes())
}

fn argv0() -> OsString {
    std::env::args_os().next().unwrap_or_default()
}

/// `"$@"` with Unix byte fidelity.
pub fn raw_args() -> Vec<OsString> {
    std::env::args_os().skip(1).collect()
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
    find_in_path(raw.as_bytes())
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| raw.as_bytes().to_vec())
}

/// The name bash would put in a script diagnostic: the path used to exec the
/// script. Rust binaries get argv[0] (possibly just `tty-log` from PATH), so a
/// bare name is resolved through PATH to match the shebang invocation.
pub fn invocation_name_of(argv0: &OsStr) -> Vec<u8> {
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
    // Rust's stdout is line buffered; a child that inherits fd 1 must not
    // overtake a prefix that has no newline yet (`iommu-info` prints the group
    // prefix before spawning lspci).
    let _ = stream.flush();
}

pub fn out(bytes: &[u8]) {
    write_stream(io::stdout(), bytes);
}

pub fn out_str(text: &str) {
    out(text.as_bytes());
}

pub fn out_line(bytes: &[u8]) {
    let mut line = Vec::with_capacity(bytes.len() + 1);
    line.extend_from_slice(bytes);
    line.push(b'\n');
    out(&line);
}

pub fn err(bytes: &[u8]) {
    write_stream(io::stderr(), bytes);
}

pub fn err_str(text: &str) {
    err(text.as_bytes());
}

pub fn err_line(bytes: &[u8]) {
    let mut line = Vec::with_capacity(bytes.len() + 1);
    line.extend_from_slice(bytes);
    line.push(b'\n');
    err(&line);
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

/// bash: `<program>: line N: <tool>: command not found`.
pub fn not_found_message(program: &[u8], line: u32, tool: &[u8]) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(tool);
    message.extend_from_slice(b": command not found\n");
    message
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

/// bash: `<program>: line N: <path>: No such file or directory` (a command that
/// contains a slash is executed directly, so the diagnostic names the path).
pub fn path_failure_message(program: &[u8], line: u32, path: &[u8], error: &io::Error) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    message.extend_from_slice(path);
    message.extend_from_slice(b": ");
    message.extend_from_slice(os_error_text(error).as_bytes());
    message.push(b'\n');
    message
}

/// `cd` diagnostic: `<program>: line N: cd: <path>: No such file or directory`.
pub fn cd_message(program: &[u8], line: u32, path: &[u8]) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: cd: ").as_bytes());
    message.extend_from_slice(path);
    message.extend_from_slice(b": No such file or directory\n");
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
    message.extend_from_slice(os_error_text(error).as_bytes());
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

fn diagnostic_prefix(prog: &[u8], line: u32) -> Vec<u8> {
    let mut message = prog.to_vec();
    message.extend_from_slice(b": line ");
    message.extend_from_slice(line.to_string().as_bytes());
    message.extend_from_slice(b": ");
    message
}

/// The resolved path of a command that exists but may not be executable; used
/// for the `Permission denied` diagnostics bash prints with the full path.
fn resolved_tool(tool: &str) -> Vec<u8> {
    search_path(OsStr::new(tool), false)
        .map(|path| path.as_os_str().as_bytes().to_vec())
        .unwrap_or_else(|| tool.as_bytes().to_vec())
}

fn failure_status(error: &io::Error) -> i32 {
    if error.kind() == io::ErrorKind::NotFound {
        127
    } else {
        126
    }
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

/// A non-`exec` command that could not be started: bash's `command not found`
/// (127) or `Permission denied` (126) diagnostic.
pub fn spawn_failure(prog: &[u8], line: u32, tool: &str, error: &io::Error) -> ! {
    report_spawn_failure(prog, line, tool, error);
    std::process::exit(failure_status(error));
}

/// `exec` diagnostic, exit 127 (missing) or 126 (not executable).
pub fn exec_failure(program: &[u8], line: u32, tool: &[u8], error: &io::Error) -> ! {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: exec: ").as_bytes());
    message.extend_from_slice(tool);
    let mut code = 126;
    match error.raw_os_error() {
        Some(2) => {
            message.extend_from_slice(b": not found\n");
            code = 127;
        }
        Some(13) => message.extend_from_slice(b": cannot execute: Permission denied\n"),
        _ => {
            message.extend_from_slice(b": ");
            message.extend_from_slice(os_error_text(error).as_bytes());
            message.push(b'\n');
        }
    }
    err(&message);
    std::process::exit(code);
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

/// A failing bash arithmetic expansion or `(( ))` command.
pub struct ArithmeticError {
    /// The operand bash named in the diagnostic (the expanded value).
    pub value: Vec<u8>,
    /// The suffix from the first invalid character on.
    pub token: Vec<u8>,
}

/// Evaluate one operand the way bash arithmetic does.
///
/// bash parses an integer with an optional sign, `0x` hexadecimal, a leading
/// zero meaning octal, and treats an empty expansion as 0. A bare word is a
/// variable reference; the ports only meet numbers produced by jq or bc, so an
/// unknown word is treated as an unset variable (0) as well.
pub fn bash_int(value: &[u8]) -> Result<i64, ArithmeticError> {
    let text = trim_ascii(value);
    if text.is_empty() {
        return Ok(0);
    }
    if is_bare_word(text) {
        return Ok(0);
    }
    let mut index = 0;
    let mut negative = false;
    match text[0] {
        b'+' => index = 1,
        b'-' => {
            negative = true;
            index = 1;
        }
        _ => {}
    }
    let digits_start = index;
    let mut radix = 10u32;
    if text.len() >= index + 2 && text[index] == b'0' && (text[index + 1] | 0x20) == b'x' {
        radix = 16;
        index += 2;
    } else if text[index] == b'0' && index + 1 < text.len() && text[index + 1].is_ascii_digit() {
        radix = 8;
    }
    let number_start = index;
    while index < text.len() && (text[index] as char).to_digit(radix).is_some() {
        index += 1;
    }
    if index == number_start {
        return Err(ArithmeticError {
            value: text.to_vec(),
            token: text[digits_start..].to_vec(),
        });
    }
    if index != text.len() {
        return Err(ArithmeticError {
            value: text.to_vec(),
            token: text[index..].to_vec(),
        });
    }
    let digits = std::str::from_utf8(&text[number_start..index]).unwrap_or("");
    match i64::from_str_radix(digits, radix) {
        Ok(number) => Ok(if negative { -number } else { number }),
        Err(_) => Err(ArithmeticError {
            value: text.to_vec(),
            token: Vec::new(),
        }),
    }
}

fn trim_ascii(value: &[u8]) -> &[u8] {
    let mut start = 0;
    let mut end = value.len();
    while start < end && matches!(value[start], b' ' | b'\t' | b'\n' | b'\r') {
        start += 1;
    }
    while end > start && matches!(value[end - 1], b' ' | b'\t' | b'\n' | b'\r') {
        end -= 1;
    }
    &value[start..end]
}

fn is_bare_word(value: &[u8]) -> bool {
    if value.is_empty() {
        return false;
    }
    if !(value[0].is_ascii_alphabetic() || value[0] == b'_') {
        return false;
    }
    value
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'_')
}

/// bash's arithmetic diagnostic. `conditional` selects the `(( ))` spelling.
pub fn arithmetic_message(
    program: &[u8],
    line: u32,
    conditional: bool,
    error: &ArithmeticError,
) -> Vec<u8> {
    let mut message = Vec::new();
    message.extend_from_slice(program);
    message.extend_from_slice(format!(": line {line}: ").as_bytes());
    if conditional {
        message.extend_from_slice(b"((: ");
    }
    message.extend_from_slice(&error.value);
    message.extend_from_slice(
        b": arithmetic syntax error: invalid arithmetic operator (error token is \"",
    );
    message.extend_from_slice(&error.token);
    message.extend_from_slice(b"\")\n");
    message
}

/// `need CMD` from `_localbin.sh`: warn on stderr and continue.
pub fn need(prog: &[u8], tool: &str) {
    if which_path(tool).is_none() {
        let mut message = prog.to_vec();
        message.extend_from_slice(b": missing ");
        message.extend_from_slice(tool.as_bytes());
        message.push(b'\n');
        err(&message);
    }
}

pub fn search_path(tool: &OsStr, require_executable: bool) -> Option<PathBuf> {
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
