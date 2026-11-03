//! Fixtures for the three binaries and the shell-parity harness.
//!
//! Every case gets its own temporary tree: a fake project (`shells/`, `tests/`,
//! a `flake.nix`), a `bin/` with fake `pleamar`, `pleamar-wm`, `ps`,
//! `systemctl`, `date`, `mktemp`, `sleep`, `setsid`, `timeout`, `grim`,
//! `sway`, `cage`, `column`, `pgrep` and `getconf`, and a `tmp/` used as
//! `PLEAMAR_TMPDIR`. The fakes append their argv to `argv.log`; no real
//! session, network, cgroup or compositor is touched.
//!
//! The scene pid handed to `pleamar hello` is a zombie child of the test, so
//! `/proc/<pid>` exists (the measurement loop keeps running) while its CPU
//! counters stay at zero and `smaps_rollup` is absent — deterministic samples.

#![allow(dead_code)]

use std::env;
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

static NEXT: AtomicU64 = AtomicU64::new(0);

pub const PLEAMAR: &str = r#"#!/bin/sh
line='pleamar'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
if [ "$1" = "--say" ]; then
  case "$3" in
    describe)
      [ -n "${PLEAMAR_SOCKETS:-}" ] && printf '%s\n' "$PLEAMAR_SOCKETS" >> "$FAKE_STATE/sockets"
      # Let a freshly spawned runner reach its own first line (and finish, in
      # the early-exit cases) before the harness decides it is dead.
      perl -e 'select(undef, undef, undef, 0.01)'
      if [ "${4:-}" = "json" ]; then
        if [ "${FAKE_DESCRIBE_JSON_CODE:-0}" != 0 ]; then exit "$FAKE_DESCRIBE_JSON_CODE"; fi
        if [ -n "${FAKE_DESCRIBE_SEQUENCE:-}" ]; then
          n=0
          [ -f "$FAKE_STATE/describe.n" ] && read -r n < "$FAKE_STATE/describe.n"
          n=$((n + 1))
          printf '%s' "$n" > "$FAKE_STATE/describe.n"
          file="$FAKE_DESCRIBE_SEQUENCE/$n.txt"
          [ -f "$file" ] || file="$FAKE_DESCRIBE_SEQUENCE/last.txt"
          cat "$file"
        elif [ -n "${FAKE_DESCRIBE_JSON_FILE:-}" ]; then
          cat "$FAKE_DESCRIBE_JSON_FILE"
        else
          printf '%s\n' "${FAKE_DESCRIBE_JSON:-{\"bar\":1,\"clock\":\"09:51\"}}"
        fi
        exit 0
      fi
      n=0
      [ -f "$FAKE_STATE/plain.n" ] && read -r n < "$FAKE_STATE/plain.n"
      n=$((n + 1))
      printf '%s' "$n" > "$FAKE_STATE/plain.n"
      if [ -n "${FAKE_PLAIN_DESC_FAIL_AFTER:-}" ] && [ "$n" -gt "$FAKE_PLAIN_DESC_FAIL_AFTER" ]; then exit 1; fi
      if [ "${FAKE_DESCRIBE_PLAIN:-1}" != 1 ]; then exit "${FAKE_DESCRIBE_PLAIN_CODE:-1}"; fi
      if [ -n "${FAKE_DESCRIBE_PLAIN_FILE:-}" ]; then cat "$FAKE_DESCRIBE_PLAIN_FILE"; else printf '%s\n' "${FAKE_DESCRIBE_PLAIN_TEXT:-tree}"; fi
      exit 0
      ;;
    hello) printf '%s\n' "${FAKE_HELLO:-id 1 pid 4242}"; exit 0 ;;
    quit) exit "${FAKE_QUIT_CODE:-0}" ;;
    *) exit 0 ;;
  esac
fi
case "$1" in
  --check)
    [ -n "${FAKE_CHECK_OUT:-}" ] && printf '%s' "$FAKE_CHECK_OUT"
    [ -n "${FAKE_CHECK_ERR:-}" ] && printf '%s' "$FAKE_CHECK_ERR" >&2
    exit "${FAKE_CHECK_CODE:-0}"
    ;;
  --report)
    out=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "--out" ] && out=$a
      prev=$a
    done
    [ -n "$out" ] && printf '%s\n' "${FAKE_REPORT_TEXT:-report line}" > "$out"
    exit "${FAKE_REPORT_CODE:-0}"
    ;;
  --scene) exit "${FAKE_SCENE_CODE:-0}" ;;
  *) exit "${FAKE_OTHER_CODE:-0}" ;;
