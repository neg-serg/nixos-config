//! Test fixtures: one temporary directory per case, a fake `journalctl` and
//! `systemctl` first on PATH, and `TZ` pinned to UTC unless a test overrides
//! it. Nothing here reads the host journal, writes outside the temporary
//! directory, or opens a network socket.

use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// The fake journalctl dispatches on the argv the worker sends. It records
/// every call, and its output and exit status come from `FAKE_*` variables so
/// a test can make one command fail without a second fixture.
const JOURNALCTL: &str = r#"#!/bin/sh
printf '%s\n' "journalctl $*" >> "$FAKE_ARGV_LOG"
if [ "${FAKE_SIGNAL_PARENT:-0}" = "1" ]; then
  kill "-${FAKE_SIGNAL:-TERM}" "$PPID"
  sleep 1
  : > "$FAKE_SURVIVED"
  exit 0
fi
case " $* " in
  *" -p err "*)
    printf '%s' "${FAKE_ERR_OUT:-}"
    exit "${FAKE_ERR_CODE:-0}"
    ;;
  *" -p warning "*)
    printf '%s' "${FAKE_WARN_OUT:-}"
    exit "${FAKE_WARN_CODE:-0}"
    ;;
  *)
    printf '%s' "${FAKE_LOG_OUT:-}"
    exit "${FAKE_LOG_CODE:-0}"
    ;;
esac
"#;

const SYSTEMCTL: &str = r#"#!/bin/sh
printf '%s\n' "systemctl $*" >> "$FAKE_ARGV_LOG"
printf '%s' "${FAKE_SVC_OUT:-}"
exit "${FAKE_SVC_CODE:-0}"
"#;

pub struct Case {
    pub dir: PathBuf,
    pub bin: PathBuf,
}

impl Case {
    pub fn new(label: &str) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "pleamar-journal-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("bin")).expect("create fixture directory");
        let case = Self {
            bin: dir.join("bin"),
            dir,
        };
        case.write_fake("journalctl", JOURNALCTL);
        case.write_fake("systemctl", SYSTEMCTL);
        case
    }

    fn write_fake(&self, name: &str, body: &str) {
        let path = self.bin.join(name);
        fs::write(&path, body).expect("write fake executable");
        let mut permissions = fs::metadata(&path).expect("stat fake").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("make fake executable");
    }

    pub fn remove_fake(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    pub fn set_mode(&self, name: &str, mode: u32) {
        let path = self.bin.join(name);
        let mut permissions = fs::metadata(&path).expect("stat fake").permissions();
        permissions.set_mode(mode);
        fs::set_permissions(&path, permissions).expect("chmod fake");
    }

    /// The fake binaries followed by the inherited PATH (the fake scripts use
    /// `sleep`/`kill` from it, and the shell worker needs jq in the parity
    /// harness; this binary itself needs nothing from it).
    pub fn path(&self) -> OsString {
        let mut entries = vec![self.bin.clone()];
        if let Some(path) = std::env::var_os("PATH") {
            entries.extend(std::env::split_paths(&path));
        }
        std::env::join_paths(entries).expect("join PATH")
    }

    /// PATH with only the fake binaries: no journalctl unless the fixture has
    /// one, and no jq (which the port does not need).
    pub fn isolated_path(&self) -> OsString {
        self.bin.clone().into_os_string()
    }

    pub fn argv_log(&self) -> String {
        fs::read_to_string(self.dir.join("argv.log")).unwrap_or_default()
    }

    pub fn command(&self) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_pleamar-journal"));
        command
            .env("PATH", self.path())
            .env("TZ", "UTC")
            .env("FAKE_ARGV_LOG", self.dir.join("argv.log"))
            .stdin(Stdio::null());
        command
    }

    pub fn run(&self, arguments: &[&str]) -> Output {
        self.command()
            .args(arguments)
            .output()
            .expect("run pleamar-journal")
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

pub fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("stdout is UTF-8 JSON")
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("stderr is UTF-8")
}
