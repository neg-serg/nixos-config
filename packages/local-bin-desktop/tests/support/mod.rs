//! Hermetic test support: a temporary world, fake external tools that log their
//! argv, and a runner that executes a port with a cleared environment.
//!
//! Every fake is a shell script first on `PATH`; the shell is the one the build
//! passes in `LOCAL_BIN_DESKTOP_TEST_SHELL` (a build sandbox may not have
//! `/bin/sh`). `HOME`, `TMPDIR` and `XDG_RUNTIME_DIR` point into the sandbox, so
//! nothing touches the real user's files, clipboard or notifications.
//!
//! The fakes are byte-identical in spirit to `tests/parity.sh`: they read
//! `FAKE_*` environment variables for their behaviour and append their argv to
//! `FAKE_LOG` as `tool \x1e arg... \x1e \x1e` records.

#![allow(dead_code)]

use std::ffi::OsStr;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct Sandbox {
    pub root: PathBuf,
    pub home: PathBuf,
    pub tmp: PathBuf,
    pub run_dir: PathBuf,
    pub case: PathBuf,
    pub bin: PathBuf,
    pub log: PathBuf,
    pub clip: PathBuf,
    pub notify: PathBuf,
    pub dispatch: PathBuf,
    pub eval: PathBuf,
    pub expect_stdin: PathBuf,
    pub expect_env: PathBuf,
    pub vicinae_in: PathBuf,
    pub wl_log: PathBuf,
    pub ytdlp: PathBuf,
    pub wfrec_pid: PathBuf,
    pub inotify: PathBuf,
    pub wl_counter: PathBuf,
    pub bc_log: PathBuf,
    pub mktemp_out: PathBuf,
    pub user: String,
    shell: PathBuf,
}

pub struct Outcome {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl Sandbox {
    pub fn new(label: &str) -> Sandbox {
        let counter = COUNTER.fetch_add(1, Ordering::SeqCst);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.subsec_nanos())
            .unwrap_or(0);
        let root = std::env::temp_dir().join(format!(
            "local-bin-desktop-test-{}-{}-{}-{}",
            std::process::id(),
            counter,
            nanos,
            label
        ));
        let sandbox = Sandbox {
            home: root.join("home"),
            tmp: root.join("tmp"),
            run_dir: root.join("run"),
            case: root.join("case"),
            bin: root.join("bin"),
            log: root.join("fake.log"),
            clip: root.join("clip.bin"),
            notify: root.join("notify.bin"),
            dispatch: root.join("dispatch.bin"),
            eval: root.join("eval.txt"),
            expect_stdin: root.join("expect.stdin"),
            expect_env: root.join("expect.env"),
            vicinae_in: root.join("vicinae.stdin"),
            wl_log: root.join("wl.log"),
            ytdlp: root.join("ytdlp.state"),
            wfrec_pid: root.join("wfrec.pid"),
            inotify: root.join("inotify.txt"),
            wl_counter: root.join("wl.counter"),
            bc_log: root.join("bc.log"),
            mktemp_out: root.join("tmp").join("capture.png"),
            user: format!("lbd-{}-{}", std::process::id(), counter),
            shell: PathBuf::from(
                std::env::var("LOCAL_BIN_DESKTOP_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into()),
            ),
            root,
        };
        sandbox.reset();
        sandbox
    }

    /// Remove and recreate the mutable world (home, tmp, run, case) and clear
    /// the fake state files. The fakes themselves stay installed.
    pub fn reset(&self) {
        for directory in [&self.home, &self.tmp, &self.run_dir, &self.case, &self.bin] {
            let _ = fs::remove_dir_all(directory);
            fs::create_dir_all(directory).expect("create sandbox directory");
        }
        for file in [
            &self.log,
            &self.clip,
            &self.notify,
            &self.dispatch,
            &self.eval,
            &self.expect_stdin,
            &self.expect_env,
            &self.vicinae_in,
            &self.wl_log,
            &self.ytdlp,
            &self.inotify,
            &self.wl_counter,
            &self.bc_log,
        ] {
            fs::write(file, b"").expect("truncate fake state");
        }
        let _ = fs::remove_file(&self.wfrec_pid);
        let _ = fs::remove_file(&self.mktemp_out);
    }