esac
"#;

pub const PLEAMAR_WM: &str = r#"#!/bin/sh
line='pleamar-wm'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
if [ "$1" = "headless" ]; then
  if [ -n "${PLEAMAR_HEADLESS_PNG:-}" ] && [ "${FAKE_WM_PNG_MODE:-valid}" != "none" ]; then
    case "${FAKE_WM_PNG_MODE:-valid}" in
      bad)
        printf 'not a png' > "$PLEAMAR_HEADLESS_PNG"
        pad=$(( ${FAKE_WM_SIZE:-2048} - 9 ))
        [ "$pad" -gt 0 ] && printf '%*s' "$pad" '' | tr ' ' x >> "$PLEAMAR_HEADLESS_PNG"
        ;;
      small)
        printf '\211PNG\r\n\032\n' > "$PLEAMAR_HEADLESS_PNG"
        ;;
      *)
        printf '\211PNG\r\n\032\n' > "$PLEAMAR_HEADLESS_PNG"
        ;;
    esac
    if [ "${FAKE_WM_PNG_MODE:-valid}" = "valid" ]; then
      pad=$(( ${FAKE_WM_SIZE:-2048} - 8 ))
      [ "$pad" -gt 0 ] && printf '%*s' "$pad" '' | tr ' ' x >> "$PLEAMAR_HEADLESS_PNG"
    fi
  fi
  exit "${FAKE_WM_CODE:-0}"
fi
exit 0
"#;

pub const PS: &str = r#"#!/bin/sh
line='ps'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
case "$*" in
  *"-o pgid="*)
    pid=""
    prev=""
    for a in "$@"; do
      [ "$prev" = "-p" ] && pid=$a
      prev=$a
    done
    printf '%s\n' "${FAKE_PGID:-$pid}"
    exit 0
    ;;
  *)
    printf '%s\n' "${FAKE_PS_ROW:-1234 1.5 7}"
    exit "${FAKE_PS_CODE:-0}"
    ;;
esac
"#;

pub const SYSTEMCTL: &str = r#"#!/bin/sh
line='systemctl'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
case "$*" in
  *"-p MainPID --value"*) printf '%s\n' "${FAKE_MAINPID:-}"; exit 0 ;;
  *"-p ControlGroup --value"*) printf '%s\n' "${FAKE_CONTROLGROUP:-}"; exit 0 ;;
  *"is-active --quiet"*) exit "${FAKE_UNIT_ACTIVE:-0}" ;;
  *" stop "*) exit 0 ;;
esac
exit 0
"#;

pub const SYSTEMD_RUN: &str = r#"#!/bin/sh
line='systemd-run'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
exit "${FAKE_SYSTEMD_RUN_CODE:-0}"
"#;

pub const DATE: &str = r#"#!/bin/sh
line='date'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
if [ "$1" = "+%Y-%m-%d" ]; then printf '%s\n' "${FAKE_DATE:-2026-01-02}"; exit 0; fi
if [ "$1" = "+%s.%N" ]; then
  n=0
  [ -f "$FAKE_STATE/date.n" ] && read -r n < "$FAKE_STATE/date.n"
  n=$((n + 1))
  printf '%s' "$n" > "$FAKE_STATE/date.n"
  printf '%s.000000\n' "$((1000 + n))"
  exit 0
fi
exit 0
"#;

pub const MKTEMP: &str = r#"#!/bin/sh
line='mktemp'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
template=$2
base=${template%XXXXXX}
n=0
[ -f "$FAKE_STATE/mktemp.n" ] && read -r n < "$FAKE_STATE/mktemp.n"
n=$((n + 1))
printf '%s' "$n" > "$FAKE_STATE/mktemp.n"
dir="$base$n"
mkdir -p "$dir" || exit 1
printf '%s\n' "$dir"
"#;

pub const SLEEP: &str = r#"#!/bin/sh
line='sleep'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
# A short real pause: the scripts park in a poll loop, and the fake runner
# needs a chance to exit so the liveness branch is reachable deterministically.
perl -e 'select(undef, undef, undef, 0.002)'
exit 0
"#;

pub const SETSID: &str = r#"#!/bin/sh
line='setsid'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
# A real session (and process group) of its own, then the command, so the
# harness's process-group TERM/KILL reaches the whole fake runner.
exec perl -MPOSIX -e 'POSIX::setsid(); exec { $ARGV[0] } @ARGV; die "exec: $!"' "$@"
"#;

