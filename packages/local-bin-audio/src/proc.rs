//! Subprocess helper: spawn a tool with the shell's arg/stdio/diagnostic shape.
//!
//! Every external call in a port goes through this module, so the tool is
//! spawned with the same argv and the same stdout/stderr destinations as in the
//! original script. When the tool cannot be found, the bash diagnostic (with
//! the original script's line number) is written where the shell would have
//! written it: inherited stderr, a captured pipe, or nowhere when the call had
//! `2>/dev/null`.

use std::ffi::OsString;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::process::{Child, Command, ExitStatus, Stdio};

use crate::env;

/// Where a child's stdin comes from.
#[derive(Clone, Copy)]
pub enum Input<'a> {
    /// Inherit the port's stdin (the shell default).
    Inherit,
    /// `/dev/null`.
    Null,
    /// A pipe fed with these bytes (the shell's `printf ... | tool`).
    Bytes(&'a [u8]),
}

/// Where a child's stdout/stderr goes.
#[derive(Clone, Copy)]
pub enum Sink {
    Inherit,
    Null,
    Capture,
}

/// The program name and line number bash prints when the tool is missing.
#[derive(Clone, Copy)]
pub struct Diag<'a> {
    pub program: &'a [u8],
    pub line: u32,
}

pub struct Cmd<'a> {
    tool: &'a [u8],
    args: Vec<OsString>,
    stdin: Input<'a>,
    stdout: Sink,
    stderr: Sink,
    diag: Option<Diag<'a>>,
    envs: Vec<(OsString, OsString)>,
    directory: Option<OsString>,
}

pub struct Outcome {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub found: bool,
}

impl<'a> Cmd<'a> {
    pub fn new(tool: &'a str) -> Self {
        Self::from_bytes(tool.as_bytes())
    }

    /// A tool named by bytes (paths that came from argv or the environment).
    pub fn from_bytes(tool: &'a [u8]) -> Self {
        Self {
            tool,
            args: Vec::new(),
            stdin: Input::Inherit,
            stdout: Sink::Inherit,
            stderr: Sink::Inherit,
            diag: None,
            envs: Vec::new(),
            directory: None,
        }
    }