    /// Write an executable fake tool: logging prelude, then `body`.
    pub fn fake(&self, name: &str, body: &str) {
        let mut text = String::new();
        text.push_str(&format!("#!{}\n", self.shell.display()));
        text.push_str("if [ -n \"${FAKE_LOG:-}\" ]; then\n");
        text.push_str(&format!(
            "  printf '%s\\036' '{name}' \"$@\" >> \"$FAKE_LOG\"; printf '\\037' >> \"$FAKE_LOG\"\n"
        ));
        text.push_str("fi\n");
        text.push_str(body);
        if !body.ends_with('\n') {
            text.push('\n');
        }
        self.fake_raw(name, text.as_bytes());
    }

    /// Write an executable file without the logging prelude.
    pub fn fake_raw(&self, name: &str, contents: &[u8]) {
        let path = self.bin.join(name);
        fs::write(&path, contents).expect("write fake");
        let mut permissions = fs::metadata(&path).expect("stat fake").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("chmod fake");
    }

    /// Replace the instant `sleep` fake with the host's real sleep binary, for
    /// the liveness window of screenrec.
    pub fn install_real_sleep(&self) -> bool {
        let candidate = std::env::var_os("LOCAL_BIN_DESKTOP_TEST_SLEEP")
            .map(PathBuf::from)
            .filter(|path| path.is_file());
        let candidate = candidate.or_else(|| {
            std::env::var_os("PATH").and_then(|path| {
                std::env::split_paths(&path)
                    .map(|directory| directory.join("sleep"))
                    .find(|path| path.is_file())
            })
        });
        let Some(source) = candidate else {
            return false;
        };
        fs::copy(&source, self.bin.join("sleep")).is_ok()
    }

    /// A `sh` that logs and then behaves like the real shell, for `clip`'s
    /// transform step.
    pub fn install_shell(&self) -> bool {
        self.fake("sh", &format!("exec \"{}\" \"$@\"\n", self.shell.display()));
        self.bin.join("sh").is_file()
    }

    /// Copy a host binary into the fake directory. The fakes themselves need
    /// `cat` to move stdin around byte-exactly, and `clip` needs a real `sh`.
    pub fn install_real_tool(&self, name: &str) -> bool {
        let Some(source) = std::env::var_os("PATH").and_then(|path| {
            std::env::split_paths(&path)
                .map(|directory| directory.join(name))
                .find(|candidate| candidate.is_file())
        }) else {
            return false;
        };
        fs::copy(&source, self.bin.join(name)).is_ok()
    }

