//! Process and command helpers shared by the three binaries.
//!
//! The shell harnesses piped most external output through coreutils. The port
//! keeps the interesting commands (`pleamar`, `pleamar-wm`, `ps`, `systemctl`,
//! `grim`, ...) as subprocesses with identical argv and environment, and reads
//! `/proc`/`/sys` directly where the shell used `cat`/`awk`.

use std::fs::OpenOptions;
use std::io;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Child, Command, ExitStatus, Output, Stdio};

/// Trim the trailing newlines a shell command substitution would remove.
pub fn trim_newlines(text: &str) -> &str {
    text.trim_end_matches('\n')
}

/// The shell's `$?` for a finished command: 128 + signal when it was killed.
pub fn exit_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

/// Spawn `program` with `args`, capturing stdout and stderr separately.
pub fn output<S: AsRef<std::ffi::OsStr>>(program: &str, args: &[S]) -> io::Result<Output> {
    let mut command = Command::new(program);
    command.args(args);
    command.output()
}

/// Run a command with stdout captured and stderr discarded. Used for every
/// probe the scripts ran inside command substitutions with `2> /dev/null`.
pub fn stdout_silent<S: AsRef<std::ffi::OsStr>>(program: &str, args: &[S]) -> io::Result<String> {
    let mut command = Command::new(program);
    command.args(args).stderr(Stdio::null());
    let output = command.output()?;
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// Run a command with both streams discarded and return its status.
pub fn status_silent<S: AsRef<std::ffi::OsStr>>(program: &str, args: &[S]) -> Option<ExitStatus> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    command.status().ok()
}

/// `sleep`, logged and faked by the tests so the loops are instant.
pub fn sleep(seconds: &str) {
    let _ = status_silent("sleep", &[seconds]);
}

/// Send a signal with the external `kill`, exactly like the shell's `kill`
/// builtin did: `kill -TERM -- -PGID` when the process leads its group,
/// `kill -TERM PID` otherwise.
pub fn kill(signal: &str, pid: u32, group: bool) {
    let pid = pid.to_string();
    let status = if group {
        let negative = format!("-{pid}");
        status_silent("kill", &[signal, "--", negative.as_str()])
    } else {
        status_silent("kill", &[signal, pid.as_str()])
    };
    let _ = status;
}

/// Start a command whose stdout and stderr both append to `log`. Returns the
/// child so the caller can register or wait for it.
pub fn spawn_append(mut command: Command, log: &Path) -> io::Result<Child> {
    let file = OpenOptions::new().create(true).append(true).open(log)?;
    let stderr = file.try_clone()?;
    command
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(stderr));
    command.spawn()
}

/// Start a command with stdout and stderr both written to a fresh `log`.
pub fn spawn_truncate(mut command: Command, log: &Path) -> io::Result<Child> {
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(log)?;
    let stderr = file.try_clone()?;
    command
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(stderr));
    command.spawn()
}

/// Run a command synchronously with stdout and stderr appended to `log`.
pub fn status_append(mut command: Command, log: &Path) -> io::Result<ExitStatus> {
    let file = OpenOptions::new().create(true).append(true).open(log)?;
    let stderr = file.try_clone()?;
    command
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(stderr));
    command.status()
}

/// Run a command with stdout and stderr merged into one file, for the shell's
/// `out="$(cmd 2>&1)"`. Both descriptors share the file offset, so the
/// interleaving is the kernel's, as it was with the shell's dup.
pub fn output_merged<S: AsRef<std::ffi::OsStr>>(
    program: &str,
    args: &[S],
    merged: &Path,
) -> io::Result<ExitStatus> {
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(merged)?;
    let stderr = file.try_clone()?;
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(stderr));
    command.status()
}

/// Detach a background command into its own session (`setsid`), as the scripts
/// did for scene runners and renderers.
pub fn setsid(command: Command) -> Command {
    let command = command;
    let mut args: Vec<std::ffi::OsString> = Vec::new();
    let original = command.get_program().to_os_string();
    args.push(original);
    for arg in command.get_args() {
        args.push(arg.to_os_string());
    }
    let mut wrapped = Command::new("setsid");
    wrapped.args(args);
    for (key, value) in command.get_envs() {
        match value {
            Some(value) => {
                wrapped.env(key, value);
            }
            None => {
                wrapped.env_remove(key);
            }
        }
    }
    if let Some(dir) = command.get_current_dir() {
        wrapped.current_dir(dir);
    }
    wrapped
}

/// Process group id from `ps -o pgid= -p PID`; empty when there is none.
pub fn process_group(pid: u32) -> String {
    let pid = pid.to_string();
    stdout_silent("ps", &["-o", "pgid=", "-p", pid.as_str()])
        .unwrap_or_default()
        .replace(' ', "")
        .trim()
        .to_string()
}

/// A Pid written as the shell saw it (digits only).
pub fn proc_exists(pid: u32) -> bool {
    Path::new(&format!("/proc/{pid}")).exists()
}

/// `pgrep -P PID`: the direct children of a process, one per line.
pub fn children_of(pid: u32) -> Vec<u32> {
    let pid = pid.to_string();
    let text = stdout_silent("pgrep", &["-P", pid.as_str()]).unwrap_or_default();
    text.lines()
        .filter_map(|line| line.trim().parse::<u32>().ok())
        .collect()
}
