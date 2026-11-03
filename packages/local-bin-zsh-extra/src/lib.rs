//! Shared runtime for the Rust ports of the six zsh helpers in
//! `packages/local-bin/bin`.
//!
//! The ports keep the observable behaviour of the zsh originals: the same
//! argument handling, usage text, stdout/stderr split, exit codes, environment
//! defaults, prompts, file naming and subprocess argv. Shell text processing
//! (`sed`, `awk`, `cut`, `tr`, `head`, `dirname`, the JSON shaping that jq did)
//! is native here; programs that do real work (gh, mpc, swayimg, wpctl,
//! notify-send, sudo, sysctl, virsh, virt-install, virt-xml, qemu-img, curl,
//! mkdir, mv, rm) are still spawned with the original arguments.
//!
//! A failed spawn is a zsh diagnostic, not a Rust error: the ports print
//! `<site>: command not found: <tool>` (only when the command's stderr is not
//! redirected to `/dev/null`, where zsh suppresses it too) and return 127/126.
//! Command substitutions strip their trailing newlines, because several
//! comparisons and prompts depend on it.

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

pub fn argv0() -> OsString {
    std::env::args_os().next().unwrap_or_default()
}

/// `"$@"`, byte-preserving so non-UTF-8 paths reach the external tools intact.
pub fn raw_args() -> Vec<OsString> {
    std::env::args_os().skip(1).collect()
}

/// The basename of argv[0], which is what `basename "$0"` prints.
pub fn prog() -> Vec<u8> {
    let argv0 = argv0();
    match Path::new(&argv0).file_name() {
        Some(name) => name.as_bytes().to_vec(),
        None => argv0.as_bytes().to_vec(),
    }
}

pub fn is_executable(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

fn search_path(tool: &OsStr) -> Option<PathBuf> {
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
        .find(|candidate| is_executable(candidate))
}

/// `command -v`: an executable file on `PATH`, or an explicit path.
pub fn which(tool: &OsStr) -> Option<PathBuf> {
    if tool.as_bytes().contains(&b'/') {
        let path = Path::new(tool);
        return is_executable(path).then(|| path.to_path_buf());
    }
    search_path(tool)
}

pub fn which_str(tool: &str) -> Option<PathBuf> {
    which(OsStr::new(tool))
}

fn write_stream(mut stream: impl Write, bytes: &[u8]) {
    match stream.write_all(bytes) {
        Ok(()) => {}
        // A closed pipe is SIGPIPE for a shell program; Rust ignores the
        // signal, so the port reproduces the shell's status.
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => std::process::exit(141),
        Err(_) => std::process::exit(1),
    }
    let _ = stream.flush();
}

pub fn out(bytes: &[u8]) {
    write_stream(io::stdout(), bytes);
}

pub fn out_str(text: &str) {
    out(text.as_bytes());
}

pub fn out_line(text: &str) {
    out(format!("{text}\n").as_bytes());
}

pub fn err(bytes: &[u8]) {
    write_stream(io::stderr(), bytes);
}

pub fn err_str(text: &str) {
    err(text.as_bytes());
}

pub fn err_line(text: &str) {
    err(format!("{text}\n").as_bytes());
}

/// The shell's status for a child (128 + signal for signal deaths).
pub fn status_code(status: ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        code
    } else if let Some(signal) = status.signal() {
        128 + signal
    } else {
        1
    }
}

/// Command substitution: all trailing newlines disappear.
pub fn strip_trailing_newlines(mut bytes: Vec<u8>) -> Vec<u8> {
    while bytes.last() == Some(&b'\n') {
        bytes.pop();
    }
    bytes
}

/// `head -1`: the first line without its newline.
pub fn first_line(text: &[u8]) -> &[u8] {
    match text.iter().position(|byte| *byte == b'\n') {
        Some(position) => &text[..position],
        None => text,
    }
}

/// zsh's default word splitting (`${=var}`): space, tab and newline only.
pub fn split_shell_words(text: &str) -> Vec<&str> {
    text.split(|character| matches!(character, ' ' | '\t' | '\n'))
        .filter(|word| !word.is_empty())
        .collect()
}

#[derive(Clone, Copy)]
pub enum StdioMode {
    Inherit,
    Null,
}

impl StdioMode {
    fn stdio(self) -> Stdio {
        match self {
            StdioMode::Inherit => Stdio::inherit(),
            StdioMode::Null => Stdio::null(),
        }
    }
}

pub struct Captured {
    pub status: i32,
    pub stdout: Vec<u8>,
}

/// Run a command with captured stdout, mirroring `$(cmd)`.
pub fn capture(tool: &str, args: &[OsString], stderr: StdioMode) -> io::Result<Captured> {
    let output = Command::new(tool)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(stderr.stdio())
        .output()?;
    Ok(Captured {
        status: status_code(output.status),
        stdout: output.stdout,
    })
}

/// Run a foreground command, mirroring a plain command call.
pub fn run(tool: &str, args: &[OsString], stdout: StdioMode, stderr: StdioMode) -> io::Result<i32> {
    let status = Command::new(tool)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(stdout.stdio())
        .stderr(stderr.stdio())
        .status()?;
    Ok(status_code(status))
}

pub fn failure_status(error: &io::Error) -> i32 {
    match error.kind() {
        io::ErrorKind::NotFound => 127,
        _ => 126,
    }
}

fn os_error_text(error: &io::Error) -> String {
    let text = error.to_string();
    match text.find(" (os error ") {
        Some(position) => text[..position].to_string(),
        None => text,
    }
}

/// zsh's diagnostic for a command that is not on `PATH`; suppressed when the
/// command redirected stderr to `/dev/null`.
pub fn report_spawn_failure(site: &str, tool: &str, error: &io::Error, stderr: StdioMode) -> i32 {
    if matches!(stderr, StdioMode::Inherit) {
        match error.kind() {
            io::ErrorKind::NotFound => {
                err_line(&format!("{site}: command not found: {tool}"));
            }
            io::ErrorKind::PermissionDenied => {
                err_line(&format!("{site}: permission denied: {tool}"));
            }
            _ => {
                err_line(&format!("{site}: {}: {tool}", os_error_text(error)));
            }
        }
    }
    failure_status(error)
}

/// `$(cmd)` for an optional command: `None` on spawn failure, with the zsh
/// diagnostic written according to `stderr`.
pub fn capture_checked(
    site: &str,
    tool: &str,
    args: &[OsString],
    stderr: StdioMode,
) -> Option<Captured> {
    match capture(tool, args, stderr) {
        Ok(captured) => Some(captured),
        Err(error) => {
            report_spawn_failure(site, tool, &error, stderr);
            None
        }
    }
}

/// A plain command call that keeps going regardless of the status
/// (`|| true`): missing tools still get the zsh diagnostic.
pub fn run_ignored(site: &str, tool: &str, args: &[OsString], stderr: StdioMode) -> i32 {
    match run(tool, args, StdioMode::Inherit, stderr) {
        Ok(status) => status,
        Err(error) => report_spawn_failure(site, tool, &error, stderr),
    }
}