pub const TIMEOUT: &str = r#"#!/bin/sh
line='timeout'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
if [ "$1" = "-k" ]; then shift 2; fi
shift
exec "$@"
"#;

pub const GRIM: &str = r#"#!/bin/sh
line='grim'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
for last in "$@"; do :; done
printf '\211PNG\r\n\032\n' > "$last"
pad=$(( ${FAKE_GRIM_SIZE:-2048} - 8 ))
[ "$pad" -gt 0 ] && printf '%*s' "$pad" '' | tr ' ' x >> "$last"
exit "${FAKE_GRIM_CODE:-0}"
"#;

pub const COLUMN: &str = r#"#!/bin/sh
line='column'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
for last in "$@"; do :; done
cat "$last"
"#;

pub const GETCONF: &str = r#"#!/bin/sh
printf '100\n'
"#;

pub const PGREP: &str = r#"#!/bin/sh
line='pgrep'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
[ -n "${FAKE_PGREP_PIDS:-}" ] && printf '%s\n' "$FAKE_PGREP_PIDS"
exit 0
"#;

pub const SWAY: &str = r#"#!/bin/sh
line='sway'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
sock="$XDG_RUNTIME_DIR/wayland-${FAKE_WAYLAND_N:-1}"
perl -MIO::Socket::UNIX -e '$s=IO::Socket::UNIX->new(Local=>$ARGV[0],Listen=>1) or die $!; sleep 100' "$sock" &
child=$!
trap 'kill $child 2>/dev/null; exit 0' TERM INT
wait "$child"
"#;

pub const CAGE: &str = r#"#!/bin/sh
line='cage'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
sock="$XDG_RUNTIME_DIR/wayland-${FAKE_WAYLAND_N:-1}"
perl -MIO::Socket::UNIX -e '$s=IO::Socket::UNIX->new(Local=>$ARGV[0],Listen=>1) or die $!; sleep 100' "$sock" &
listener=$!
# Give the harness's socket watcher time to see it before the fake scene ends.
perl -e 'select(undef, undef, undef, 0.3)'
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
[ "$1" = "--" ] && shift
"$@"
rc=$?
kill "$listener" 2>/dev/null
wait "$listener" 2>/dev/null
exit "$rc"
"#;

pub struct Case {
    pub dir: PathBuf,
    pub project: PathBuf,
    pub bin: PathBuf,
    pub tools: PathBuf,
    pub tmp: PathBuf,
    pub runtime: PathBuf,
    pub state: PathBuf,
    pub log: PathBuf,
    pub home: PathBuf,
    pub program: PathBuf,
    zombie: Option<Child>,
    pub zombie_pid: u32,
    envs: Vec<(String, String)>,
}

impl Case {
    pub fn measure(label: &str) -> Self {
        Self::new(label, "pleamar-measure", "measure")
    }

    pub fn describe_snap(label: &str) -> Self {
        Self::new(label, "pleamar-describe-snap", "describe-snap")
    }

    pub fn smoke(label: &str) -> Self {
        Self::new(label, "pleamar-smoke", "smoke")
    }

    pub fn rig(label: &str) -> Self {
        Self::new(label, "pleamar-rig", "rig")
    }

    fn new(label: &str, program: &str, tool: &str) -> Self {
        let dir = env::temp_dir().join(format!(
            "pleamar-harness-{}-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            tool,
            label
        ));
        let _ = fs::remove_dir_all(&dir);
        let project = dir.join("project");
        let bin = dir.join("bin");
        let tools = dir.join("tools");
        let tmp = dir.join("tmp");
        let runtime = dir.join("runtime");
        let state = dir.join("state");
        let home = dir.join("home");
        for path in [
            &project.join("shells"),
            &project.join("tests"),
            &bin,
            &tools,
            &tmp,
            &runtime,
            &state,
            &home,
        ] {
            fs::create_dir_all(path).expect("create fixture directory");
        }
        fs::write(project.join("flake.nix"), b"{}\n").expect("write fixture flake");
        let log = dir.join("argv.log");
        fs::write(&log, b"").expect("create argv log");
        let mut case = Self {
            dir: dir.clone(),
            project,
            bin,
            tools,
            tmp,
            runtime,
            state,
            log,
            home,
            program: PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../target")
                .join("debug")
                .join(program),
            zombie: None,
            zombie_pid: 0,
            envs: Vec::new(),
        };
        case.link_host_tools();
        // The binary under test is the one cargo built for this test run.
        case.program = PathBuf::from(match program {
            "pleamar-measure" => env!("CARGO_BIN_EXE_pleamar-measure"),
            "pleamar-describe-snap" => env!("CARGO_BIN_EXE_pleamar-describe-snap"),
            "pleamar-smoke" => env!("CARGO_BIN_EXE_pleamar-smoke"),
            "pleamar-rig" => env!("CARGO_BIN_EXE_pleamar-rig"),
            other => panic!("unknown binary {other}"),
        });
        case.install_fakes();
        case.make_zombie();
        case.base_envs(tool);
        case.scene("bar", "zone bar\n");
        case
    }

