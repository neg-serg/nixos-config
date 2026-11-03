//! Shared fixtures: one temporary tree per case, fake external programs first
//! on an otherwise empty PATH, temporary HOME/XDG/TMPDIR, and a cleared
//! environment so nothing reads the host.
//!
//! Fake programs are shell scripts that only use builtins (`printf`, `read`,
//! `case`), so they also work with the isolated PATH. The interpreter line is
//! rewritten to LOCAL_BIN_MISC_TEST_SHELL when the Nix check sets it, because
//! a build sandbox does not necessarily provide /bin/sh.

#![allow(dead_code)]

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn fake_shebang() -> String {
    std::env::var("LOCAL_BIN_MISC_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
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
            "local-bin-misc-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&root);
        for directory in [
            "bin",
            "home",
            "tmp",
            "xdg/cache",
            "xdg/config",
            "xdg/data",
            "xdg/state",
        ] {
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

    pub fn env_log(&self) -> String {
        self.read("env.log")
    }

    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command
            .current_dir(&self.root)
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
            .env("FAKE_ARGV_LOG", self.root.join("argv.log"))
            .env("FAKE_ENV_LOG", self.root.join("env.log"))
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

    pub fn run_with_stdin(&self, arguments: &[&str], input: &[u8]) -> Output {
        let mut child = self
            .command()
            .args(arguments)
            .stdin(Stdio::piped())
            .spawn()
            .expect("spawn the binary under test");
        child
            .stdin
            .take()
            .expect("piped stdin")
            .write_all(input)
            .expect("write fixture stdin");
        child.wait_with_output().expect("collect output")
    }

    /// A socket path inside the case tree; `v` tests point
    /// LOCAL_BIN_MISC_V_SOCKET here so they never touch /tmp/nvim.sock.
    pub fn socket_path(&self) -> PathBuf {
        self.path("nvim.sock")
    }

    /// Bind a Unix socket and drop the listener immediately: the path remains
    /// as a socket file, which is all the `[ -S ]` check needs.
    pub fn write_stale_socket(&self) {
        let path = self.socket_path();
        assert!(
            fs::symlink_metadata(&path).is_err(),
            "socket fixture already exists: {}",
            path.display()
        );
        let listener = std::os::unix::net::UnixListener::bind(&path).expect("bind fixture socket");
        drop(listener);
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
