//! External command plumbing.
//!
//! The port keeps every user-facing tool invocation from the shell: convert,
//! mogrify, swww, swaymsg, vicinae, zoxide, wl-copy, pic-notify — and the
//! coreutils commands whose failure text is observable (mv, cp, realpath, sed).
//! Their argv, stdio redirection and "ignore the exit status" semantics are
//! reproduced here; there is no shell involved any more.

use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::Write;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::OnceLock;

/// What the shell printed as `<script>:<line>: command not found: <tool>`.
/// The line number is shell bookkeeping and has no equivalent here, so the
/// port prints `<argv0>: command not found: <tool>` instead.
pub fn command_not_found(tool: &OsStr) {
    let mut message = program().to_vec();
    message.extend_from_slice(b": command not found: ");
    message.extend_from_slice(tool.as_bytes());
    message.push(b'\n');
    let _ = std::io::stderr().write_all(&message);
}

fn program() -> &'static [u8] {
    static PROGRAM: OnceLock<Vec<u8>> = OnceLock::new();
    PROGRAM.get_or_init(|| {
        std::env::args_os()
            .next()
            .map(|value| value.into_vec())
            .unwrap_or_else(|| b"swayimg-actions".to_vec())
    })
}

/// zsh's `command -v <name>`: a non-empty PATH entry whose file exists and has
/// an executable bit. zsh does *not* accept a non-executable file the way bash
/// does, which matters for every `command -v convert` style guard in the shell.
pub fn program_exists(name: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(name);
        let Ok(metadata) = fs::metadata(&candidate) else {
            continue;
        };
        if metadata.is_dir() {
            continue;
        }
        if metadata.permissions().mode() & 0o111 != 0 {
            return true;
        }
    }
    false
}

/// Whether `[ -x "$path" ]` would be true for an explicit path.
pub fn is_executable(path: &[u8]) -> bool {
    let candidate = std::path::Path::new(OsStr::from_bytes(path));
    match fs::metadata(candidate) {
        Ok(metadata) => metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

pub struct Outcome {
    pub status: Option<ExitStatus>,
    pub stdout: Vec<u8>,
    /// Status to report when the process could not be spawned at all (127 for
    /// "command not found", 126 for other exec failures).
    fallback: i32,
}

impl Outcome {
    pub fn success(&self) -> bool {
        self.status.map(|status| status.success()).unwrap_or(false)
    }

    /// The shell's `$?`, including 128+N for a signalled child.
    pub fn code(&self) -> i32 {
        match self.status {
            Some(status) => status
                .code()
                .unwrap_or_else(|| 128 + status.signal().unwrap_or(0)),
            None => self.fallback,
        }
    }
}

pub struct Call {
    program: OsString,
    arguments: Vec<OsString>,
    input: Option<Vec<u8>>,
    capture_stdout: bool,
    stdout_null: bool,
    stderr_null: bool,
}

impl Call {
    pub fn new(program: impl Into<OsString>) -> Self {
        Self {
            program: program.into(),
            arguments: Vec::new(),
            input: None,
            capture_stdout: false,
            stdout_null: false,
            stderr_null: false,
        }
    }

    pub fn argument(mut self, argument: impl Into<OsString>) -> Self {
        self.arguments.push(argument.into());
        self
    }

    /// Feed `data` to the child's stdin (used by vicinae, wl-copy and the
    /// sed slice exactly like the shell piped printf into them).
    pub fn input(mut self, data: Vec<u8>) -> Self {
        self.input = Some(data);
        self
    }

    pub fn capture_stdout(mut self) -> Self {
        self.capture_stdout = true;
        self
    }

    /// `> /dev/null 2>&1`
    pub fn quiet(mut self) -> Self {
        self.stdout_null = true;
        self.stderr_null = true;
        self
    }

    /// `2> /dev/null`
    pub fn quiet_stderr(mut self) -> Self {
        self.stderr_null = true;
        self
    }

    pub fn run(self) -> Outcome {
        let mut command = Command::new(&self.program);
        command.args(&self.arguments);
        command.stdin(if self.input.is_some() {
            Stdio::piped()
        } else {
            Stdio::inherit()
        });
        command.stdout(if self.capture_stdout {
            Stdio::piped()
        } else if self.stdout_null {
            Stdio::null()
        } else {
            Stdio::inherit()
        });
        command.stderr(if self.stderr_null {
            Stdio::null()
        } else {
            Stdio::inherit()
        });

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                let fallback = if error.kind() == std::io::ErrorKind::NotFound {
                    if !self.stderr_null {
                        command_not_found(&self.program);
                    }
                    127
                } else {
                    if !self.stderr_null {
                        let mut message = program().to_vec();
                        message.extend_from_slice(b": ");
                        message.extend_from_slice(self.program.as_bytes());
                        message.extend_from_slice(b": ");
                        message.extend_from_slice(error.to_string().as_bytes());
                        message.push(b'\n');
                        let _ = std::io::stderr().write_all(&message);
                    }
                    126
                };
                return Outcome {
                    status: None,
                    stdout: Vec::new(),
                    fallback,
                };
            }
        };

        if let Some(data) = self.input {
            // Write stdin from a thread so a chatty child cannot deadlock on
            // a full stdout pipe while we are still feeding its stdin.
            let mut stdin = child.stdin.take();
            std::thread::spawn(move || {
                if let Some(pipe) = stdin.as_mut() {
                    let _ = pipe.write_all(&data);
                }
            });
        }

        match child.wait_with_output() {
            Ok(output) => Outcome {
                status: Some(output.status),
                stdout: output.stdout,
                fallback: 0,
            },
            Err(error) => {
                if !self.stderr_null {
                    let mut message = program().to_vec();
                    message.extend_from_slice(b": wait failed: ");
                    message.extend_from_slice(error.to_string().as_bytes());
                    message.push(b'\n');
                    let _ = std::io::stderr().write_all(&message);
                }
                Outcome {
                    status: None,
                    stdout: Vec::new(),
                    fallback: 126,
                }
            }
        }
    }
}

/// Run `realpath` the way the shell did in command substitution: stdout is
/// captured and trailing newlines are stripped; only a successful exit yields
/// a path. `stderr_null` mirrors the places where the script redirected it.
pub fn realpath(path: &[u8], stderr_null: bool) -> Option<Vec<u8>> {
    let mut call = Call::new("realpath")
        .argument(OsStr::from_bytes(path))
        .capture_stdout();
    if stderr_null {
        call = call.quiet_stderr();
    }
    let outcome = call.run();
    if !outcome.success() {
        return None;
    }
    Some(crate::bytes::strip_trailing_newlines(outcome.stdout))
}

/// The command substitution around `realpath` in the mv/cp loop and copyname:
/// a failed realpath contributes the empty string (and prints its own error).
pub fn realpath_or_empty(path: &[u8]) -> Vec<u8> {
    realpath(path, false).unwrap_or_default()
}