    /// The standard tools the fakes and the original scripts use, symlinked
    /// into a private directory so the host's `pleamar`, `grim`, `sway` or
    /// `systemctl` can never leak into a test through `PATH`.
    fn link_host_tools(&self) {
        for name in [
            "basename", "bash", "cat", "chmod", "cmp", "cp", "diff", "dirname", "env", "find",
            "gawk", "grep", "head", "id", "jq", "kill", "mkdir", "mv", "od", "perl", "rm", "sed",
            "sh", "sort", "tail", "tr", "wc",
        ] {
            if let Some(path) = host_tool(name) {
                let _ = symlink(path, self.tools.join(name));
            }
        }
        // `awk` is often a gawk symlink; keep the name the scripts call.
        if !self.tools.join("awk").exists() {
            if let Some(path) = self.tools.join("gawk").canonicalize().ok() {
                let _ = symlink(path, self.tools.join("awk"));
            }
        }
    }

    fn install_fakes(&self) {
        for (name, body) in [
            ("pleamar", PLEAMAR),
            ("pleamar-wm", PLEAMAR_WM),
            ("ps", PS),
            ("systemctl", SYSTEMCTL),
            ("systemd-run", SYSTEMD_RUN),
            ("date", DATE),
            ("mktemp", MKTEMP),
            ("sleep", SLEEP),
            ("setsid", SETSID),
            ("timeout", TIMEOUT),
            ("grim", GRIM),
            ("column", COLUMN),
            ("getconf", GETCONF),
            ("pgrep", PGREP),
            ("sway", SWAY),
            ("cage", CAGE),
        ] {
            self.fake(name, body);
        }
    }

