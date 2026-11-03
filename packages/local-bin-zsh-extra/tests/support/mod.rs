//! Shared hermetic fixture for the local-bin-zsh-extra tests.
//!
//! Every case gets its own temporary tree with an otherwise empty PATH, fake
//! external programs that log their argv/stdin, and temporary HOME/XDG/TMPDIR
//! values. The fakes are shell scripts that use only shell builtins, so they
//! work with the isolated PATH; `default.nix` points
//! LOCAL_BIN_ZSH_EXTRA_TEST_SHELL at the store bash because a build sandbox
//! does not necessarily provide `/bin/sh`.
//!
//! Nothing in the suite touches the real VM, sysctl, MPD queue, trash,
//! `/dev/shm` or GitHub: every tool is a fake or a fixture and every path is
//! under the per-case temporary root.

#![allow(dead_code)]

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn fake_interpreter() -> String {
    std::env::var("LOCAL_BIN_ZSH_EXTRA_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
}

/// The host `mkdir` used by the fake to create fixture directories. Nix sets
/// the variable in preCheck; a plain `cargo test` finds it on the normal PATH,
/// because the isolated PATH only exists inside the spawned fixture.
fn host_mkdir() -> String {
    if let Ok(value) = std::env::var("LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR") {
        return value;
    }
    host_tool("mkdir").unwrap_or_else(|| "/bin/mkdir".to_string())
}

fn host_rm() -> String {
    if let Ok(value) = std::env::var("LOCAL_BIN_ZSH_EXTRA_TEST_RM") {
        return value;
    }
    host_tool("rm").unwrap_or_else(|| "/bin/rm".to_string())
}

fn host_tool(name: &str) -> Option<String> {
    let path = std::env::var_os("PATH").unwrap_or_default();
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(name);
        if let Ok(metadata) = fs::metadata(&candidate) {
            if metadata.is_file() && metadata.permissions().mode() & 0o111 != 0 {
                return Some(candidate.to_string_lossy().into_owned());
            }
        }
    }
    None
}

pub struct Case {
    pub root: PathBuf,
    pub bin: PathBuf,
    pub home: PathBuf,
    pub tmp: PathBuf,
    pub logs: PathBuf,
    program: PathBuf,
}

impl Case {
    pub fn new(label: &str, program: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "local-bin-zsh-extra-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&root);
        for directory in [
            "bin",
            "home",
            "home/tmp",
            "home/.local/bin",
            "home/.cache",
            "home/.config",
            "xdg/cache",
            "xdg/config",
            "xdg/data",
            "xdg/state",
            "logs",
            "work",
        ] {
            fs::create_dir_all(root.join(directory)).expect("create fixture directory");
        }
        Self {
            bin: root.join("bin"),
            home: root.join("home"),
            tmp: root.join("home/tmp"),
            logs: root.join("logs"),
            root,
            program: PathBuf::from(program),
        }
    }

    pub fn write_fake(&self, name: &str, body: &str) {
        let body = match body.strip_prefix("#!/bin/sh\n") {
            Some(rest) => format!("#!{}\n{rest}", fake_interpreter()),
            None => body.to_string(),
        };
        let path = self.bin.join(name);
        fs::write(&path, body).expect("write fake executable");
        let mut permissions = fs::metadata(&path).expect("stat fake").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("make fake executable");
    }