    pub fn arg(mut self, arg: impl Into<OsString>) -> Self {
        self.args.push(arg.into());
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: Into<OsString>,
    {
        self.args.extend(args.into_iter().map(Into::into));
        self
    }

    pub fn arg_bytes(mut self, arg: &[u8]) -> Self {
        self.args.push(env::os_string(arg));
        self
    }

    pub fn stdin(mut self, stdin: Input<'a>) -> Self {
        self.stdin = stdin;
        self
    }

    pub fn stdout(mut self, sink: Sink) -> Self {
        self.stdout = sink;
        self
    }

    pub fn stderr(mut self, sink: Sink) -> Self {
        self.stderr = sink;
        self
    }

    /// Add an environment override for the child only (the shell `export`s it,
    /// but the port never mutates its own environment).
    pub fn env(mut self, name: &str, value: &[u8]) -> Self {
        self.envs
            .push((OsString::from(name), env::os_string(value)));
        self
    }

    /// Working directory for the child (the shell's `cd DIR && tool`).
    pub fn current_dir(mut self, directory: impl Into<OsString>) -> Self {
        self.directory = Some(directory.into());
        self
    }

    pub fn diag(mut self, program: &'a [u8], line: u32) -> Self {
        self.diag = Some(Diag { program, line });
        self
    }

    /// Build the `Command` without spawning (pipelines need the raw handle).
    pub fn build(&self) -> Command {
        let mut command = Command::new(std::ffi::OsStr::from_bytes(self.tool));
        command.args(&self.args);
        for (name, value) in &self.envs {
            command.env(name, value);
        }
        if let Some(directory) = &self.directory {
            command.current_dir(directory);
        }
        configure(&mut command, self.stdin, self.stdout, self.stderr);
        command
    }

    /// Spawn, feed stdin, wait, and collect whatever was captured.
    pub fn run(self) -> Outcome {
        let stdin = self.stdin;
        let mut child = match self.spawn_child() {
            Ok(child) => child,
            Err(outcome) => return outcome,
        };
        if let Input::Bytes(bytes) = stdin {
            if let Some(mut pipe) = child.stdin.take() {
                // A closed pipe is the shell's SIGPIPE on the producer side.
                let _ = pipe.write_all(bytes);
            }
        }
        match child.wait_with_output() {
            Ok(output) => Outcome {
                code: env::status_code(output.status),
                stdout: output.stdout,
                stderr: output.stderr,
                found: true,
            },
            Err(_) => Outcome {
                code: 1,
                stdout: Vec::new(),
                stderr: Vec::new(),
                found: true,
            },
        }
    }

    /// Spawn without waiting (the shell's `tool ... &`). A spawn failure is
    /// reported where the shell would report it; the caller only learns whether
    /// a child exists.
    pub fn spawn_async(self) -> Option<Child> {
        let stdin = self.stdin;
        match self.spawn_child() {
            Ok(child) => {
                if let Input::Bytes(bytes) = stdin {
                    let mut child = child;
                    if let Some(mut pipe) = child.stdin.take() {
                        let _ = pipe.write_all(bytes);
                    }
                    return Some(child);
                }
                Some(child)
            }
            Err(_) => None,
        }
    }

    fn spawn_child(self) -> Result<Child, Outcome> {
        let mut command = self.build();
        match command.spawn() {
            Ok(child) => Ok(child),
            Err(error) => Err(report_spawn_failure(
                &error,
                self.tool,
                self.diag,
                self.stderr,
            )),
        }
    }
}

/// Apply the shell's stdio destinations to a command.
pub fn configure(command: &mut Command, stdin: Input<'_>, stdout: Sink, stderr: Sink) {
    match stdin {
        Input::Inherit => {
            command.stdin(Stdio::inherit());
        }
        Input::Null => {
            command.stdin(Stdio::null());
        }
        Input::Bytes(_) => {
            command.stdin(Stdio::piped());
        }
    }
    match stdout {
        Sink::Inherit => command.stdout(Stdio::inherit()),
        Sink::Null => command.stdout(Stdio::null()),
        Sink::Capture => command.stdout(Stdio::piped()),
    };
    match stderr {
        Sink::Inherit => command.stderr(Stdio::inherit()),
        Sink::Null => command.stderr(Stdio::null()),
        Sink::Capture => command.stderr(Stdio::piped()),
    };
}

/// Emit the bash diagnostic for a failed exec and return the shell status.
pub fn report_spawn_failure(
    error: &std::io::Error,
    tool: &[u8],
    diag: Option<Diag<'_>>,
    stderr: Sink,
) -> Outcome {
    let code = spawn_error_code(error);
    let mut captured = Vec::new();
    if let Some(diag) = diag {
        let message = if tool.contains(&b'/') {
            env::path_failure_message(diag.program, diag.line, tool, error)
        } else {
            env::not_found_message(diag.program, diag.line, tool)
        };
        match stderr {
            Sink::Inherit => env::err(&message),
            Sink::Null => {}
            Sink::Capture => captured.extend_from_slice(&message),
        }
    }
    Outcome {
        code,
        stdout: Vec::new(),
        stderr: captured,
        found: false,
    }
}

pub fn spawn_error_code(error: &std::io::Error) -> i32 {
    match error.raw_os_error() {
        Some(2) => 127,
        Some(13) => 126,
        _ => {
            if error.kind() == std::io::ErrorKind::NotFound {
                127
            } else {
                126
            }
        }
    }
}

/// `$(tool ...)`: capture stdout, drop stderr, strip trailing newlines.
pub fn capture_lines(cmd: Cmd<'_>) -> (Vec<u8>, i32) {
    let outcome = cmd.stdout(Sink::Capture).stderr(Sink::Null).run();
    (
        crate::text::strip_trailing_newlines(&outcome.stdout).to_vec(),
        outcome.code,
    )
}

/// Exit status of a finished child, kept for callers that compare it.
pub fn status_code(status: ExitStatus) -> i32 {
    env::status_code(status)
}