    fn make_zombie(&mut self) {
        // A child that has exited but is not reaped yet: /proc/<pid> exists,
        // its stat counters are frozen and there is no smaps_rollup.
        let child = Command::new("sh")
            .arg("-c")
            .arg("exit 0")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn zombie child");
        let pid = child.id();
        let deadline = Instant::now() + Duration::from_secs(2);
        while Instant::now() < deadline {
            if let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) {
                if stat
                    .rsplit(')')
                    .next()
                    .map_or(false, |rest| rest.trim_start().starts_with('Z'))
                {
                    break;
                }
            }
            std::thread::sleep(Duration::from_millis(5));
        }
        self.zombie_pid = pid;
        self.zombie = Some(child);
    }

    fn base_envs(&mut self, tool: &str) {
        let path = format!("{}:{}", self.bin.display(), self.tools.display());
        let values = [
            ("PATH", path),
            ("LC_ALL", "C.utf8".to_string()),
            ("LANG", "C.utf8".to_string()),
            ("HOME", self.home.display().to_string()),
            ("TMPDIR", self.tmp.display().to_string()),
            ("PLEAMAR_TMPDIR", self.tmp.display().to_string()),
            ("PLEAMAR_ROOT", self.project.display().to_string()),
            ("XDG_RUNTIME_DIR", self.runtime.display().to_string()),
            ("FAKE_LOG", self.log.display().to_string()),
            ("FAKE_STATE", self.state.display().to_string()),
            ("FAKE_SCENE_PID", self.zombie_pid.to_string()),
            ("FAKE_HELLO", format!("id 1 pid {}", self.zombie_pid)),
            ("PLEAMAR_BIN", "pleamar".to_string()),
            ("PLEAMAR_WM_BIN", "pleamar-wm".to_string()),
            ("FAKE_TOOL", tool.to_string()),
        ];
        self.envs = values
            .into_iter()
            .map(|(key, value)| (key.to_string(), value))
            .collect();
    }

    pub fn fake(&self, name: &str, body: &str) {
        write_executable(&self.bin.join(name), body);
    }

    pub fn remove_fake(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    pub fn scene(&self, name: &str, body: &str) {
        let directory = self.project.join("shells").join(name);
        fs::create_dir_all(&directory).expect("create scene directory");
        fs::write(directory.join(format!("{name}.plm")), body).expect("write scene");
    }

    pub fn raw_scene(&self, relative: &str, body: &str) {
        let path = self.project.join(relative);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create scene dir");
        }
        fs::write(path, body).expect("write scene");
    }

    pub fn snapshot(&self, name: &str, body: &str) {
        fs::write(
            self.project
                .join("tests")
                .join(format!("{name}.describe.txt")),
            body,
        )
        .expect("write snapshot");
    }

    pub fn snapshot_path(&self, name: &str) -> PathBuf {
        self.project
            .join("tests")
            .join(format!("{name}.describe.txt"))
    }

    pub fn set(&mut self, key: &str, value: &str) {
        self.envs.retain(|(existing, _)| existing != key);
        self.envs.push((key.to_string(), value.to_string()));
    }

    pub fn unset(&mut self, key: &str) {
        self.envs.retain(|(existing, _)| existing != key);
    }

    pub fn envs(&self) -> Vec<(String, String)> {
        self.envs.clone()
    }

    fn command(&self, program: &Path) -> Command {
        let mut command = Command::new(program);
        command.env_clear();
        for (key, value) in &self.envs {
            command.env(key, value);
        }
        command
    }

    pub fn run(&self, args: &[&str]) -> Output {
        self.run_with(args, &[])
    }

    pub fn run_with(&self, args: &[&str], extra: &[(&str, &str)]) -> Output {
        let mut command = self.command(&self.program);
        command.args(args);
        for (key, value) in extra {
            command.env(key, value);
        }
        command.output().expect("run the harness binary")
    }

    /// Run a copy of the original shell script (used by the parity harness).
    pub fn run_shell(&self, script: &Path, args: &[&str], extra: &[(&str, &str)]) -> Output {
        let bash = host_tool("bash").expect("bash is needed by the parity harness");
        let mut command = self.command(&bash);
        command.arg(script).args(args).current_dir(&self.project);
        for (key, value) in extra {
            command.env(key, value);
        }
        command.output().expect("run the original shell script")
    }

    /// Run the ported binary in a chosen cwd, optionally without
    /// `PLEAMAR_ROOT`, for the repository-root resolution tests.
    pub fn run_at(
        &self,
        cwd: &Path,
        args: &[&str],
        extra: &[(&str, &str)],
        without_root: bool,
    ) -> Output {
        let mut command = self.command(&self.program);
        command.args(args).current_dir(cwd);
        if without_root {
            command.env_remove("PLEAMAR_ROOT");
        }
        for (key, value) in extra {
            command.env(key, value);
        }
        command.output().expect("run the harness binary")
    }

    pub fn run_rust(&self, args: &[&str], extra: &[(&str, &str)]) -> Output {
        let mut command = self.command(&self.program);
        command.args(args).current_dir(&self.project);
        for (key, value) in extra {
            command.env(key, value);
        }
        command.output().expect("run the ported binary")
    }

    pub fn log(&self) -> String {
        fs::read_to_string(&self.log).unwrap_or_default()
    }

    pub fn calls(&self) -> Vec<String> {
        self.log().lines().map(str::to_string).collect()
    }

    pub fn calls_of(&self, program: &str) -> Vec<String> {
        self.calls()
            .into_iter()
            .filter(|line| line.split_whitespace().next() == Some(program))
            .collect()
    }

    pub fn read(&self, relative: &str) -> String {
        fs::read_to_string(self.project.join(relative)).unwrap_or_default()
    }

    pub fn exists(&self, relative: &str) -> bool {
        self.project.join(relative).exists()
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        if let Some(mut child) = self.zombie.take() {
            let _ = child.wait();
        }
        let _ = fs::remove_dir_all(&self.dir);
    }
}

pub fn write_executable(path: &Path, body: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create executable directory");
    }
    fs::write(path, body).expect("write executable");
    let mut permissions = fs::metadata(path).expect("stat executable").permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(path, permissions).expect("chmod executable");
}

/// Symlink a host tool into the fake bin dir when it is needed by a script that
/// the port does not reimplement (the fakes themselves use `sh`, `cat`, ...).
pub fn host_tool(name: &str) -> Option<PathBuf> {
    let path = env::var_os("PATH")?;
    for directory in env::split_paths(&path) {
        let candidate = directory.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

/// Symlink `name` beside the fakes so the caller can add host tools to one
/// case without depending on the test process's PATH.
pub fn link_tool(case: &Case, name: &str) {
    if let Some(path) = host_tool(name) {
        let _ = symlink(path, case.bin.join(name));
    }
}

pub fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}
