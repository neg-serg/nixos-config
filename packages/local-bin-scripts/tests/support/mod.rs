//! Shared fixtures: one temporary tree per case, fake external programs first
//! on an otherwise empty PATH, a temporary `HOME`/`TMPDIR`, and cleared
//! environment so nothing reads the host.
//!
//! Fake programs are `/bin/sh` scripts and only use shell builtins (`printf`,
//! `read`, `case`), so they work with the isolated PATH too.

#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// The interpreter line for the fake tools. `/bin/sh` on a normal host; the
/// Nix check phase exports an absolute bash because the build sandbox has no
/// `/bin/sh`.
fn fake_shebang() -> String {
    std::env::var("LOCAL_BIN_SCRIPTS_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
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
            "local-bin-scripts-{}-{}-{}",
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
            Some(rest) => format!("#!{}\n{rest}", fake_shebang()),
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

    pub fn read(&self, name: &str) -> String {
        fs::read_to_string(self.root.join(name)).unwrap_or_default()
    }

    pub fn argv_log(&self) -> String {
        self.read("argv.log")
    }

    /// A command with a cleared environment: only the fake `bin` on PATH, the
    /// temporary HOME/TMPDIR and the two fixture log paths are present.
    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command
            .env_clear()
            .env("PATH", &self.bin)
            .env("HOME", &self.home)
            .env("TMPDIR", &self.tmp)
            .env("LANG", "C")
            .env("LC_ALL", "C")
            .env("COLUMNS", "80")
            .env("FAKE_ARGV_LOG", self.root.join("argv.log"))
            .env("FAKE_DMENU_IN", self.root.join("dmenu-in.log"))
            .env("FAKE_CLIP", self.root.join("clip.log"))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    pub fn run(&self, arguments: &[&str]) -> Output {
        self.command()
            .args(arguments)
            .output()
            .expect("run the binary under test")
    }

    pub fn program(&self) -> &Path {
        &self.program
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