    pub fn install_default_fakes(&self) {
        // The fakes use `cat` to pass stdin/stdout bytes around; the port under
        // test only ever sees the fake directory on PATH.
        if !self.install_real_tool("cat") {
            panic!("test environment needs a real `cat` in PATH");
        }
        // `clip` runs the user's transform through `sh -c`.
        self.install_shell();
        self.fake(
            "sleep",
            "if [ \"${FAKE_SLEEP_REAL:-0}\" = 1 ]; then exec \"${FAKE_SLEEP_BIN:-sleep}\" \"$@\"; fi\nexit 0\n",
        );
        self.fake("timeout", "shift\nexec \"$@\"\n");
        self.fake("date", "printf '%s\\n' \"${FAKE_DATE_OUT:?}\"\n");
        self.fake(
            "identify",
            "printf '%s' \"${FAKE_IDENTIFY_OUT-1920 1080 8 srgba 4.0}\"\nexit \"${FAKE_IDENTIFY_EXIT-0}\"\n",
        );
        self.fake(
            "wl-copy",
            "cat >> \"${FAKE_CLIP_FILE:?}\"\nprintf '\\037' >> \"${FAKE_CLIP_FILE:?}\"\n",
        );
        self.fake(
            "wl-paste",
            "printf '%s' \"${FAKE_WLPASTE-}\"\nexit \"${FAKE_WLPASTE_EXIT-0}\"\n",
        );
        self.fake(
            "notify-send",
            "printf '%s\\036' \"$@\" >> \"${FAKE_NOTIFY_FILE:?}\"\nprintf '\\037' >> \"${FAKE_NOTIFY_FILE:?}\"\nexit \"${FAKE_NOTIFY_EXIT-0}\"\n",
        );
        self.fake("pleamar", "exit \"${FAKE_PLEAMAR_EXIT-1}\"\n");
        self.fake("quickshell", "exit \"${FAKE_QUICKSHELL_EXIT-1}\"\n");
        self.fake(
            "hyprctl",
            r#"case "$1" in
  activewindow)
    printf '%s' "${FAKE_ACTIVEWINDOW-}"
    exit "${FAKE_HYPRCTL_AW_EXIT-0}" ;;
  monitors)
    printf '%s' "${FAKE_MONITORS-}"
    exit "${FAKE_HYPRCTL_MON_EXIT-0}" ;;
  -j)
    case "$2" in
      getoption) printf '%s' "${FAKE_GETOPTION-}" ;;
      monitors) printf '%s' "${FAKE_MONITORS-}" ;;
    esac ;;
  eval)
    printf '%s' "$2" > "${FAKE_EVAL_FILE:-/dev/null}"
    exit "${FAKE_HYPRCTL_EVAL_EXIT-0}" ;;
  dispatch)
    printf '%s\036' "$@" >> "${FAKE_DISPATCH_FILE:?}"
    printf '\037' >> "${FAKE_DISPATCH_FILE:?}"
    exit "${FAKE_HYPRCTL_DISPATCH_EXIT-0}" ;;
esac
exit 0
"#,
        );
        self.fake(
            "kitten",
            "case \"$*\" in\n  *set-user-vars) printf '%s' \"${FAKE_KITTEN_VARS-}\" ;;\nesac\nexit 0\n",
        );
        self.fake("oxipng", "exit \"${FAKE_OXIPNG_EXIT-0}\"\n");
        self.fake(
            "tesseract",
            "printf '%s' \"${FAKE_TESSERACT_OUT-}\"\nexit \"${FAKE_TESSERACT_EXIT-0}\"\n",
        );
        self.fake(
            "magick",
            "printf '%s' \"${FAKE_MAGICK_OUT-}\"\nexit \"${FAKE_MAGICK_EXIT-0}\"\n",
        );
        self.fake(
            "curl",
            "printf '%s' \"${FAKE_CURL_OUT-}\"\nexit \"${FAKE_CURL_EXIT-0}\"\n",
        );
        self.fake("grim", ": > \"$3\"\nexit \"${FAKE_GRIM_EXIT-0}\"\n");
        self.fake("mktemp", "printf '%s' \"${FAKE_MKTEMP_OUT:?}\"\n");
        self.fake("systemctl", "exit \"${FAKE_SYSTEMCTL_EXIT-0}\"\n");
        self.fake(
            "wl",
            r#"case "$1" in
  query)
    if [ -f "${FAKE_WL_COUNTER:-}" ]; then
      remaining=$(cat "$FAKE_WL_COUNTER")
      if [ "$remaining" -gt 0 ]; then
        echo $((remaining - 1)) > "$FAKE_WL_COUNTER"
        exit 1
      fi
    fi
    exit "${FAKE_WL_QUERY_EXIT-0}" ;;
  restore) exit "${FAKE_WL_RESTORE_EXIT-0}" ;;
