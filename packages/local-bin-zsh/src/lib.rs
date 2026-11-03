//! Shared runtime for the Rust ports of the zsh helpers in
//! `packages/local-bin/bin`.
//!
//! The ports keep the observable behaviour of the zsh originals: the same
//! argument handling, usage text, stdout/stderr split, exit codes, environment
//! defaults, prompts, file naming and subprocess argv. Shell text processing
//! (`${var//x/y}`, `sed`, `awk`, `cut`, `tr`, `dirname`, `basename`, `wc`,
//! `tail`, `head`, the JSON shaping of the music-tui profile) is native here;
//! programs that do real work (fd, fzf, vicinae, mpv, zathura, playerctl,
//! music-*, lspci, nc/socat, albumdetails, mv/ren/rmdir, du/stat, find/xargs,
//! vid-info) are still spawned with the original arguments.
//!
//! Two things are more obvious here than in the shell originals:
//!
//! * A missing command is a zsh diagnostic, not a Rust error: the ports print
//!   `<invocation>:<line>: command not found: <tool>` (or `<function>:<line>`
//!   when the call site sits inside a function, which is what zsh does), and
//!   the status is 127/126 exactly like an exec failure. The diagnostic is
//!   written to the call's stderr redirection, so it lands in `mpv.log` when
//!   the original redirected that command's stderr into the log.
//! * Command substitutions strip trailing newlines; the helpers below do the
//!   same, because several prompts and comparisons depend on it.

#![forbid(unsafe_code)]

use std::ffi::{OsStr, OsString};
use std::fs::{self, File};
use std::io::{self, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};

/// `"$@"`, byte-preserving so non-UTF-8 paths reach the external tools intact.
pub fn raw_args() -> Vec<OsString> {
    std::env::args_os().skip(1).collect()
}

fn argv0() -> OsString {
    std::env::args_os().next().unwrap_or_default()
}

/// `PROG=${LOCALBIN_PATH##*/}` from `_localbin.sh`: the basename the helpers
/// prefix their diagnostics with.
pub fn prog() -> Vec<u8> {
    let program = argv0();
    match Path::new(&program).file_name() {
        Some(name) => name.as_bytes().to_vec(),
        None => program.as_bytes().to_vec(),
    }
}

/// `$0` the way zsh would print it in a top-level diagnostic: the path used to
/// invoke the program, with a bare command resolved through `PATH`.
pub fn invocation() -> Vec<u8> {
    let raw = argv0();
    if raw.as_bytes().contains(&b'/') {
        return raw.as_bytes().to_vec();
    }
    which(&raw)
        .map(|path| path.into_os_string().into_vec())
        .unwrap_or_else(|| raw.as_bytes().to_vec())
}

/// `${NAME:-default}`: unset and empty both select the default.
pub fn var_nonempty(name: &str) -> Option<OsString> {
    std::env::var_os(name).filter(|value| !value.is_empty())
}

/// `$NAME`: empty when unset.
pub fn var(name: &str) -> OsString {
    std::env::var_os(name).unwrap_or_default()
}

pub fn home() -> OsString {
    var("HOME")
}

