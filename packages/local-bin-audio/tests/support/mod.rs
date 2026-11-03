//! Shared fixtures: one temporary tree per case, fake external programs first
//! on an otherwise empty PATH, a temporary `HOME`/`TMPDIR`/`XDG_RUNTIME_DIR`,
//! and a cleared environment so nothing reads the host.
//!
//! Fake programs are shell scripts and only use shell builtins, so they work
//! with the isolated PATH. Their standard prelude appends one argv record per
//! invocation (`tool<TAB>arg<TAB>...`) to `$FAKE_LOG`; tests assert on it.

#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// The interpreter line for the fake tools. `/bin/sh` on a normal host; the Nix
/// check phase exports an absolute bash because the build sandbox has no
/// `/bin/sh`.
fn fake_shebang() -> String {
    std::env::var("LOCAL_BIN_AUDIO_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
}

pub struct Outcome {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

pub struct Sandbox {
    pub root: PathBuf,
    pub bin: PathBuf,
    pub home: PathBuf,
    pub tmp: PathBuf,
    pub run_dir: PathBuf,
    pub case: PathBuf,
    pub log: PathBuf,
    program: PathBuf,
}

impl Sandbox {
    pub fn new(label: &str, program: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "local-bin-audio-{}-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.subsec_nanos())
                .unwrap_or(0)
        ));
        let _ = fs::remove_dir_all(&root);
        for directory in ["bin", "home", "tmp", "run", "case"] {
            fs::create_dir_all(root.join(directory)).expect("create fixture directory");
        }
        fs::write(root.join("argv.log"), b"").expect("create argv log");
        Self {
            bin: root.join("bin"),
            home: root.join("home"),
            tmp: root.join("tmp"),
            run_dir: root.join("run"),
            case: root.join("case"),
            log: root.join("argv.log"),
            program: PathBuf::from(program),
            root,
        }
    }

    /// Write a logging fake: the body runs after the argv record was written.
    pub fn fake(&self, name: &str, body: &str) {
        let mut text = format!("#!{}\n", fake_shebang());
        text.push_str("line=\"");
        text.push_str(name);
        text.push_str("\"\n");
        text.push_str("for arg in \"$@\"; do line=\"$line\t$arg\"; done\n");
        text.push_str("printf '%s\\n' \"$line\" >> \"$FAKE_LOG\"\n");
        text.push_str(body);
        if !body.ends_with('\n') {
            text.push('\n');
        }
        self.fake_raw(name, &text);
    }

    /// Write an executable file verbatim (used for fakes with custom logging).
    pub fn fake_raw(&self, name: &str, body: &str) {
        let path = self.bin.join(name);
        fs::write(&path, body).expect("write fake executable");
        let mut permissions = fs::metadata(&path).expect("stat fake").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("make fake executable");
    }

    pub fn remove_fake(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    pub fn write(&self, relative: &str, content: &[u8]) -> PathBuf {
        let path = self.case.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create case parent");
        }
        fs::write(&path, content).expect("write case file");
        path
    }

    pub fn write_home(&self, relative: &str, content: &[u8]) -> PathBuf {
        let path = self.home.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create home parent");
        }
        fs::write(&path, content).expect("write home file");
        path
    }

    pub fn read_case(&self, relative: &str) -> Vec<u8> {
        fs::read(self.case.join(relative)).unwrap_or_default()
    }

    pub fn read_home(&self, relative: &str) -> Vec<u8> {
        fs::read(self.home.join(relative)).unwrap_or_default()
    }

    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command
            .env_clear()
            .env("PATH", &self.bin)
            .env("HOME", &self.home)
            .env("TMPDIR", &self.tmp)
            .env("XDG_RUNTIME_DIR", &self.run_dir)
            .env("LANG", "C")
            .env("LC_ALL", "C")
            .env("PWD", &self.case)
            .env("FAKE_LOG", &self.log)
            .current_dir(&self.case)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    pub fn run(&self, args: &[&str]) -> Outcome {
        self.run_env(args, &[])
    }

    pub fn run_env(&self, args: &[&str], envs: &[(&str, &str)]) -> Outcome {
        let mut command = self.command();
        for (name, value) in envs {
            command.env(name, value);
        }
        let output = command
            .args(args)
            .output()
            .expect("run the binary under test");
        Outcome {
            code: output
                .status
                .code()
                .unwrap_or_else(|| panic!("terminated by a signal: {:?}", output.status)),
            stdout: output.stdout,
            stderr: output.stderr,
        }
    }

    /// The raw argv log (one `tool<TAB>arg...` line per invocation).
    pub fn log(&self) -> String {
        fs::read_to_string(&self.log).unwrap_or_default()
    }

    /// Wait until the argv log contains `needle` (background helpers).
    pub fn wait_log(&self, needle: &str) -> String {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            let log = self.log();
            if log.contains(needle) || Instant::now() >= deadline {
                return log;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    pub fn log_lines_for(&self, tool: &str) -> Vec<String> {
        self.log()
            .lines()
            .filter(|line| line.split('\t').next() == Some(tool))
            .map(str::to_string)
            .collect()
    }

    pub fn path(&self, relative: &str) -> PathBuf {
        self.root.join(relative)
    }

    pub fn program(&self) -> &Path {
        &self.program
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

pub fn text(bytes: &[u8]) -> String {
    String::from_utf8(bytes.to_vec()).expect("output is UTF-8")
}

pub fn mode(path: &Path, bits: u32) {
    let mut permissions = fs::metadata(path).expect("stat fixture").permissions();
    permissions.set_mode(bits);
    fs::set_permissions(path, permissions).expect("chmod fixture");
}
