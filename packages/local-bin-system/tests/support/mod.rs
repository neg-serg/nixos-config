//! Shared hermetic fixture: one temporary tree per case, fake external
//! programs first on an otherwise empty PATH, temporary `HOME`/`TMPDIR`, and a
//! cleared environment so nothing reads the host.
//!
//! Fake programs are shell scripts using only builtins. The shebang is
//! rewritten to `$LOCAL_BIN_SYSTEM_TEST_SHELL` (set by `default.nix` to the
//! store bash) because the build sandbox has no `/bin/sh`.

#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn fake_interpreter() -> String {
    std::env::var("LOCAL_BIN_SYSTEM_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
}

pub struct Case {
    pub root: PathBuf,
    pub bin: PathBuf,
    pub home: PathBuf,
    pub tmp: PathBuf,
    program: PathBuf,
}

impl Case {
    pub fn new(label: &str, program: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "local-bin-system-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&root);
        for directory in ["bin", "home", "tmp"] {
            fs::create_dir_all(root.join(directory)).expect("create fixture directory");
        }
        Self {
            bin: root.join("bin"),
            home: root.join("home"),
            tmp: root.join("tmp"),
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

    pub fn fake(&self, name: &str) -> PathBuf {
        self.bin.join(name)
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

    pub fn write_bytes(&self, path: &Path, content: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent directory");
        }
        fs::write(path, content).expect("write fixture file");
    }

    pub fn read(&self, name: &str) -> String {
        fs::read_to_string(self.root.join(name)).unwrap_or_default()
    }

    pub fn read_bytes(&self, path: &Path) -> Vec<u8> {
        fs::read(path).unwrap_or_default()
    }

    pub fn read_at(&self, path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_default()
    }

    pub fn argv_log(&self) -> String {
        self.read("argv.log")
    }

    pub fn clip_log(&self) -> String {
        self.read("clip.log")
    }

    /// A command with a cleared environment: only the fake `bin` on PATH, the
    /// temporary HOME/TMPDIR and the fixture log paths are present.
    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command
            .env_clear()
            .env("PATH", &self.bin)
            .env("HOME", &self.home)
            .env("TMPDIR", &self.tmp)
            .env("LANG", "C")
            .env("LC_ALL", "C")
            .env("FAKE_ARGV_LOG", self.root.join("argv.log"))
            .env("FAKE_CLIP", self.root.join("clip.log"))
            .env("FAKE_DMENU_IN", self.root.join("dmenu-in.log"))
            .env("FAKE_RUNNING", self.root.join("running"))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    pub fn command_in(&self, directory: &Path) -> Command {
        let mut command = self.command();
        command.current_dir(directory).env("PWD", directory);
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

    pub fn run_env(&self, arguments: &[&str], variables: &[(&str, &str)]) -> Output {
        let mut command = self.command();
        for (name, value) in variables {
            command.env(name, value);
        }
        command
            .args(arguments)
            .output()
            .expect("run the binary under test")
    }

    pub fn run_in_env(
        &self,
        directory: &Path,
        arguments: &[&str],
        variables: &[(&str, &str)],
    ) -> Output {
        let mut command = self.command_in(directory);
        for (name, value) in variables {
            command.env(name, value);
        }
        command
            .args(arguments)
            .output()
            .expect("run the binary under test")
    }

    pub fn run_stdin(&self, arguments: &[&str], input: &[u8]) -> Output {
        use std::io::Write;
        let mut child = self
            .command()
            .args(arguments)
            .stdin(Stdio::piped())
            .spawn()
            .expect("spawn the binary under test");
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(input).expect("write stdin");
        }
        child.wait_with_output().expect("wait for the binary")
    }

    pub fn run_stdin_env(
        &self,
        arguments: &[&str],
        input: &[u8],
        variables: &[(&str, &str)],
    ) -> Output {
        use std::io::Write;
        let mut command = self.command();
        for (name, value) in variables {
            command.env(name, value);
        }
        let mut child = command
            .args(arguments)
            .stdin(Stdio::piped())
            .spawn()
            .expect("spawn the binary under test");
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(input).expect("write stdin");
        }
        child.wait_with_output().expect("wait for the binary")
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

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