esac
exit 0
"#,
        );
        self.fake(
            "inotifywait",
            "cat \"${FAKE_INOTIFY_LINES:-/dev/null}\"\nexit 0\n",
        );
        self.fake("zoxide", "exit 0\n");
        self.fake(
            "ssh-agent",
            "printf '%s\\n' \"SSH_AUTH_SOCK=${FAKE_SSH_SOCK:?}; export SSH_AUTH_SOCK;\"\nprintf '%s\\n' \"SSH_AGENT_PID=${FAKE_SSH_PID:?}; export SSH_AGENT_PID;\"\nprintf '%s\\n' \"echo Agent pid ${FAKE_SSH_PID};\"\n",
        );
        self.fake(
            "pass",
            "case \"$2\" in\n  ssh-key) printf '%s\\n' \"${FAKE_PASS_KEY-}\"\n    exit \"${FAKE_PASS_KEY_EXIT-0}\" ;;\n  wrk/ssh-key) printf '%s\\n' \"${FAKE_PASS_WRK_KEY-}\"\n    exit \"${FAKE_PASS_WRK_EXIT-1}\" ;;\nesac\nexit 1\n",
        );
        self.fake(
            "expect",
            "cat > \"${FAKE_EXPECT_STDIN:?}\"\nprintf '%s' \"${SSH_AUTH_SOCK-}\" > \"${FAKE_EXPECT_ENV:?}\"\nexit \"${FAKE_EXPECT_EXIT-0}\"\n",
        );
        self.fake(
            "bc",
            r#"expression=$(cat)
if [ -n "${FAKE_BC_LOG:-}" ]; then
  printf '%s\037' "$expression" >> "$FAKE_BC_LOG"
fi
case "$expression" in
  "1.0 + +10 / 100.0") printf '%s\n' "1.1" ;;
  "1.0 + -10 / 100.0") printf '%s\n' "0.9" ;;
  "1.0 + -99 / 100.0") printf '%s\n' "0.1" ;;
  "800 * 1.1 / 1") printf '%s\n' "880" ;;
  "600 * 1.1 / 1") printf '%s\n' "660" ;;
  "800 * 0.9 / 1") printf '%s\n' "720" ;;
  "600 * 0.9 / 1") printf '%s\n' "540" ;;
  "800 * 0.1 / 1") printf '%s\n' "80" ;;
  "600 * 0.1 / 1") printf '%s\n' "60" ;;
  "800 * 1.100000 / 1") printf '%s\n' "880.000000" ;;
  "600 * 1.100000 / 1") printf '%s\n' "660.000000" ;;
  *) printf '1\n' ;;
