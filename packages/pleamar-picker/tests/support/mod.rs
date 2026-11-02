//! Fixtures for the three binaries' integration tests.
//!
//! Every case gets its own temporary tree: `home/`, `cache/` (XDG_CACHE_HOME),
//! `tmp/` (TMPDIR), `media/` for wallpapers, `helpers/` holding copies of this
//! crate's binaries (so `pleamar-wallpaper-apply` finds its still helper
//! beside itself, as the shell's `dirname "$0"` did), and `bin/` for the fake
//! external tools. The fakes append their argv to `argv.log`; the environment
//! is explicit, so nothing reads the host's HOME, XDG trees or PLEAMAR /
//! SYSTEMCTL variables.

#![allow(dead_code)]

use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime};

static NEXT: AtomicU64 = AtomicU64::new(0);

/// The standard fake pleamar. The deck's `open` fact lives in a small state
/// file (`FAKE_DECK_FILE`), `emit toggle_picker` closes or opens it according
/// to `FAKE_TOGGLE_CLOSES` / `FAKE_TOGGLE_OPENS`, and the start path's
/// `emit open_picker` succeeds from the `FAKE_OPEN_AFTER`-th call on. Every
/// call is logged with bracketed arguments, so a space inside `get open`
/// stays visible. Only shell builtins are used, so the tests need no host
/// command except the picker's own `tail`.
pub const PLEAMAR: &str = r#"#!/bin/sh
printf 'pleamar' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
case "$*" in
  "--say picker get open")
    if [ -f "$FAKE_DECK_FILE" ]; then
      read -r open < "$FAKE_DECK_FILE"
    else
      open=${FAKE_OPEN_VALUE:-true}
    fi
    printf '%s\n' "$open"
    ;;
  "--say picker emit toggle_picker")
    code=${FAKE_TOGGLE_CODE:-0}
    if [ "$code" = 0 ]; then
      if [ "${FAKE_TOGGLE_CLOSES:-0}" = 1 ]; then printf 'false' > "$FAKE_DECK_FILE"; fi
      if [ "${FAKE_TOGGLE_OPENS:-0}" = 1 ]; then printf 'true' > "$FAKE_DECK_FILE"; fi
    fi
    exit "$code"
    ;;
  "--say picker emit open_picker")
    n=0
    if [ -f "$FAKE_COUNTER" ]; then read -r n < "$FAKE_COUNTER"; fi
    n=$((n + 1))
    printf '%s' "$n" > "$FAKE_COUNTER"
    if [ "$n" -ge "${FAKE_OPEN_AFTER:-1}" ]; then exit 0; else exit "${FAKE_OPEN_FAIL_CODE:-1}"; fi
    ;;
  "--say picker emit close_picker") exit "${FAKE_CLOSE_CODE:-0}" ;;
  "--say picker emit reload") exit "${FAKE_RELOAD_CODE:-0}" ;;
  *) exit "${FAKE_OTHER_CODE:-0}" ;;
esac
"#;

/// The standard fake systemctl; start/stop exit codes are configurable.
pub const SYSTEMCTL: &str = r#"#!/bin/sh
printf 'systemctl' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
case "$1 $2" in
  "--user start") exit "${FAKE_START_CODE:-0}" ;;
  "--user stop") exit "${FAKE_STOP_CODE:-0}" ;;
  *) exit 0 ;;
esac
"#;

/// The timing loop's sleep, logged and instant.
pub const SLEEP: &str = r#"#!/bin/sh
printf 'sleep' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
exit 0
"#;

/// setsid: logs the detached command and does not run it, so the wallpaper
/// command string is observable byte for byte.
pub const SETSID: &str = r#"#!/bin/sh
printf 'setsid' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
exit "${FAKE_SETSID_CODE:-0}"
"#;

/// nice: logs the matugen argv and swallows its execution.
pub const NICE: &str = r#"#!/bin/sh
printf 'nice' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
exit "${FAKE_NICE_CODE:-0}"
"#;

/// matugen only has to exist for `command -v`; `nice` is what runs it.
pub const MATUGEN: &str = "#!/bin/sh\nexit 0\n";

/// ffmpeg writes `FAKE_FFMPEG_DATA` to its last argument and exits
/// `FAKE_FFMPEG_CODE`; `-ss` value and the output path go into the log as
/// two separate values the tests can inspect.
pub const FFMPEG: &str = r#"#!/bin/sh
printf 'ffmpeg' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
for last; do :; done
printf '%s' "${FAKE_FFMPEG_DATA:-JPEG}" > "$last"
exit "${FAKE_FFMPEG_CODE:-0}"
"#;

