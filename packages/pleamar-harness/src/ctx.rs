//! Per-run state: output in the scripts' prefixes, child bookkeeping, the temp
//! sandbox and cleanup.
//!
//! The shell scripts used `trap cleanup EXIT INT TERM` and two `exit` wrappers
//! (`fail` = 1, `die` = 2). Here the same contract is a [`Halt`] returned by
//! the run functions; `main` reports it, cleans up and exits. A panic or a
//! signal is the only path without the cleanup (the shell had a trap for INT
//! and TERM; the port keeps normal and error exits byte-compatible and does not
//! install signal handlers — documented in the crate README).

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

use crate::proc;

/// The shell's `fail` (1) and `die` (2) plus a pre-computed exit code.
pub enum Halt {
    /// `tool: message` on stderr, exit 1.
    Fail(String),
    /// `tool: error: message` on stderr, exit 2.
    Die(String),
    /// Message already printed by the caller.
    Exit(i32),
}

impl Halt {
    pub fn code(&self) -> i32 {
        match self {
            Halt::Fail(_) => 1,
            Halt::Die(_) => 2,
            Halt::Exit(code) => *code,
        }
    }

    pub fn report(&self, tool: &str) {
        match self {
            Halt::Fail(message) => eprintln!("{tool}: {message}"),
            Halt::Die(message) => eprintln!("{tool}: error: {message}"),
            Halt::Exit(_) => {}
        }
    }
}

/// Everything one harness run owns. The `tool` string is the prefix every
/// message carries (`measure`, `describe-snap`, `smoke`).
pub struct Ctx {
    pub tool: &'static str,
    pub project: PathBuf,
    pub temp: Option<PathBuf>,
    pub keep_tmp: bool,
    pub snap_tmp: Option<PathBuf>,
    started: Vec<u32>,
    children: BTreeMap<u32, Child>,
}

impl Ctx {
    pub fn new(tool: &'static str, project: PathBuf) -> Self {
        Self {
            tool,
            project,
            temp: None,
            keep_tmp: false,
            snap_tmp: None,
            started: Vec::new(),
            children: BTreeMap::new(),
        }
    }

    /// The per-run temp dir; every caller reaches this only after `mktemp`.
    pub fn temp(&self) -> &Path {
        self.temp
            .as_deref()
            .expect("the harness called mktemp before using its temp dir")
    }

    pub fn say(&self, message: impl std::fmt::Display) {
        let mut out = std::io::stdout().lock();
        let _ = writeln!(out, "{}: {message}", self.tool);
    }

    pub fn warn(&self, message: impl std::fmt::Display) {
        let mut err = std::io::stderr().lock();
        let _ = writeln!(err, "{}: warning: {message}", self.tool);
    }

    /// Bytes to stderr without the tool prefix, for the script's own
    /// `printf '...: error: ...'` blocks (describe's capture failures).
    pub fn stderr_bytes(&self, bytes: &[u8]) {
        let mut err = std::io::stderr().lock();
        let _ = err.write_all(bytes);
        let _ = err.flush();
    }

    pub fn fail<T>(&self, message: impl Into<String>) -> Result<T, Halt> {
        Err(Halt::Fail(message.into()))
    }

    pub fn die<T>(&self, message: impl Into<String>) -> Result<T, Halt> {
        Err(Halt::Die(message.into()))
    }

    /// Register a started child and return its pid.
    pub fn spawn(&mut self, command: &mut Command) -> std::io::Result<u32> {
        let child = command.spawn()?;
        let pid = child.id();
        self.started.push(pid);
        self.children.insert(pid, child);
        Ok(pid)
    }

    /// Take a known child out of the bookkeeping; waiting consumes it.
    pub fn take(&mut self, pid: u32) -> Option<Child> {
        self.children.remove(&pid)
    }

    /// Wait for a registered child; `None` if it was never registered.
    pub fn wait(&mut self, pid: u32) -> Option<std::process::ExitStatus> {
        let mut child = self.take(pid)?;
        child.wait().ok()
    }

    /// The shell's `kill -0`: a registered child is reaped first, anything else
    /// is tested through `/proc`.
    pub fn alive(&mut self, pid: u32) -> bool {
        let state = self.children.get_mut(&pid).map(Child::try_wait);
        match state {
            Some(Ok(Some(_))) => {
                self.children.remove(&pid);
                false
            }
            Some(Ok(None)) => true,
            Some(Err(_)) => false,
            None => proc::proc_exists(pid),
        }
    }

    /// TERM the process group (or the process), wait up to 3 s, then KILL. The
    /// shell's `terminate` in all three scripts.
    pub fn terminate(&mut self, pid: u32) {
        if pid == 0 || !self.alive(pid) {
            return;
        }
        let pgid = proc::process_group(pid);
        let group = !pgid.is_empty() && pgid == pid.to_string();
        proc::kill("-TERM", pid, group);
        for _ in 0..30 {
            if !self.alive(pid) {
                return;
            }
            proc::sleep("0.1");
        }
        proc::kill("-KILL", pid, group);
        if let Some(mut child) = self.take(pid) {
            let _ = child.wait();
        }
        self.started.retain(|started| *started != pid);
    }

    /// `trap cleanup EXIT`: terminate what is still running, drop the temp dir
    /// unless `--keep-tmp`, remove a stale snapshot temp file.
    pub fn cleanup(&mut self) {
        let pids = self.started.clone();
        for pid in pids {
            self.terminate(pid);
        }
        if let Some(snap) = self.snap_tmp.take() {
            let _ = fs::remove_file(snap);
        }
        if let Some(temp) = self.temp.take() {
            if !self.keep_tmp {
                let _ = fs::remove_dir_all(temp);
            }
        }
    }

    /// Start a background command with both streams appended to `log`.
    pub fn spawn_log(&mut self, command: Command, log: &Path) -> std::io::Result<u32> {
        let child = proc::spawn_append(command, log)?;
        let pid = child.id();
        self.started.push(pid);
        self.children.insert(pid, child);
        Ok(pid)
    }

    /// Start a background command with both streams truncating `log`.
    pub fn spawn_log_truncate(&mut self, command: Command, log: &Path) -> std::io::Result<u32> {
        let child = proc::spawn_truncate(command, log)?;
        let pid = child.id();
        self.started.push(pid);
        self.children.insert(pid, child);
        Ok(pid)
    }

    /// Discard a registered child after it was waited for by pid.
    pub fn forget(&mut self, pid: u32) {
        self.children.remove(&pid);
        self.started.retain(|started| *started != pid);
    }

    /// Resolve a binary the way the shell's `resolve_bin` did.
    pub fn resolve_bin(&self, value: &str) -> Option<String> {
        crate::env::resolve_bin(value)
    }
}

/// Set up a command to read stdin from the caller, as the shell's foreground
/// commands did (no pipes are fed by the harness).
pub fn inherited_stdin(command: &mut Command) {
    command.stdin(Stdio::inherit());
}
