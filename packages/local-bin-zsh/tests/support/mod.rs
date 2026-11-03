//! Shared hermetic fixture for the local-bin-zsh tests.
//!
//! Every case gets its own temporary tree with an otherwise empty PATH, fake
//! external programs that log their argv and stdin, and temporary HOME/XDG/
//! TMPDIR values. The fakes are shell scripts that use only shell builtins, so
//! they work with the isolated PATH; `default.nix` points
//! LOCAL_BIN_ZSH_TEST_SHELL at the store bash because a build sandbox does not
//! necessarily provide `/bin/sh`.
//!
//! Nothing in the suite touches the real music library, `~/dw`, the IOMMU
//! sysfs tree or `/tmp` sockets: the spawn targets are fakes and the IOMMU
//! fixture root is routed through LOCAL_BIN_ZSH_IOMMU_ROOT.

#![allow(dead_code)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn fake_interpreter() -> String {
    std::env::var("LOCAL_BIN_ZSH_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
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
            "local-bin-zsh-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&root);
        for directory in [
            "bin",
            "home",
            "home/tmp",
            "home/bin",
            "home/.cache",
            "home/.config",
            "xdg/cache",
            "xdg/config",
            "xdg/data",
            "xdg/state",
            "logs",
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
        self.write(path, body);
        let mut permissions = fs::metadata(path).expect("stat executable").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).expect("make executable");
    }

    pub fn write_bytes(&self, path: &Path, content: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent directory");
        }
        fs::write(path, content).expect("write fixture file");
    }

    pub fn read_at(&self, path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_default()
    }

    pub fn read_bytes_at(&self, path: &Path) -> Vec<u8> {
        fs::read(path).unwrap_or_default()
    }

    /// The argv log of `tool`, in the format the fake writes:
    /// `<tool>\nARG <arg>\n...`.
    pub fn argv(&self, tool: &str) -> String {
        self.read_at(&self.logs.join(format!("{tool}.argv")))
    }

    pub fn stdin(&self, tool: &str) -> String {
        self.read_at(&self.logs.join(format!("{tool}.stdin")))
    }

    pub fn log_path(&self, tool: &str) -> PathBuf {
        self.logs.join(format!("{tool}.argv"))
    }

    pub fn wait_for_log(&self, tool: &str) {
        let path = self.log_path(tool);
        let deadline = Instant::now() + Duration::from_secs(3);
        while Instant::now() < deadline {
            if path.exists() {
                return;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        panic!("timed out waiting for {}", path.display());
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
            .env("FAKE_LOG_DIR", &self.logs)
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
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// Generic fake: logs `<name>` plus one `ARG ...` line per argv element, drains
/// stdin (so pipeline writers do not block), then reports the FAKE_* env.
pub fn tool_script(name: &str, prefix: &str) -> String {
    format!(
        r#"#!/bin/sh
{{ printf '%s\n' '{name}'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; }} >> "$FAKE_LOG_DIR/{name}.argv"
: > "$FAKE_LOG_DIR/{name}.stdin"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/{name}.stdin"; done
printf '%s' "${{FAKE_{prefix}_OUT-}}"
printf '%s' "${{FAKE_{prefix}_ERR-}}" >&2
exit "${{FAKE_{prefix}_CODE:-0}}"
"#
    )
}

/// `fd` fake that also serves the `--exec du` size call.
pub fn fd_script() -> String {
    r#"#!/bin/sh
{ printf 'fd\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/fd.argv"
: > "$FAKE_LOG_DIR/fd.stdin"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/fd.stdin"; done
exec_mode=0
for a in "$@"; do [ "$a" = "--exec" ] && exec_mode=1; done
if [ "$exec_mode" = 1 ]; then printf '%s' "${FAKE_FD_EXEC_OUT-}"; else printf '%s' "${FAKE_FD_OUT-}"; fi
printf '%s' "${FAKE_FD_ERR-}" >&2
exit "${FAKE_FD_CODE:-0}"
"#
    .to_string()
}

/// `fzf` fake: one output line per invocation from the sequence file given in
/// FAKE_FZF_SEQ_FILE, plus optional FAKE_FZF_EXTRA.
pub fn fzf_script() -> String {
    // Only shell builtins: the fake PATH contains nothing else.
    r#"#!/bin/sh
n=0
if [ -f "$FAKE_LOG_DIR/fzf.count" ]; then read -r n < "$FAKE_LOG_DIR/fzf.count"; fi
n=$((n + 1))
printf '%s' "$n" > "$FAKE_LOG_DIR/fzf.count"
{ printf 'fzf\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/fzf.argv"
: > "$FAKE_LOG_DIR/fzf.stdin.$n"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/fzf.stdin.$n"; done
if [ -n "${FAKE_FZF_SEQ_FILE-}" ]; then
  i=0
  while IFS= read -r line; do
    i=$((i + 1))
    if [ "$i" = "$n" ]; then printf '%s\n' "$line"; fi
  done < "$FAKE_FZF_SEQ_FILE"
fi
printf '%s' "${FAKE_FZF_EXTRA-}"
exit "${FAKE_FZF_CODE:-0}"
"#
    .to_string()
}

/// `playerctl` fake: the `-l` probe and `metadata` answer independently.
pub fn playerctl_script() -> String {
    r#"#!/bin/sh
{ printf 'playerctl\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/playerctl.argv"
if [ "$1" = "-l" ]; then exit "${FAKE_PLAYERCTL_LIST_CODE:-1}"; fi
printf '%s' "${FAKE_PLAYERCTL_OUT-}"
printf '%s' "${FAKE_PLAYERCTL_ERR-}" >&2
exit "${FAKE_PLAYERCTL_CODE:-0}"
"#
    .to_string()
}

/// `xargs` fake used by the background vid-info warm-up: logs argv and the
/// NUL-separated items it would have passed on.
pub fn xargs_script() -> String {
    r#"#!/bin/sh
{ printf 'xargs\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/xargs.argv"
: > "$FAKE_LOG_DIR/xargs.items"
while IFS= read -r -d '' item; do printf 'ITEM %s\n' "$item" >> "$FAKE_LOG_DIR/xargs.items"; done
exit "${FAKE_XARGS_CODE:-0}"
"#
    .to_string()
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

/// The exact `<tool>\nARG ...` log line sequence for a call.
pub fn expected_argv(tool: &str, arguments: &[&str]) -> String {
    let mut log = format!("{tool}\n");
    for argument in arguments {
        log.push_str(&format!("ARG {argument}\n"));
    }
    log
}