pub struct Case {
    pub dir: PathBuf,
    pub bin: PathBuf,
    pub tools: PathBuf,
    pub home: PathBuf,
    pub cache: PathBuf,
    pub helpers: PathBuf,
    pub media: PathBuf,
    pub log: PathBuf,
    program: PathBuf,
}

impl Case {
    pub fn still(label: &str) -> Self {
        Self::new(label, "pleamar-wallpaper-still", false)
    }

    pub fn apply(label: &str) -> Self {
        Self::new(label, "pleamar-wallpaper-apply", true)
    }

    pub fn picker(label: &str) -> Self {
        Self::new(label, "pleamar-picker", false)
    }

    fn new(label: &str, name: &str, with_still: bool) -> Self {
        let dir = std::env::temp_dir().join(format!(
            "pleamar-picker-test-{}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed),
            label
        ));
        let _ = fs::remove_dir_all(&dir);
        let bin = dir.join("bin");
        let home = dir.join("home");
        let cache = dir.join("cache");
        let helpers = dir.join("helpers");
        let media = dir.join("media");
        for path in [&bin, &home, &cache, &helpers, &media, &dir.join("tmp")] {
            fs::create_dir_all(path).expect("create fixture directory");
        }
        // The only host programs the port itself runs in these tests: the
        // picker's `tail -n 1` pipeline. Everything else is faked.
        let tools = dir.join("tools");
        fs::create_dir_all(&tools).expect("create tools directory");
        if let Some(tail) = host_tool("tail") {
            symlink(tail, tools.join("tail")).expect("link host tail");
        }
        let source = match name {
            "pleamar-wallpaper-still" => env!("CARGO_BIN_EXE_pleamar-wallpaper-still"),
            "pleamar-wallpaper-apply" => env!("CARGO_BIN_EXE_pleamar-wallpaper-apply"),
            "pleamar-picker" => env!("CARGO_BIN_EXE_pleamar-picker"),
            other => panic!("unknown binary {other}"),
        };
        let program = helpers.join(name);
        link_executable(Path::new(source), &program);
        if with_still {
            link_executable(
                Path::new(env!("CARGO_BIN_EXE_pleamar-wallpaper-still")),
                &helpers.join("pleamar-wallpaper-still"),
            );
        }
        let log = dir.join("argv.log");
        fs::write(&log, b"").expect("create argv log");
        Self {
            dir,
            bin,
            tools,
            home,
            cache,
            helpers,
            media,
            log,
            program,
        }
    }

    /// Install an executable fake into `bin/`.
    pub fn fake(&self, name: &str, body: &str) {
        write_executable(&self.bin.join(name), body);
    }

    /// An executable helper beside the command's own binary (the apply
    /// binary's still lookup, including the legacy `wallpaper-still` name).
    pub fn fake_helper(&self, name: &str, body: &str) {
        write_executable(&self.helpers.join(name), body);
    }

    /// Replace the still helper beside the apply binary.
    pub fn fake_still(&self, body: &str) {
        self.fake_helper("pleamar-wallpaper-still", body);
    }

    pub fn remove_still_helper(&self) {
        let _ = fs::remove_file(self.helpers.join("pleamar-wallpaper-still"));
    }

    pub fn remove_fake(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    pub fn write(&self, path: &Path, contents: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent");
        }
        fs::write(path, contents).expect("write fixture file");
    }

    pub fn media_file(&self, name: &str, contents: &[u8]) -> PathBuf {
        let path = self.media.join(name);
        self.write(&path, contents);
        path
    }

    pub fn log(&self) -> String {
        fs::read_to_string(&self.log).unwrap_or_default()
    }

    pub fn reset_log(&self) {
        fs::write(&self.log, b"").expect("truncate argv log");
    }

    /// The fake deck's `get open` answer, as the state file knows it.
    pub fn set_deck_open(&self, open: &str) {
        fs::write(self.dir.join("deck-open"), open).expect("write deck state");
    }

    pub fn path(&self) -> OsString {
        std::env::join_paths([self.bin.clone(), self.tools.clone()]).expect("join PATH")
    }

    pub fn isolated_path(&self) -> OsString {
        self.bin.clone().into_os_string()
    }