esac
exit 0
"#,
        );
        self.fake(
            "wf-recorder",
            r#"if [ "${1-}" = "-L" ]; then
  printf '%s' "${FAKE_WFREC_LIST-}"
  exit 0
fi
if [ -n "${FAKE_WFREC_PIDFILE:-}" ]; then
  printf '%s' $$ > "$FAKE_WFREC_PIDFILE"
fi
if [ "${FAKE_WFREC_DIE:-0}" = 1 ]; then
  exit 1
fi
kill -STOP $$
"#,
        );
        // screenrec's sound sidecar: a stopped process whose comm is `ffmpeg`,
        // so the start path sees it alive and `status` can report it. Every
        // screenrec test kills it through the state file.
        self.fake("ffmpeg", "kill -STOP $$\n");
        self.fake(
            "slurp",
            "printf '%s\\n' \"${FAKE_SLURP_OUT-}\"\nexit \"${FAKE_SLURP_EXIT-0}\"\n",
        );
        self.fake(
            "vicinae",
            "cat > \"${FAKE_VICINAE_STDIN:-/dev/null}\"\nprintf '%s' \"${FAKE_VICINAE_OUT-}\"\nexit \"${FAKE_VICINAE_EXIT-0}\"\n",
        );
        self.fake(
            "cliphist",
            "case \"$1\" in\n  list) printf '%s' \"${FAKE_CLIPHIST_LIST-}\" ;;\n  decode) printf '%s' \"${FAKE_CLIPHIST_DECODE-}\" ;;\nesac\nexit 0\n",
        );
        self.fake("wtype", "exit 0\n");
        self.fake(
            "yt-dlp",
            "printf '%s' \"$PWD\" > \"${FAKE_YTDLP_STATE:?}\"\nexit 0\n",
        );
        self.fake("negwm", "exit 0\n");
        self.fake("clipcat-menu", "exit 0\n");
        self.fake("pic-notify", "exit 0\n");
        self.fake("pic-info", "exit 0\n");
        self.fake("rg", "cat\n");
        self.fake("grep", "cat\n");
    }

    fn base_env(&self) -> Vec<(String, String)> {
        vec![
            ("PATH".into(), self.bin.display().to_string()),
            ("HOME".into(), self.home.display().to_string()),
            ("TMPDIR".into(), self.tmp.display().to_string()),
            ("XDG_RUNTIME_DIR".into(), self.run_dir.display().to_string()),
            ("USER".into(), self.user.clone()),
            ("LANG".into(), "C.UTF-8".into()),
            ("LC_ALL".into(), "C.UTF-8".into()),
            ("FAKE_LOG".into(), self.log.display().to_string()),
            ("FAKE_CLIP_FILE".into(), self.clip.display().to_string()),
            ("FAKE_NOTIFY_FILE".into(), self.notify.display().to_string()),
            ("FAKE_DISPATCH_FILE".into(), self.dispatch.display().to_string()),
            ("FAKE_EVAL_FILE".into(), self.eval.display().to_string()),
            ("FAKE_EXPECT_STDIN".into(), self.expect_stdin.display().to_string()),
            ("FAKE_EXPECT_ENV".into(), self.expect_env.display().to_string()),
            ("FAKE_VICINAE_STDIN".into(), self.vicinae_in.display().to_string()),
            ("FAKE_WL_LOG".into(), self.wl_log.display().to_string()),
            ("FAKE_WL_COUNTER".into(), self.wl_counter.display().to_string()),
            ("FAKE_BC_LOG".into(), self.bc_log.display().to_string()),
            ("FAKE_YTDLP_STATE".into(), self.ytdlp.display().to_string()),
            ("FAKE_WFREC_PIDFILE".into(), self.wfrec_pid.display().to_string()),
            ("FAKE_INOTIFY_LINES".into(), self.inotify.display().to_string()),
            ("FAKE_MKTEMP_OUT".into(), self.mktemp_out.display().to_string()),
            (
                "FAKE_ACTIVEWINDOW".into(),
                r#"{"pid":4242,"size":[800,600],"floating":true,"x":10,"y":20,"width":2560,"height":1440,"scale":1}"#.into(),
            ),
            (
                "FAKE_MONITORS".into(),
                r#"[{"name":"DP-1","focused":true,"x":0,"y":0,"width":2560,"height":1440,"scale":1}]"#.into(),
            ),
            ("FAKE_GETOPTION".into(), r#"{"bool":true}"#.into()),
        ]
    }

    pub fn run(&self, program: &str, args: &[&str]) -> Outcome {
        self.run_with(program, args, &[], None)
    }

    pub fn run_env(&self, program: &str, args: &[&str], envs: &[(&str, &str)]) -> Outcome {
        self.run_with(program, args, envs, None)
    }

    pub fn run_stdin(
        &self,
        program: &str,
        args: &[&str],
        envs: &[(&str, &str)],
        stdin: &[u8],
    ) -> Outcome {
        self.run_with(program, args, envs, Some(stdin))
    }

    pub fn run_with(
        &self,
        program: &str,
        args: &[&str],
        envs: &[(&str, &str)],
        stdin: Option<&[u8]>,
    ) -> Outcome {
        // stdout/stderr go to files, not pipes: a port like screenrec leaves a
        // running recorder behind, and `Command::output()` would block on the
        // inherited pipe until that child exits.
        let stdin_path = self.root.join("run.stdin");
        let stdout_path = self.root.join("run.stdout");
        let stderr_path = self.root.join("run.stderr");
        self.write(&stdin_path, stdin.unwrap_or_default());
        let stdin_file = std::fs::File::open(&stdin_path).expect("open stdin fixture");
        let stdout_file = std::fs::File::create(&stdout_path).expect("create stdout fixture");
        let stderr_file = std::fs::File::create(&stderr_path).expect("create stderr fixture");

        let mut command = Command::new(program);
        command.args(args);
        command.current_dir(&self.case);
        command.env_clear();
        for (name, value) in self.base_env() {
            command.env(name, value);
        }
        for (name, value) in envs {
            command.env(name, value);
        }
        command
            .stdin(stdin_file)
            .stdout(stdout_file)
            .stderr(stderr_file);
        let status = command.status().expect("run port");
        Outcome {
            code: status.code().unwrap_or_else(|| {
                128 + std::os::unix::process::ExitStatusExt::signal(&status).unwrap_or(0)
            }),
            stdout: std::fs::read(&stdout_path).unwrap_or_default(),
            stderr: std::fs::read(&stderr_path).unwrap_or_default(),
        }
    }

    /// Spawn a fake tool directly (for the state the ports read, e.g. a live
    /// `wf-recorder` whose comm must match).
    pub fn spawn_fake(&self, name: &str, args: &[&str]) -> std::process::Child {
        let mut command = Command::new(self.bin.join(name));
        command.args(args);
        command.env_clear();
        for (name, value) in self.base_env() {
            command.env(name, value);
        }
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn fake")
    }

    /// All fake tool calls, in order, as `[tool, arg...]`.
    pub fn log(&self) -> Vec<Vec<String>> {
        parse_calls(&fs::read(&self.log).unwrap_or_default())
            .into_iter()
            .map(|call| {
                call.into_iter()
                    .map(|arg| String::from_utf8_lossy(&arg).into_owned())
                    .collect()
            })
            .collect()
    }

    pub fn calls(&self, tool: &str) -> Vec<Vec<String>> {
        self.log()
            .into_iter()
            .filter(|call| call.first().map(String::as_str) == Some(tool))
            .collect()
    }

    /// Clipboard payloads, one per `wl-copy` call (empty payloads included).
    pub fn clipped(&self) -> Vec<Vec<u8>> {
        parse_records(&fs::read(&self.clip).unwrap_or_default())
    }

    pub fn last_clip(&self) -> Vec<u8> {
        self.clipped().pop().unwrap_or_default()
    }

    /// `notify-send` calls, one argv per notification.
    pub fn notifications(&self) -> Vec<Vec<Vec<u8>>> {
        parse_calls(&fs::read(&self.notify).unwrap_or_default())
    }

    /// `hyprctl dispatch` calls (argv without the leading `dispatch` word is not
    /// stripped: the fake logs `$@`, which starts with it).
    pub fn dispatch(&self) -> Vec<Vec<Vec<u8>>> {
        parse_calls(&fs::read(&self.dispatch).unwrap_or_default())
    }

    /// Expressions fed to `bc`, one per call.
    pub fn bc_expressions(&self) -> Vec<String> {
        parse_records(&fs::read(&self.bc_log).unwrap_or_default())
            .into_iter()
            .map(|record| String::from_utf8_lossy(&record).into_owned())
            .collect()
    }

    pub fn eval_snippet(&self) -> Vec<u8> {
        fs::read(&self.eval).unwrap_or_default()
    }

    pub fn expect_script(&self) -> Vec<u8> {
        fs::read(&self.expect_stdin).unwrap_or_default()
    }

    pub fn expect_environment(&self) -> Vec<u8> {
        fs::read(&self.expect_env).unwrap_or_default()
    }

    /// `wl` calls, one argv each.
    pub fn wl_calls(&self) -> Vec<Vec<String>> {
        self.calls("wl")
    }

    pub fn write(&self, path: &Path, contents: &[u8]) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent");
        }
        fs::write(path, contents).expect("write file");
    }

    pub fn read(&self, path: &Path) -> Vec<u8> {
        fs::read(path).unwrap_or_default()
    }

    pub fn set_mtime(&self, path: &Path, seconds: u64) {
        let file = fs::File::options()
            .write(true)
            .open(path)
            .expect("open for mtime");
        let time = UNIX_EPOCH + std::time::Duration::from_secs(seconds);
        file.set_times(fs::FileTimes::new().set_modified(time))
            .expect("set mtime");
    }

    /// A pid whose `/proc/<pid>/comm` is `wf-recorder` is required by screenrec;
    /// a script keeps the script's own name in comm, which is what the fake does.
    pub fn write_pidfile(&self, pid: u32) {
        let path = PathBuf::from(format!("/tmp/wf-recorder-{}.pid", self.user));
        fs::write(path, format!("{pid}\n")).expect("write pidfile");
    }

    pub fn pidfile(&self) -> PathBuf {
        PathBuf::from(format!("/tmp/wf-recorder-{}.pid", self.user))
    }

    /// screenrec's state file: the sidecar path and the audio PID the tests
    /// clean up after a start.
    pub fn statefile(&self) -> PathBuf {
        PathBuf::from(format!("/tmp/wf-recorder-{}.json", self.user))
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_file(self.pidfile());
        let _ = fs::remove_file(self.statefile());
        let _ = fs::remove_dir_all(&self.root);
    }
}