    pub fn remove_fake(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    pub fn path(&self, name: &str) -> PathBuf {
        self.root.join(name)
    }

    pub fn write(&self, path: &Path, content: &str) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent directory");
        }
        fs::write(path, content).expect("write fixture file");
    }

    pub fn write_executable(&self, path: &Path, body: &str) {
        let body = match body.strip_prefix("#!/bin/sh\n") {
            Some(rest) => format!("#!{}\n{rest}", fake_interpreter()),
            None => body.to_string(),
        };
        self.write(path, &body);
        let mut permissions = fs::metadata(path).expect("stat executable").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).expect("make executable");
    }

    pub fn read_at(&self, path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_default()
    }

    pub fn log_path(&self, tool: &str) -> PathBuf {
        self.logs.join(format!("{tool}.argv"))
    }

    /// The argv log of `tool`, in the format the fake writes:
    /// `<tool>\nARG <arg>\n...`.
    pub fn argv(&self, tool: &str) -> String {
        self.read_at(&self.log_path(tool))
    }

    pub fn stdin(&self, tool: &str) -> String {
        self.read_at(&self.logs.join(format!("{tool}.stdin")))
    }

    pub fn calls(&self) -> String {
        self.read_at(&self.logs.join("calls.log"))
    }

    pub fn clear_logs(&self) {
        let _ = fs::remove_dir_all(&self.logs);
        fs::create_dir_all(&self.logs).expect("recreate log directory");
    }

    pub fn wait_for_log(&self, tool: &str) {
        self.wait_for_path(&self.log_path(tool));
    }

    pub fn wait_for_path(&self, path: &Path) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if path.exists() {
                return;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        panic!("timed out waiting for {}", path.display());
    }

    pub fn wait_for_file_containing(&self, path: &Path, needle: &str) {
        let deadline = Instant::now() + Duration::from_secs(5);
        while Instant::now() < deadline {
            if self.read_at(path).contains(needle) {
                return;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        panic!("timed out waiting for {needle:?} in {}", path.display());
    }

    pub fn command(&self) -> Command {
        self.command_in(&self.root)
    }

    pub fn command_in(&self, directory: &Path) -> Command {
        let mut command = Command::new(&self.program);
        command
            .current_dir(directory)
            .env_clear()
            .env("PATH", &self.bin)
            .env("HOME", &self.home)
            .env("TMPDIR", &self.tmp)
            .env("XDG_CACHE_HOME", self.root.join("xdg/cache"))
            .env("XDG_CONFIG_HOME", self.root.join("xdg/config"))
            .env("XDG_DATA_HOME", self.root.join("xdg/data"))
            .env("XDG_STATE_HOME", self.root.join("xdg/state"))
            .env("LANG", "C")
            .env("LC_ALL", "C")
            .env("FAKE_LOG_DIR", &self.logs)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        for variable in [
            "LOCAL_BIN_ZSH_EXTRA_TEST_SHELL",
            "LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR",
            "LOCAL_BIN_ZSH_EXTRA_TEST_RM",
        ] {
            if let Ok(value) = std::env::var(variable) {
                command.env(variable, value);
            }
        }
        command.env("LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR", host_mkdir());
        command.env("LOCAL_BIN_ZSH_EXTRA_TEST_RM", host_rm());
        command
    }

    pub fn run(&self, arguments: &[&str]) -> Output {
        self.command()
            .args(arguments)
            .output()
            .expect("run the binary under test")
    }

    pub fn run_in(&self, directory: &Path, arguments: &[&str]) -> Output {
        self.command_in(directory)
            .args(arguments)
            .output()
            .expect("run the binary under test")
    }

    pub fn run_with_input(&self, arguments: &[&str], input: &[u8]) -> Output {
        let mut child = self
            .command()
            .args(arguments)
            .stdin(Stdio::piped())
            .spawn()
            .expect("spawn the binary under test");
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(input);
        }
        child
            .wait_with_output()
            .expect("wait for the binary under test")
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

pub fn tool_script(name: &str, prefix: &str) -> String {
    format!(
        r#"#!/bin/sh
{{ printf '%s\n' '{name}'; printf '%s\n' '{name}' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; }} >> "$FAKE_LOG_DIR/{name}.argv"
: > "$FAKE_LOG_DIR/{name}.stdin"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/{name}.stdin"; done
printf '%s' "${{FAKE_{prefix}_OUT-}}"
printf '%s' "${{FAKE_{prefix}_ERR-}}" >&2
exit "${{FAKE_{prefix}_CODE:-0}}"
"#
    )
}

pub const MKDIR: &str = r#"#!/bin/sh
{ printf 'mkdir\n'; printf 'mkdir\n' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/mkdir.argv"
exec "${LOCAL_BIN_ZSH_EXTRA_TEST_MKDIR:-/bin/mkdir}" "$@"
"#;

pub fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("stdout is UTF-8")
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("stderr is UTF-8")
}

pub fn exited(output: &Output) -> i32 {
    output
        .status
        .code()
        .unwrap_or_else(|| panic!("terminated by a signal: {:?}", output.status))
}

pub fn expected_argv(tool: &str, arguments: &[&str]) -> String {
    let mut log = format!("{tool}\n");
    for argument in arguments {
        log.push_str(&format!("ARG {argument}\n"));
    }
    log
}