pub fn is_executable(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
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
pub fn which(tool: &OsStr) -> Option<PathBuf> {
    let path = Path::new(tool);
    if tool.as_bytes().contains(&b'/') {
        return is_executable(path).then(|| path.to_path_buf());
    }
    search_path(tool, true)
}

pub fn which_str(tool: &str) -> Option<PathBuf> {
    which(OsStr::new(tool))
}

/// `need CMD` from `_localbin.sh`: warn and continue.
pub fn need(tool: &str) {
    if which_str(tool).is_none() {
        let mut message = prog();
        message.extend_from_slice(b": missing ");
        message.extend_from_slice(tool.as_bytes());
        message.push(b'\n');
        err(&message);
    }
}

/// `die MSG` from `_localbin.sh`: `<prog>: <msg>` on stderr, status 1.
pub fn die(message: &[u8]) -> ! {
    let mut line = prog();
    line.extend_from_slice(b": ");
    line.extend_from_slice(message);
    line.push(b'\n');
    err(&line);
    std::process::exit(1);
}

pub fn die_str(message: &str) -> ! {
    die(message.as_bytes())
}

fn write_stream(mut stream: impl Write, bytes: &[u8]) {
    match stream.write_all(bytes) {
        Ok(()) => {}
        // A closed pipe is a SIGPIPE for a shell program; Rust ignores the
        // signal, so the port reproduces the shell's status.
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => std::process::exit(141),
        Err(_) => std::process::exit(1),
    }
    // Rust's stdout handle is line buffered; a child that inherits fd 1 must
    // not overtake a prefix that has no newline yet (`iommu-info` writes the
    // group prefix before spawning lspci).
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

pub fn err_line(text: &str) {
    let mut line = Vec::with_capacity(text.len() + 1);
    line.extend_from_slice(text.as_bytes());
    line.push(b'\n');
    err(&line);
}

/// Where the diagnostic of a failed `exec` goes. This mirrors the redirection
/// on the command: `2>/dev/null` silences the diagnostic, and `2>log` writes it
/// into the log (the shell applies redirections before it fails the exec).
pub enum Stderr {
    Inherit,
    Null,
    File(File),
}

enum Sink {
    Inherit,
    Suppress,
    File(File),
}

fn prepare_stderr(mode: Stderr) -> (Stdio, Sink) {
    match mode {
        Stderr::Inherit => (Stdio::inherit(), Sink::Inherit),
        Stderr::Null => (Stdio::null(), Sink::Suppress),
        Stderr::File(file) => match file.try_clone() {
            Ok(duplicate) => (Stdio::from(duplicate), Sink::File(file)),
            // Without a second descriptor the child still owns the log; the
            // failure path just cannot append its diagnostic.
            Err(_) => (Stdio::from(file), Sink::Suppress),
        },
    }
}

/// Stdin of a spawned command, with the shell's three cases.
pub enum Stdin {
    Null,
    Inherit,
    Bytes(Vec<u8>),
}

impl Stdin {
    fn into_stdio(self) -> (Stdio, Option<Vec<u8>>) {
        match self {
            Stdin::Null => (Stdio::null(), None),
            Stdin::Inherit => (Stdio::inherit(), None),
            Stdin::Bytes(bytes) => (Stdio::piped(), Some(bytes)),
        }
    }
}

/// Stdout of a foreground command that is not being captured.
pub enum Stdout {
    Inherit,
    File(File),
}

impl Stdout {
    fn into_stdio(self) -> Stdio {
        match self {
            Stdout::Inherit => Stdio::inherit(),
            Stdout::File(file) => Stdio::from(file),
        }
    }
}

/// A zsh diagnostic context: a top-level line number (`<invocation>:<line>`) or
/// `FUNCTION:LINE`, where LINE is relative to the function body — zsh sets `$0`
/// to the function name inside functions and counts the body from the line
/// after the opening brace.
#[derive(Clone, Copy)]
pub enum Site<'a> {
    Top(u32),
    Func(&'a str, u32),
}

impl Site<'_> {
    fn prefix(self) -> Vec<u8> {
        let mut prefix = match self {
            Site::Top(line) => {
                let mut prefix = invocation();
                prefix.push(b':');
                prefix.extend_from_slice(line.to_string().as_bytes());
                prefix
            }
            Site::Func(name, line) => {
                let mut prefix = name.as_bytes().to_vec();
                prefix.push(b':');
                prefix.extend_from_slice(line.to_string().as_bytes());
                prefix
            }
        };
        prefix.extend_from_slice(b": ");
        prefix
    }
}

fn failure_status(error: &io::Error) -> i32 {
    match error.kind() {
        io::ErrorKind::NotFound => 127,
        _ => 126,
    }
}

fn diagnostic(site: Site, tool: &str, error: &io::Error) -> Vec<u8> {
    let mut message = site.prefix();
    match error.kind() {
        io::ErrorKind::NotFound => {
            message.extend_from_slice(b"command not found: ");
            message.extend_from_slice(tool.as_bytes());
        }
        io::ErrorKind::PermissionDenied => {
            message.extend_from_slice(b"permission denied: ");
            message.extend_from_slice(tool.as_bytes());
        }
        _ => {
            message.extend_from_slice(lowercase(&os_error_text(error)).as_bytes());
            message.extend_from_slice(b": ");
            message.extend_from_slice(tool.as_bytes());
        }
    }
    message.push(b'\n');
    message
}

fn emit_failure(sink: Sink, site: Site, tool: &str, error: &io::Error) {
    let message = diagnostic(site, tool, error);
    match sink {
        Sink::Suppress => {}
        Sink::Inherit => err(&message),
        Sink::File(mut file) => {
            let _ = file.write_all(&message);
        }
    }
}

/// zsh's diagnostic for a command that is not a function and not on `PATH`
/// (`"mode_$choice"` in music-tui reaches this).
pub fn command_not_found(site: Site, name: &[u8]) -> i32 {
    let mut message = site.prefix();
    message.extend_from_slice(b"command not found: ");
    message.extend_from_slice(name);
    message.push(b'\n');
    err(&message);
    127
}

/// A failed shell output redirection: zsh prints
/// `<context>: <strerror lowercase>: <path>` and the command does not run.
pub fn redirection_failure(site: Site, path: &OsStr, error: &io::Error) -> i32 {
    let mut message = site.prefix();
    message.extend_from_slice(lowercase(&os_error_text(error)).as_bytes());
    message.extend_from_slice(b": ");
    message.extend_from_slice(path.as_bytes());
    message.push(b'\n');
    err(&message);
    1
}

/// Results of a captured command (a shell command substitution).
pub struct Captured {
    pub status: i32,
    pub stdout: Vec<u8>,
}

impl Captured {
    pub fn success(&self) -> bool {
        self.status == 0
    }

    /// The captured text with the trailing newlines a command substitution
    /// removes.
    pub fn text(&self) -> Vec<u8> {
        strip_trailing_newlines(self.stdout.clone())
    }
}

/// Run a command with captured stdout, mirroring `$(cmd)`.
pub fn capture(
    site: Site,
    tool: &str,
    argv: &[OsString],
    stdin: Stdin,
    stderr: Stderr,
) -> Captured {
    let (stderr_stdio, sink) = prepare_stderr(stderr);
    let (stdin_stdio, input) = stdin.into_stdio();
    let mut command = Command::new(tool);
    command
        .args(argv)
        .stdin(stdin_stdio)
        .stdout(Stdio::piped())
        .stderr(stderr_stdio);
    match command.spawn() {
        Ok(mut child) => {
            if let Some(bytes) = input {
                if let Some(mut pipe) = child.stdin.take() {
                    // The producer of a shell pipeline ignores SIGPIPE here;
                    // the pipeline's status comes from the consumer.
                    let _ = pipe.write_all(&bytes);
                }
            }
            match child.wait_with_output() {
                Ok(output) => Captured {
                    status: status_code(output.status),
                    stdout: output.stdout,
                },
                Err(_) => Captured {
                    status: 1,
                    stdout: Vec::new(),
                },
            }
        }
        Err(error) => {
            emit_failure(sink, site, tool, &error);
            Captured {
                status: failure_status(&error),
                stdout: Vec::new(),
            }
        }
    }
}

/// Run a foreground command whose stdout is inherited or redirected.
pub fn run(
    site: Site,
    tool: &str,
    argv: &[OsString],
    stdin: Stdin,
    stdout: Stdout,
    stderr: Stderr,
) -> i32 {
    let (stderr_stdio, sink) = prepare_stderr(stderr);
    let (stdin_stdio, input) = stdin.into_stdio();
    let mut command = Command::new(tool);
    command
        .args(argv)
        .stdin(stdin_stdio)
        .stdout(stdout.into_stdio())
        .stderr(stderr_stdio);
    match command.spawn() {
        Ok(mut child) => {
            if let Some(bytes) = input {
                if let Some(mut pipe) = child.stdin.take() {
                    let _ = pipe.write_all(&bytes);
                }
            }
            match child.wait() {
                Ok(status) => status_code(status),
                Err(_) => 1,
            }
        }
        Err(error) => {
            emit_failure(sink, site, tool, &error);
            failure_status(&error)
        }
    }
}

/// A background command with its stdout piped into another process.
pub fn spawn_stdout_piped(
    site: Site,
    tool: &str,
    argv: &[OsString],
    stderr: Stderr,
) -> Option<Child> {
    let (stderr_stdio, sink) = prepare_stderr(stderr);
    let mut command = Command::new(tool);
    command
        .args(argv)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(stderr_stdio);
    match command.spawn() {
        Ok(child) => Some(child),
        Err(error) => {
            emit_failure(sink, site, tool, &error);
            None
        }
    }
}

/// A background command fed by another process's stdout.
pub fn spawn_stdin_from(
    site: Site,
    tool: &str,
    argv: &[OsString],
    stdin: Stdio,
    stderr: Stderr,
) -> Option<Child> {
    let (stderr_stdio, sink) = prepare_stderr(stderr);
    let mut command = Command::new(tool);
    command
        .args(argv)
        .stdin(stdin)
        .stdout(Stdio::inherit())
        .stderr(stderr_stdio);
    match command.spawn() {
        Ok(child) => Some(child),
        Err(error) => {
            emit_failure(sink, site, tool, &error);
            None
        }
    }
}

/// A background command fed by a NUL-separated list built in-process. The
/// write happens on a helper thread so the foreground does not block on a slow
/// consumer, the way the original `printf | xargs &` block does not block.
pub fn spawn_stdin_bytes(
    site: Site,
    tool: &str,
    argv: &[OsString],
    input: Vec<u8>,
    stderr: Stderr,
) -> Option<Child> {
    let (stderr_stdio, sink) = prepare_stderr(stderr);
    let mut command = Command::new(tool);
    command
        .args(argv)
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(stderr_stdio);
    match command.spawn() {
        Ok(mut child) => {
            if let Some(mut pipe) = child.stdin.take() {
                std::thread::spawn(move || {
                    let _ = pipe.write_all(&input);
                });
            }
            Some(child)
        }
        Err(error) => {
            emit_failure(sink, site, tool, &error);
            None
        }
    }
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

/// `[[:space:]]` for the ASCII locale the scripts run in (tests force C).
fn is_shell_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

/// The `trim` function of music-rename: strip `[[:space:]]` at both ends.
pub fn trim(text: &[u8]) -> &[u8] {
    let start = text
        .iter()
        .position(|byte| !is_shell_space(*byte))
        .unwrap_or(text.len());
    let end = text
        .iter()
        .rposition(|byte| !is_shell_space(*byte))
        .map(|position| position + 1)
        .unwrap_or(start);
    &text[start..end]
}

/// Replace every occurrence of `from` with `to` (zsh `${var//from/to}`).
pub fn replace_all(text: &[u8], from: &[u8], to: &[u8]) -> Vec<u8> {
    if from.is_empty() {
        return text.to_vec();
    }
    let mut result = Vec::with_capacity(text.len());
    let mut index = 0;
    while index < text.len() {
        if text[index..].starts_with(from) {
            result.extend_from_slice(to);
            index += from.len();
        } else {
            result.push(text[index]);
            index += 1;
        }
    }
    result
}

pub fn replace_byte(text: &[u8], from: u8, to: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(text.len());
    for byte in text {
        if *byte == from {
            result.extend_from_slice(to);
        } else {
            result.push(*byte);
        }
    }
    result
}

/// `dirname --` (GNU coreutils, which is what the original calls).
pub fn dirname(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        None => b".".to_vec(),
        Some(0) => b"/".to_vec(),
        Some(position) => {
            let mut slash = position;
            while slash > 1 && trimmed[slash - 1] == b'/' {
                slash -= 1;
            }
            trimmed[..slash].to_vec()
        }
    }
}

/// `basename --` (GNU coreutils).
pub fn basename(path: &[u8]) -> Vec<u8> {
    let mut end = path.len();
    while end > 1 && path[end - 1] == b'/' {
        end -= 1;
    }
    let trimmed = &path[..end];
    if trimmed.is_empty() && !path.is_empty() {
        return b"/".to_vec();
    }
    if !trimmed.is_empty() && trimmed.iter().all(|byte| *byte == b'/') {
        return b"/".to_vec();
    }
    match trimmed.iter().rposition(|byte| *byte == b'/') {
        Some(position) => trimmed[position + 1..].to_vec(),
        None => trimmed.to_vec(),
    }
}

/// One `awk` field-1 extraction with the default `FS` (blanks separate,
/// leading blanks ignored).
pub fn first_field(line: &[u8]) -> &[u8] {
    let start = line
        .iter()
        .position(|byte| *byte != b' ' && *byte != b'\t')
        .unwrap_or(line.len());
    let end = line[start..]
        .iter()
        .position(|byte| *byte == b' ' || *byte == b'\t')
        .map(|position| start + position)
        .unwrap_or(line.len());
    &line[start..end]
}

/// `awk '{print $1}'` over the whole text: one output line per input line.
pub fn first_fields(text: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for (index, line) in text.split(|byte| *byte == b'\n').enumerate() {
        if index > 0 {
            result.push(b'\n');
        }
        result.extend_from_slice(first_field(line));
    }
    strip_trailing_newlines(result)
}

/// `cut -d . -f1` over the whole text.
pub fn before_first_dot(text: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for (index, line) in text.split(|byte| *byte == b'\n').enumerate() {
        if index > 0 {
            result.push(b'\n');
        }
        match line.iter().position(|byte| *byte == b'.') {
            Some(position) => result.extend_from_slice(&line[..position]),
            None => result.extend_from_slice(line),
        }
    }
    strip_trailing_newlines(result)
}

/// `wc -l`: newline characters, which is what the original counts.
pub fn count_newlines(bytes: &[u8]) -> usize {
    bytes.iter().filter(|byte| **byte == b'\n').count()
}

/// `tail -1`: the final line without its newline.
pub fn last_line(text: &[u8]) -> &[u8] {
    if text.is_empty() {
        return text;
    }
    let body = if text.ends_with(b"\n") {
        &text[..text.len() - 1]
    } else {
        text
    };
    match body.iter().rposition(|byte| *byte == b'\n') {
        Some(position) => &body[position + 1..],
        None => body,
    }
}

/// `${~dir}` for the forms the helpers accept: `~` and `~/...`. A named-user
/// tilde stays literal; the originals only use the home-directory form.
pub fn expand_tilde(value: &OsStr, home: &OsStr) -> OsString {
    let bytes = value.as_bytes();
    if bytes == b"~" {
        return home.to_os_string();
    }
    if let Some(rest) = bytes.strip_prefix(b"~/") {
        let mut expanded = home.as_bytes().to_vec();
        expanded.push(b'/');
        expanded.extend_from_slice(rest);
        return OsString::from_vec(expanded);
    }
    value.to_os_string()
}

/// Join an OsString suffix to a path prefix without normalizing separators
/// (the scripts build paths by string concatenation).
pub fn join_bytes(prefix: &OsStr, suffix: &[u8]) -> OsString {
    let mut bytes = prefix.as_bytes().to_vec();
    bytes.extend_from_slice(suffix);
    OsString::from_vec(bytes)
}

pub fn path_bytes(path: &Path) -> Vec<u8> {
    path.as_os_str().as_bytes().to_vec()
}

/// `strerror` text without Rust's "(os error N)" suffix.
pub fn os_error_text(error: &io::Error) -> String {
    let text = error.to_string();
    match text.find(" (os error ") {
        Some(position) => text[..position].to_string(),
        None => text,
    }
}

fn lowercase(text: &str) -> String {
    let mut characters = text.chars();
    match characters.next() {
        Some(first) => first.to_lowercase().collect::<String>() + characters.as_str(),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dirname_matches_coreutils() {
        for (input, expected) in [
            ("", "."),
            ("/", "/"),
            ("foo", "."),
            ("foo/", "."),
            ("foo/bar", "foo"),
            ("/foo", "/"),
            ("a//b", "a"),
            ("//", "/"),
            ("a/./b/", "a/."),
            (".", "."),
            ("..", "."),
        ] {
            assert_eq!(dirname(input.as_bytes()), expected.as_bytes(), "{input:?}");
        }
    }

    #[test]
    fn basename_matches_coreutils() {
        for (input, expected) in [
            ("", ""),
            ("/", "/"),
            ("foo", "foo"),
            ("foo/", "foo"),
            ("foo/bar", "bar"),
            ("/foo", "foo"),
            ("a//b", "b"),
            ("//", "/"),
            ("a/./b/", "b"),
            (".", "."),
            ("..", ".."),
        ] {
            assert_eq!(basename(input.as_bytes()), expected.as_bytes(), "{input:?}");
        }
    }

    #[test]
    fn trim_strips_shell_whitespace_only() {
        assert_eq!(trim(b"  A B \t\n"), b"A B");
        assert_eq!(trim(b""), b"");
        assert_eq!(trim(b"   "), b"");
        assert_eq!(trim("·A·".as_bytes()), "·A·".as_bytes());
    }

    #[test]
    fn first_fields_works_per_line() {
        assert_eq!(first_fields(b"2026 x\n  1995 y"), b"2026\n1995");
        assert_eq!(first_fields(b""), b"");
        assert_eq!(first_fields(b"  \n\t"), b"");
    }

    #[test]
    fn command_substitution_strips_all_trailing_newlines() {
        assert_eq!(strip_trailing_newlines(b"a\n\n\n".to_vec()), b"a");
        assert_eq!(strip_trailing_newlines(b"\n\n".to_vec()), b"");
        assert_eq!(strip_trailing_newlines(b"a\nb".to_vec()), b"a\nb");
    }

    #[test]
    fn replace_all_handles_the_music_rename_substitutions() {
        assert_eq!(replace_all(b"/A/B", b"/", b"-"), b"-A-B");
        assert_eq!(replace_all(b"2026", b"2026", b"2xQ"), b"2xQ");
        assert_eq!(replace_all(b"2026", b"2026", b""), b"");
        assert_eq!(
            replace_byte("A B".as_bytes(), b' ', "·".as_bytes()),
            "A·B".as_bytes()
        );
    }
}