    pub fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command
            .current_dir(&self.dir)
            .env("HOME", &self.home)
            .env("XDG_CACHE_HOME", &self.cache)
            .env("TMPDIR", self.dir.join("tmp"))
            .env("PATH", self.path())
            .env("FAKE_LOG", &self.log)
            .env("FAKE_DECK_FILE", self.dir.join("deck-open"))
            .env("FAKE_COUNTER", self.dir.join("counter"))
            .env_remove("PLEAMAR")
            .env_remove("SYSTEMCTL")
            .env_remove("MATUGEN")
            .env_remove("WALLPAPER_STILL")
            .stdin(Stdio::null());
        command
    }

    pub fn run(&self, arguments: &[&str]) -> Output {
        output(self.command().args(arguments))
    }

    pub fn run_os(&self, arguments: &[OsString]) -> Output {
        output(self.command().args(arguments))
    }

    pub fn run_with(&self, variables: &[(&str, &str)], arguments: &[&str]) -> Output {
        let mut command = self.command();
        for (name, value) in variables {
            command.env(name, value);
        }
        output(command.args(arguments))
    }

    pub fn run_isolated(&self, arguments: &[&str]) -> Output {
        output(
            self.command()
                .env("PATH", self.isolated_path())
                .args(arguments),
        )
    }

    /// A file created with the same process umask as the commands' cache
    /// files, so modes can be compared without assuming 022.
    pub fn reference_file(&self) -> PathBuf {
        let path = self.dir.join("reference-file");
        fs::write(&path, b"reference").expect("write reference file");
        path
    }

    /// Set a file's modification time, seconds since the epoch.
    pub fn set_mtime(&self, path: &Path, seconds: u64) {
        let file = fs::File::options()
            .write(true)
            .open(path)
            .expect("open fixture file");
        file.set_modified(SystemTime::UNIX_EPOCH + Duration::from_secs(seconds))
            .expect("set modification time");
    }

    pub fn cache_path(&self) -> PathBuf {
        self.cache.join("pleamar").join("wallpaper-path")
    }

    pub fn frame_dir(&self) -> PathBuf {
        self.cache.join("pleamar").join("wallpaper-frames")
    }

    pub fn new_symlink(&self, target: &Path, link: &Path) {
        symlink(target, link).expect("create fixture symlink");
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

fn write_executable(path: &Path, body: &str) {
    // A previous fixture may have left a symlink (the copied binaries are
    // links now); never follow it into the target binary.
    let _ = fs::remove_file(path);
    fs::write(path, body).expect("write fake executable");
    let mut permissions = fs::metadata(path).expect("stat fake").permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(path, permissions).expect("chmod fake");
}

/// A program from the host's PATH, for the `tools/` link farm.
fn host_tool(name: &str) -> Option<PathBuf> {
    for directory in std::env::split_paths(&std::env::var_os("PATH")?) {
        let candidate = directory.join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

fn link_executable(source: &Path, target: &Path) {
    let _ = fs::remove_file(target);
    symlink(source, target).expect("link fixture binary");
}

/// Run a command, retrying the one transient failure this test layout can
/// produce: another case's fork inherits this case's just-written executable
/// for a moment, and execve answers ETXTBSY. The window is a few microseconds;
/// a short retry keeps the suite deterministic. No production code does this.
pub fn output(command: &mut Command) -> Output {
    const ETXTBSY: i32 = 26;
    for _ in 0..100 {
        match command.output() {
            Ok(output) => return output,
            Err(error) if error.raw_os_error() == Some(ETXTBSY) => {
                std::thread::sleep(Duration::from_millis(2));
            }
            Err(error) => panic!("run fixture binary: {error}"),
        }
    }
    panic!("run fixture binary: ETXTBSY persisted");
}

/// Let a builder chain end in a helper, e.g.
/// `case.command().env_remove(...).args([...]).pipe_through(support::output)`.
pub trait PipeThrough {
    fn pipe_through(self, run: fn(&mut Command) -> Output) -> Output;
}

impl PipeThrough for &mut Command {
    fn pipe_through(self, run: fn(&mut Command) -> Output) -> Output {
        run(self)
    }
}

pub fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("stdout is UTF-8")
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("stderr is UTF-8")
}

pub fn mode(path: &Path) -> u32 {
    fs::symlink_metadata(path)
        .expect("stat path")
        .permissions()
        .mode()
        & 0o7777
}

pub fn read(path: &Path) -> String {
    fs::read_to_string(path).expect("read path")
}

/// The target of a symlink, as a display string.
pub fn link_target(path: &Path) -> String {
    fs::read_link(path)
        .expect("read symlink")
        .display()
        .to_string()
}