/// Split `US`-framed records, keeping empty payloads and dropping the trailing
/// separator.
fn parse_records(bytes: &[u8]) -> Vec<Vec<u8>> {
    let mut records: Vec<Vec<u8>> = bytes
        .split(|byte| *byte == 0x1f)
        .map(|piece| piece.to_vec())
        .collect();
    if records.last().map(Vec::is_empty).unwrap_or(false) {
        records.pop();
    }
    if bytes.is_empty() {
        records.clear();
    }
    records
}

/// Split call records into `[tool, arg...]`; `RS` separates the arguments of one
/// call, so an empty argument stays visible.
fn parse_calls(bytes: &[u8]) -> Vec<Vec<Vec<u8>>> {
    let mut calls = Vec::new();
    for record in parse_records(bytes) {
        let mut pieces: Vec<Vec<u8>> = record
            .split(|byte| *byte == 0x1e)
            .map(|piece| piece.to_vec())
            .collect();
        if pieces.last().map(Vec::is_empty).unwrap_or(false) {
            pieces.pop();
        }
        if !pieces.is_empty() {
            calls.push(pieces);
        }
    }
    calls
}

/// The combined argv of the first call of `tool`, for terse assertions.
pub fn call(tool: &str, args: &[&str]) -> Vec<String> {
    let mut call = vec![tool.to_string()];
    call.extend(args.iter().map(|arg| arg.to_string()));
    call
}

/// A NUL-separated rendering of a call list, handy in assertion messages.
pub fn render(calls: &[Vec<String>]) -> String {
    calls
        .iter()
        .map(|call| call.join(" "))
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn bytes(text: &str) -> Vec<u8> {
    text.as_bytes().to_vec()
}

pub fn str_of(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// A real unix socket at /tmp/kitty-<pid>, as kitty would leave behind.
pub fn bind_kitty_socket(pid: u32) -> std::os::unix::net::UnixListener {
    let path = PathBuf::from(format!("/tmp/kitty-{pid}"));
    let _ = fs::remove_file(&path);
    std::os::unix::net::UnixListener::bind(&path).expect("bind kitty socket")
}

pub fn remove_kitty_socket(pid: u32) {
    let _ = fs::remove_file(format!("/tmp/kitty-{pid}"));
}

pub fn is_socket(path: &Path) -> bool {
    use std::os::unix::fs::FileTypeExt;
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_socket())
        .unwrap_or(false)
}

pub fn os(path: &Path) -> &OsStr {
    path.as_os_str()
}
