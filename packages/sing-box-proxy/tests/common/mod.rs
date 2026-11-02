//! Shared helpers for the integration tests.
//!
//! Every test that drives external commands uses a stub directory on PATH.
//! The stubs are POSIX `#!/bin/sh` scripts (the Nix sandbox provides
//! `/bin/sh`), so the suite never needs the real systemd, the real network, the
//! real sing-box process, /run/secrets, or the live config.

#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::time::{SystemTime, UNIX_EPOCH};

pub struct TestDir {
    path: PathBuf,
}

impl TestDir {
    pub fn new(tag: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let path = std::env::temp_dir().join(format!(
            "sing-box-proxy-test-{tag}-{}-{nanos:x}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("create test dir");
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn join(&self, name: &str) -> PathBuf {
        self.path.join(name)
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

pub fn write_script(path: &Path, body: &str) {
    fs::write(path, format!("#!/bin/sh\n{body}\n")).expect("write stub");
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).expect("chmod stub");
}

pub struct Stubs {
    dir: TestDir,
}

impl Stubs {
    pub fn new(tag: &str) -> Self {
        Self {
            dir: TestDir::new(tag),
        }
    }

    pub fn add(&self, name: &str, body: &str) {
        write_script(&self.dir.join(name), body);
    }

    pub fn path(&self) -> &Path {
        self.dir.path()
    }

    /// PATH that contains only the stubs.
    pub fn only_path(&self) -> String {
        self.dir.path().display().to_string()
    }

    /// Stubs first, then the inherited PATH (used by shell-parity tests that
    /// still need coreutils/jq).
    pub fn layered_path(&self) -> String {
        format!(
            "{}:{}",
            self.dir.path().display(),
            std::env::var("PATH").unwrap_or_default()
        )
    }
}

/// Run the compiled `proxy` binary with a clean environment.
pub fn run_proxy(args: &[&str], envs: &[(String, String)], path: &str) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_proxy"));
    command.args(args).env_clear();
    command.env("PATH", path);
    for (key, value) in envs {
        command.env(key, value);
    }
    command.output().expect("run proxy binary")
}

/// Run the legacy shell implementation (only for tests that are safe: no
/// secret reads, no network) with the same clean environment.
pub fn run_shell(script: &Path, args: &[&str], envs: &[(String, String)], path: &str) -> Output {
    let mut command = Command::new("bash");
    command.arg(script).args(args).env_clear();
    command.env("PATH", path);
    for (key, value) in envs {
        command.env(key, value);
    }
    command.output().expect("run shell proxy")
}

/// HOME plus the secret overrides, pointing at a throwaway directory.
pub fn base_env(dir: &TestDir) -> Vec<(String, String)> {
    vec![
        ("HOME".to_string(), dir.path().display().to_string()),
        (
            "PROXY_SECRET".to_string(),
            dir.join("missing-secret").display().to_string(),
        ),
        (
            "PROXY_LAN_SECRET".to_string(),
            dir.join("missing-lan-secret").display().to_string(),
        ),
    ]
}

pub fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// The shell parity test only runs where the legacy script is available.
pub fn shell_script() -> Option<PathBuf> {
    let path = std::env::var_os("PROXY_SHELL").map(PathBuf::from)?;
    path.is_file().then_some(path)
}

pub fn fixture(relative: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(relative);
    fs::read_to_string(&path).unwrap_or_else(|err| panic!("read {}: {err}", path.display()))
}

pub fn shell_mode(path: &Path) -> u32 {
    fs::metadata(path).expect("metadata").permissions().mode() & 0o777
}

/// Stub bodies shared between tests.
pub mod scripts {
    pub const SYSTEMCTL_FAIL: &str = "exit 1";
    pub const SYSTEMCTL_OK: &str = "exit 0";
    pub const PGREP_FAIL: &str = "exit 1";
    pub const PGREP_4242: &str = "printf '4242\\n'\nexit 0";
    pub const IGNORE: &str = "exit 0";
    pub const SLEEP: &str = "exit 0";
    pub const SS_LISTENERS: &str = r#"case "$*" in
  *-tlnp*)
    printf 'LISTEN 0 4096 127.0.0.1:10808 0.0.0.0:* users:(("sing-box",pid=1,fd=3))\n'
    printf 'LISTEN 0 4096 0.0.0.0:10810 0.0.0.0:* users:(("sing-box",pid=1,fd=4))\n'
    printf 'LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=2,fd=3))\n'
    ;;
  *) : ;;
esac"#;
    pub const SS_ACTIVE: &str = r#"case "$*" in
  *-tlnp*)
    printf 'LISTEN 0 4096 127.0.0.1:10808 0.0.0.0:* users:(("sing-box",pid=1,fd=3))\n'
    ;;
  *-tnp*)
    printf 'ESTAB 0 0 10.8.0.2:443 198.51.100.7:5555 users:(("sing-box",pid=4242,fd=9))\n'
    ;;
  *) : ;;
esac"#;
    pub const STAT: &str = "printf '2026-01-02 03:04:05.000000000 +0000\\n'";
    pub const IP: &str =
        "printf '2: eth0    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0\\n'";
    pub const CURL_STATUS: &str = r#"case "$*" in
  *api.telegram.org*) printf '200|0.500' ;;
  *gstatic*) printf '204|0.123' ;;
  *) printf '000|0' ;;
esac"#;
    pub const CURL_PROBES_OK: &str = r#"case "$*" in
  *speed.cloudflare.com*) printf '250000' ;;
  *api.telegram.org*) printf '200' ;;
  *) printf '204' ;;
esac"#;
}
