//! Thin process helpers.
//!
//! The shell script delegated to `systemctl`, `pgrep`, `pkill`, `curl`, `ss`,
//! `ip`, `stat` and `sleep`. The port keeps those calls (same arguments, same
//! stdout/stderr handling) instead of reimplementing systemd or HTTP, so the
//! observable behaviour and the test strategy (fake binaries on PATH) are
//! preserved and the dependency set stays minimal.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

/// `shutil.which()`: executable regular file found through PATH.
pub fn which(program: &str) -> Option<PathBuf> {
    if program.contains('/') {
        let path = PathBuf::from(program);
        return is_executable(&path).then_some(path);
    }
    let path_var = std::env::var_os("PATH")?;
    for dir in std::env::split_paths(&path_var) {
        let candidate = dir.join(program);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    match std::fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

pub fn command_exists(program: &str) -> bool {
    which(program).is_some()
}

pub enum RunError {
    Spawn(io::Error),
    Timeout,
}

/// `subprocess.run(..., timeout=...)`: collect stdout/stderr, tolerate a
/// non-zero exit status, return `Timeout` after killing the child.
pub fn run_capture(
    program: &str,
    args: &[OsString],
    timeout: Option<Duration>,
    stderr_null: bool,
) -> Result<Output, RunError> {
    let mut command = Command::new(program);
    command.args(args);
    command.stdout(Stdio::piped());
    if stderr_null {
        command.stderr(Stdio::null());
    } else {
        command.stderr(Stdio::piped());
    }
    let mut child = command.spawn().map_err(RunError::Spawn)?;

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();
    let stdout_reader = stdout_pipe.map(|mut pipe| {
        thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = io::copy(&mut pipe, &mut buf);
            buf
        })
    });
    let stderr_reader = stderr_pipe.map(|mut pipe| {
        thread::spawn(move || {
            let mut buf = Vec::new();
            let _ = io::copy(&mut pipe, &mut buf);
            buf
        })
    });

    let deadline = timeout.map(|limit| Instant::now() + limit);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {
                if let Some(deadline) = deadline {
                    if Instant::now() >= deadline {
                        let _ = child.kill();
                        let _ = child.wait();
                        let _ = stdout_reader.map(|handle| handle.join());
                        let _ = stderr_reader.map(|handle| handle.join());
                        return Err(RunError::Timeout);
                    }
                }
                thread::sleep(Duration::from_millis(10));
            }
            Err(err) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(RunError::Spawn(err));
            }
        }
    };

    let stdout = stdout_reader
        .map(|handle| handle.join().unwrap_or_default())
        .unwrap_or_default();
    let stderr = stderr_reader
        .map(|handle| handle.join().unwrap_or_default())
        .unwrap_or_default();
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

/// Run a command quietly and report whether it succeeded.
pub fn run_success(program: &str, args: &[&str], stderr_null: bool) -> bool {
    let owned: Vec<OsString> = args.iter().map(OsString::from).collect();
    match run_capture(program, &owned, None, stderr_null) {
        Ok(output) => output.status.success(),
        Err(_) => false,
    }
}

/// Run a command, inherit stdout/stderr, ignore errors (`... || true`).
pub fn run_ignored(program: &str, args: &[&str]) {
    let owned: Vec<OsString> = args.iter().map(OsString::from).collect();
    let _ = run_capture(program, &owned, None, false);
}

pub fn stdout_trimmed(program: &str, args: &[&str]) -> Option<String> {
    let owned: Vec<OsString> = args.iter().map(OsString::from).collect();
    match run_capture(program, &owned, None, true) {
        Ok(output) => Some(String::from_utf8_lossy(&output.stdout).trim().to_string()),
        Err(_) => None,
    }
}

/// `pgrep -f <pattern> > /dev/null 2>&1`.
pub fn pgrep(pattern: &str) -> bool {
    run_success("pgrep", &["-f", pattern], true)
}

/// `pgrep -f <pattern> | head -1`.
pub fn pgrep_first(pattern: &str) -> Option<String> {
    let owned = [OsString::from("-f"), OsString::from(pattern)];
    match run_capture("pgrep", &owned, None, true) {
        Ok(output) => {
            let text = String::from_utf8_lossy(&output.stdout);
            text.lines().next().map(|line| line.trim().to_string())
        }
        Err(_) => None,
    }
}

/// `pkill -f <pattern> 2>/dev/null || true`.
pub fn pkill(pattern: &str) {
    run_ignored("pkill", &["-f", pattern]);
}

/// The shell calls the external `sleep`; keeping that makes the tests able to
/// stub delays. Fall back to an in-process sleep if `sleep` is unavailable.
pub fn sleep_secs(seconds: u64) {
    let arg = seconds.to_string();
    if let Ok(mut child) = Command::new("sleep")
        .arg(&arg)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        let _ = child.wait();
    } else {
        thread::sleep(Duration::from_secs(seconds));
    }
}

/// `tail -N <path>` to stdout (`... 2>/dev/null || true`).
pub fn tail_lines(path: &Path, count: usize) -> Vec<String> {
    match std::fs::read_to_string(path) {
        Ok(text) => {
            let lines: Vec<&str> = text.lines().collect();
            let start = lines.len().saturating_sub(count);
            lines[start..]
                .iter()
                .map(|line| (*line).to_string())
                .collect()
        }
        Err(_) => Vec::new(),
    }
}

/// `mktemp -d <prefix>XXXXXX`: a private (0700) directory removed on drop.
pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub fn new(prefix: &str) -> io::Result<Self> {
        for _ in 0..100 {
            let path = PathBuf::from(format!("{prefix}{:016x}", crate::random::random_u64()));
            match fs::create_dir(&path) {
                Ok(()) => {
                    fs::set_permissions(&path, fs::Permissions::from_mode(0o700))?;
                    return Ok(Self { path });
                }
                Err(err) if err.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(err) => return Err(err),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "cannot create a unique temp directory",
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}
