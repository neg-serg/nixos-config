//! Hermetic end-to-end tests for the `swayimg-actions` binary.
//!
//! Every test builds a sandbox with HOME, XDG dirs and TMPDIR under a fresh
//! temporary directory, clears the inherited environment, puts fake tools
//! (mogrify, convert, swww, swaymsg, vicinae, zoxide, wl-copy, pic-notify) and
//! symlinks to the few coreutils the binary still spawns on PATH, and records
//! their argv. IPC tests use a real `UnixListener`. Range tests build fixture
//! trees in a controlled creation order, which is the ctime order `find -L`
//! would have observed.
//!
//! Nothing here touches the real ~/tmp, ~/trash, ~/.local/share, the real
//! wallpaper list or a real swayimg socket: no swayimg/swww/zoxide is invoked.

use std::ffi::OsStr;
use std::fs;
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const BIN: &str = env!("CARGO_BIN_EXE_swayimg-actions");
const HELP: &str = include_str!("../src/help.txt");
const DEFAULT_SWAYMSG: &str = r#"[{"active":true,"current_mode":{"width":1920,"height":1080}}]"#;

static COUNTER: AtomicU64 = AtomicU64::new(0);

const LOGGER: &str = r#"
log() {
  name=$1
  shift
  printf '%s' "$name" >> "$FAKE_LOG"
  for arg in "$@"; do printf '\037%s' "$arg" >> "$FAKE_LOG"; done
  printf '\n' >> "$FAKE_LOG"
}
"#;

struct Sandbox {
    root: PathBuf,
    home: PathBuf,
    data: PathBuf,
    pictures: PathBuf,
    runtime: PathBuf,
    tmp: PathBuf,
    bin: PathBuf,
    cap: PathBuf,
    log: PathBuf,
}

impl Sandbox {
    fn new(label: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "swayimg-actions-{label}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let home = root.join("home");
        let data = root.join("xdg");
        let pictures = home.join("Pictures");
        let runtime = root.join("run");
        let tmp = root.join("tmp");
        let bin = root.join("bin");
        let cap = root.join("cap");
        for directory in [
            &home,
            &home.join("pic"),
            &pictures,
            &data,
            &runtime,
            &tmp,
            &bin,
            &cap,
        ] {
            fs::create_dir_all(directory).expect("sandbox directory");
        }
        let log = root.join("tools.log");
        fs::write(&log, "").unwrap();

        for tool in ["cat", "cp", "mv", "realpath", "sed"] {
            std::os::unix::fs::symlink(host_program(tool), bin.join(tool))
                .unwrap_or_else(|error| panic!("symlink {tool}: {error}"));
        }

        let sandbox = Self {
            root,
            home,
            data,
            pictures,
            runtime,
            tmp,
            bin,
            cap,
            log,
        };
        sandbox.install_default_fakes();
        sandbox
    }

    fn current_image(&self) -> PathBuf {
        self.home.join("pic/cur.jpg")
    }

    fn write_image(&self, path: &Path) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, b"img").unwrap();
    }

    fn install_script(&self, name: &str, body: &str) {
        let path = self.bin.join(name);
        fs::write(&path, format!("#!/bin/sh\n{LOGGER}\n{body}\n")).unwrap();
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).unwrap();
    }

    fn install_default_fakes(&self) {
        self.install_script(
            "mogrify",
            "log mogrify \"$@\"\nexit \"${FAKE_MOGRIFY_EXIT:-0}\"",
        );
        self.install_script(
            "convert",
            "log convert \"$@\"\n\
             last=\n\
             for arg in \"$@\"; do last=$arg; done\n\
             if [ -n \"$last\" ]; then printf rendered > \"$last\"; fi\n\
             exit \"${FAKE_CONVERT_EXIT:-0}\"",
        );
        self.install_script(
            "swww",
            "log swww \"$@\"\n\
             if [ \"$1\" = query ]; then exit \"${FAKE_SWWW_QUERY_EXIT:-0}\"; fi\n\
             exit 0",
        );
        self.install_script(
            "swaymsg",
            "log swaymsg \"$@\"\nprintf '%s' \"${FAKE_SWAYMSG:-}\"\nexit 0",
        );
        self.install_script(
            "vicinae",
            "log vicinae \"$@\"\n\
             cat > \"$FAKE_CAP/vicinae.stdin\"\n\
             printf '%s' \"${FAKE_VICINAE_OUT:-}\"\n\
             exit 0",
        );
        self.install_script(
            "zoxide",
            "log zoxide \"$@\"\n\
             if [ \"$1\" = query ]; then printf '%s' \"${FAKE_ZOXIDE:-}\"; fi\n\
             exit 0",
        );
        self.install_script(
            "wl-copy",
            "log wl-copy \"$@\"\ncat > \"$FAKE_CAP/wl-copy.stdin\"\nexit 0",
        );
    }

    fn remove_tool(&self, name: &str) {
        let _ = fs::remove_file(self.bin.join(name));
    }

    fn install_notifier(&self) {
        let directory = self.home.join(".local/bin");
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join("pic-notify");
        fs::write(
            &path,
            format!("#!/bin/sh\n{LOGGER}\nlog pic-notify \"$@\"\nexit 0\n"),
        )
        .unwrap();
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).unwrap();
    }

    fn command(&self) -> Command {
        let mut command = Command::new(BIN);
        command
            .env_clear()
            .env("HOME", &self.home)
            .env("XDG_DATA_HOME", &self.data)
            .env("XDG_PICTURES_DIR", &self.pictures)
            .env("XDG_RUNTIME_DIR", &self.runtime)
            .env("TMPDIR", &self.tmp)
            .env("PATH", &self.bin)
            .env("LC_ALL", "C")
            .env("FAKE_LOG", &self.log)
            .env("FAKE_CAP", &self.cap)
            .env("FAKE_SWAYMSG", DEFAULT_SWAYMSG)
            .env("FAKE_ZOXIDE", "")
            .env("FAKE_VICINAE_OUT", "");
        command
    }

    fn run(&self, arguments: &[&str]) -> Output {
        self.command()
            .args(arguments)
            .output()
            .expect("run swayimg-actions")
    }

    fn run_with<I, S>(&self, arguments: I) -> Output
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        self.command()
            .args(arguments)
            .output()
            .expect("run swayimg-actions")
    }

    fn invocations(&self) -> Vec<Invocation> {
        let text = fs::read_to_string(&self.log).unwrap_or_default();
        text.lines()
            .map(|line| {
                let mut fields = line.split('\u{1f}');
                Invocation {
                    tool: fields.next().unwrap_or_default().to_string(),
                    arguments: fields.map(str::to_string).collect(),
                }
            })
            .collect()
    }

    fn clear_log(&self) {
        fs::write(&self.log, "").unwrap();
    }

    fn captured(&self, name: &str) -> Vec<u8> {
        fs::read(self.cap.join(name)).unwrap_or_default()
    }

    fn write_mark(&self, anchor: &str) {
        fs::create_dir_all(self.data.join("swayimg")).unwrap();
        fs::write(self.data.join("swayimg/range_mark"), format!("{anchor}\n")).unwrap();
    }

    fn mark(&self) -> Option<String> {
        fs::read_to_string(self.data.join("swayimg/range_mark")).ok()
    }

    fn create_images(&self, names: &[&str]) {
        fs::create_dir_all(&self.pictures).unwrap();
        for name in names {
            fs::write(self.pictures.join(name), name.as_bytes()).unwrap();
            thread::sleep(Duration::from_millis(10));
        }
    }

    fn temp_files(&self) -> Vec<PathBuf> {
        fs::read_dir(self.home.join("tmp"))
            .map(|entries| entries.flatten().map(|entry| entry.path()).collect())
            .unwrap_or_default()
    }

    fn listener(&self, name: &str) -> (UnixListener, PathBuf) {
        let path = self.root.join(name);
        let listener = UnixListener::bind(&path).unwrap();
        listener.set_nonblocking(true).unwrap();
        (listener, path)
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[derive(Debug, PartialEq, Eq)]
struct Invocation {
    tool: String,
    arguments: Vec<String>,
}

fn invocation(tool: &str, arguments: &[&str]) -> Invocation {
    Invocation {
        tool: tool.to_string(),
        arguments: arguments.iter().map(|value| value.to_string()).collect(),
    }
}

fn host_program(name: &str) -> PathBuf {
    let path = std::env::var_os("PATH").expect("PATH");
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(name);
        if candidate.is_file() {
            return candidate;
        }
    }
    panic!("host tool not found: {name}");
}

/// Wait for one connection on a non-blocking listener (the child has already
/// exited, so the data is in the socket backlog).
fn receive(listener: &UnixListener) -> Vec<u8> {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match listener.accept() {
            Ok((mut stream, _)) => {
                let mut bytes = Vec::new();
                stream.read_to_end(&mut bytes).unwrap();
                return bytes;
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                assert!(Instant::now() < deadline, "no IPC connection");
                thread::sleep(Duration::from_millis(5));
            }
            Err(error) => panic!("accept failed: {error}"),
        }
    }
}

fn assert_no_connection(listener: &UnixListener) {
    thread::sleep(Duration::from_millis(150));
    match listener.accept() {
        Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {}
        Ok(_) => panic!("unexpected IPC connection"),
        Err(error) => panic!("accept failed: {error}"),
    }
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn code(output: &Output) -> i32 {
    output.status.code().expect("exit code")
}

// ---- CLI surface ---------------------------------------------------------

#[test]
fn help_prints_the_embedded_shell_lines_and_creates_nothing() {
    let sandbox = Sandbox::new("help");
    for flag in ["--help", "-h"] {
        let output = sandbox.run(&[flag]);
        assert_eq!(code(&output), 0);
        assert_eq!(stdout(&output), HELP);
        assert!(output.stderr.is_empty());
        assert!(!sandbox.home.join("tmp").exists());
        assert!(!sandbox.data.join("swayimg").exists());
    }
}

#[test]
fn unknown_action_exits_2_and_creates_startup_directories() {
    let sandbox = Sandbox::new("unknown");
    let output = sandbox.run(&["bogus"]);
    assert_eq!(code(&output), 2);
    assert_eq!(stderr(&output), "Unknown action: bogus\n");
    assert!(sandbox.home.join("tmp").is_dir());
    assert!(sandbox.data.join("swayimg").is_dir());

    // `repeat` is bound by init.lua but the shell never had a case for it.
    let output = sandbox.run(&["repeat"]);
    assert_eq!(code(&output), 2);
    assert_eq!(stderr(&output), "Unknown action: repeat\n");
}

// ---- rotate / copyname ---------------------------------------------------

#[test]
fn rotate_actions_spawn_mogrify_with_the_shell_argv() {
    let sandbox = Sandbox::new("rotate");
    sandbox.write_image(&sandbox.current_image());
    for (action, angle) in [
        ("rotate-left", "270"),
        ("rotate-right", "90"),
        ("rotate-180", "180"),
        ("rotate-ccw", "-90"),
    ] {
        sandbox.clear_log();
        let output = sandbox.run_with([OsStr::new(action), sandbox.current_image().as_os_str()]);
        assert_eq!(code(&output), 0);
        assert_eq!(
            sandbox.invocations(),
            vec![invocation(
                "mogrify",
                &["-rotate", angle, sandbox.current_image().to_str().unwrap()]
            )]
        );
    }
    assert!(sandbox.temp_files().is_empty());
}

#[test]
fn missing_mogrify_reproduces_the_command_not_found_exit() {
    let sandbox = Sandbox::new("rotate-missing");
    sandbox.write_image(&sandbox.current_image());
    sandbox.remove_tool("mogrify");
    let output = sandbox.run_with([
        OsStr::new("rotate-left"),
        sandbox.current_image().as_os_str(),
    ]);
    assert_eq!(code(&output), 127);
    assert!(stderr(&output).contains("command not found: mogrify"));
}

#[test]
fn copyname_feeds_the_canonical_path_and_runs_pic_notify() {
    let sandbox = Sandbox::new("copyname");
    sandbox.write_image(&sandbox.current_image());
    sandbox.install_notifier();
    let output = sandbox.run_with([OsStr::new("copyname"), sandbox.current_image().as_os_str()]);
    assert_eq!(code(&output), 0);
    let canonical = fs::canonicalize(sandbox.current_image()).unwrap();
    assert_eq!(
        sandbox.captured("wl-copy.stdin"),
        format!("{}\n", canonical.display()).into_bytes()
    );
    assert_eq!(
        sandbox.invocations(),
        vec![
            invocation("wl-copy", &[]),
            invocation("pic-notify", &[sandbox.current_image().to_str().unwrap()]),
        ]
    );
}

#[test]
fn copyname_without_pic_notify_still_succeeds() {
    let sandbox = Sandbox::new("copyname-no-notify");
    sandbox.write_image(&sandbox.current_image());
    let output = sandbox.run_with([OsStr::new("copyname"), sandbox.current_image().as_os_str()]);
    assert_eq!(code(&output), 0);
    assert_eq!(sandbox.invocations(), vec![invocation("wl-copy", &[])]);
}

// ---- mv / cp / picker ----------------------------------------------------

#[test]
fn mv_explicit_destination_sends_next_file_and_records_last() {
    let sandbox = Sandbox::new("mv-explicit");
    sandbox.write_image(&sandbox.current_image());
    let (listener, socket) = sandbox.listener("ipc.sock");
    let destination = sandbox.home.join("trash/1st-level/pic");
    let output = sandbox
        .command()
        .env("SWAYIMG_IPC", &socket)
        .args([
            OsStr::new("mv"),
            sandbox.current_image().as_os_str(),
            destination.as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(receive(&listener), b"next_file\n");
    assert!(destination.join("cur.jpg").is_file());
    assert!(!sandbox.current_image().exists());
    assert_eq!(
        fs::read_to_string(sandbox.data.join("swayimg/last")).unwrap(),
        format!("mv {}\n", destination.display())
    );
    let log = sandbox.invocations();
    assert_eq!(
        log.iter()
            .map(|call| call.tool.as_str())
            .collect::<Vec<_>>(),
        vec!["zoxide"]
    );
    assert_eq!(
        log[0],
        invocation("zoxide", &["add", destination.to_str().unwrap()])
    );
    assert!(sandbox.temp_files().is_empty());
}

#[test]
fn cp_explicit_destination_copies_and_never_sends_next_file() {
    let sandbox = Sandbox::new("cp-explicit");
    sandbox.write_image(&sandbox.current_image());
    let (listener, socket) = sandbox.listener("ipc.sock");
    let destination = sandbox.home.join("explicit-dest");
    let output = sandbox
        .command()
        .env("SWAYIMG_IPC", &socket)
        .args([
            OsStr::new("cp"),
            sandbox.current_image().as_os_str(),
            destination.as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(sandbox.captured("vicinae.stdin"), b"");
    assert!(destination.join("cur.jpg").is_file());
    assert!(sandbox.current_image().is_file());
    assert_no_connection(&listener);
    assert_eq!(
        fs::read_to_string(sandbox.data.join("swayimg/last")).unwrap(),
        format!("cp {}\n", destination.display())
    );
}

#[test]
fn picker_receives_the_shell_entry_list_and_rewrites_the_selection() {
    let sandbox = Sandbox::new("cp-picker");
    sandbox.write_image(&sandbox.current_image());
    fs::create_dir_all(sandbox.pictures.join("dest")).unwrap();
    let zoxide = format!(
        "{pictures}\n{home}/pic\n{home}/.hidden/x\n/mnt/one/foo\n/mnt/one/.bar\n/usr/share/dot\n",
        pictures = sandbox.pictures.display(),
        home = sandbox.home.display()
    );
    let output = sandbox
        .command()
        .env("FAKE_ZOXIDE", &zoxide)
        .env("FAKE_VICINAE_OUT", "~/Pictures/dest\n")
        .args([OsStr::new("cp"), sandbox.current_image().as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);

    let expected_stdin = "/mnt/one/foo\n~/Pictures\n~/Pictures/dest\n~/pic\n";
    assert_eq!(sandbox.captured("vicinae.stdin"), expected_stdin.as_bytes());

    let picker = sandbox
        .invocations()
        .into_iter()
        .find(|call| call.tool == "vicinae")
        .expect("vicinae invoked");
    assert_eq!(picker, invocation("vicinae", &["dmenu", "-p", "⟬cp⟭ ❯>"]));
    assert!(sandbox.pictures.join("dest/cur.jpg").is_file());
    assert_eq!(
        fs::read_to_string(sandbox.data.join("swayimg/last")).unwrap(),
        format!("cp {}\n", sandbox.pictures.join("dest").display())
    );
    // zoxide query -l plus the remembered destination.
    let zoxide_calls: Vec<_> = sandbox
        .invocations()
        .into_iter()
        .filter(|call| call.tool == "zoxide")
        .collect();
    assert_eq!(
        zoxide_calls,
        vec![
            invocation("zoxide", &["query", "-l"]),
            invocation(
                "zoxide",
                &["add", sandbox.pictures.join("dest").to_str().unwrap()]
            ),
        ]
    );
}

#[test]
fn cancelled_picker_leaves_everything_alone() {
    let sandbox = Sandbox::new("cp-cancel");
    sandbox.write_image(&sandbox.current_image());
    let output = sandbox
        .command()
        .env("FAKE_VICINAE_OUT", "")
        .args([OsStr::new("mv"), sandbox.current_image().as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert!(sandbox.current_image().is_file());
    assert!(!sandbox.data.join("swayimg/last").exists());
}

// ---- wallpapers ----------------------------------------------------------

fn assert_wall_run(sandbox: &Sandbox, action: &str, file: &Path, expected: &[String]) {
    sandbox.clear_log();
    let _ = fs::remove_file(sandbox.data.join("wl/wallpaper.list"));
    let output = sandbox.run_with([OsStr::new(action), file.as_os_str()]);
    assert_eq!(code(&output), 0);
    let log = sandbox.invocations();
    assert_eq!(log.len(), 4, "log: {log:?}");
    assert_eq!(log[0], invocation("swww", &["query"]));
    assert_eq!(log[1], invocation("swaymsg", &["-t", "get_outputs", "-r"]));
    assert_eq!(log[2].tool, "convert");
    assert_eq!(&log[2].arguments[..expected.len()], expected);
    let temporary = &log[2].arguments[expected.len()];
    assert!(
        temporary.starts_with(&format!("{}/tmp/wall_swww.", sandbox.home.display())),
        "unexpected temp wallpaper: {temporary}"
    );
    assert!(
        !Path::new(temporary).exists(),
        "temp wallpaper was not removed"
    );
    assert_eq!(log[3], invocation("swww", &["img", temporary.as_str()]));
    let list = fs::read_to_string(sandbox.data.join("wl/wallpaper.list")).unwrap();
    assert_eq!(list, format!("{}\n", file.display()));
}

#[test]
fn wall_modes_render_with_the_shell_convert_argv() {
    let sandbox = Sandbox::new("wall-modes");
    fs::create_dir_all(sandbox.data.join("wl")).unwrap();
    let file = sandbox.current_image();
    sandbox.write_image(&file);
    let path = file.to_str().unwrap().to_string();

    let cover = vec![
        path.clone(),
        "-resize".into(),
        "1920x1080^".into(),
        "-gravity".into(),
        "center".into(),
        "-extent".into(),
        "1920x1080".into(),
    ];
    for action in ["wall-fill", "wall-full", "wall-cover"] {
        assert_wall_run(&sandbox, action, &file, &cover);
    }
    let center = vec![
        path.clone(),
        "-resize".into(),
        "1920x1080".into(),
        "-gravity".into(),
        "center".into(),
        "-background".into(),
        "black".into(),
        "-extent".into(),
        "1920x1080".into(),
    ];
    assert_wall_run(&sandbox, "wall-center", &file, &center);
    assert_wall_run(
        &sandbox,
        "wall-tile",
        &file,
        &["-size".into(), "1920x1080".into(), format!("tile:{path}")],
    );
    assert_wall_run(
        &sandbox,
        "wall-mono",
        &file,
        &[path.clone(), "-colors".into(), "2".into()],
    );
}

#[test]
fn wall_picks_the_largest_active_output_and_falls_back() {
    let sandbox = Sandbox::new("wall-screen");
    let file = sandbox.current_image();
    sandbox.write_image(&file);
    let json = r#"[
      {"active": true, "current_mode": {"width": 1920, "height": 1080}},
      {"active": true, "current_mode": {"width": 2560, "height": 1440}},
      {"active": false, "current_mode": {"width": 3840, "height": 2160}},
      {"active": true, "current_mode": null}
    ]"#;
    let output = sandbox
        .command()
        .env("FAKE_SWAYMSG", json)
        .args([OsStr::new("wall-fill"), file.as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    let convert = sandbox
        .invocations()
        .into_iter()
        .find(|call| call.tool == "convert")
        .unwrap();
    assert_eq!(convert.arguments[2], "2560x1440^");
    assert_eq!(convert.arguments[6], "2560x1440");

    // No swaymsg on PATH at all: the hard-coded fallback.
    let fallback = Sandbox::new("wall-screen-missing");
    fallback.write_image(&fallback.current_image());
    fallback.remove_tool("swaymsg");
    let output = fallback.run_with([
        OsStr::new("wall-center"),
        fallback.current_image().as_os_str(),
    ]);
    assert_eq!(code(&output), 0);
    let convert = fallback
        .invocations()
        .into_iter()
        .find(|call| call.tool == "convert")
        .unwrap();
    assert_eq!(convert.arguments[2], "1920x1080");
}

#[test]
fn wall_honours_override_and_flags_as_single_arguments() {
    let sandbox = Sandbox::new("wall-flags");
    let file = sandbox.current_image();
    sandbox.write_image(&file);
    let output = sandbox
        .command()
        .env("SWWW_IMAGE_OVERRIDE", "/tmp/override.img")
        .env("SWWW_FLAGS", "--transition-type fade --flag")
        .args([OsStr::new("wall-mono"), file.as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    let image = sandbox
        .invocations()
        .into_iter()
        .find(|call| call.tool == "swww" && call.arguments[0] == "img")
        .unwrap();
    assert_eq!(
        image,
        invocation(
            "swww",
            &["img", "/tmp/override.img", "--transition-type fade --flag"]
        )
    );
}

#[test]
fn wall_starts_swww_when_query_fails() {
    let sandbox = Sandbox::new("wall-init");
    let file = sandbox.current_image();
    sandbox.write_image(&file);
    let output = sandbox
        .command()
        .env("FAKE_SWWW_QUERY_EXIT", "1")
        .args([OsStr::new("wall-fill"), file.as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(
        sandbox.invocations()[..2],
        [
            invocation("swww", &["query"]),
            invocation("swww", &["init"]),
        ]
    );
}

#[test]
fn wall_without_convert_does_nothing_but_returns_zero() {
    let sandbox = Sandbox::new("wall-no-convert");
    let file = sandbox.current_image();
    sandbox.write_image(&file);
    sandbox.remove_tool("convert");
    let output = sandbox.run_with([OsStr::new("wall-mono"), file.as_os_str()]);
    assert_eq!(code(&output), 0);
    assert_eq!(sandbox.invocations(), vec![invocation("swww", &["query"])]);
}

#[test]
fn wall_writes_the_list_through_zsh_echo_escapes() {
    let sandbox = Sandbox::new("wall-echo");
    fs::create_dir_all(sandbox.data.join("wl")).unwrap();
    let file = sandbox.pictures.join("esc\\nname.jpg");
    sandbox.write_image(&file);
    let output = sandbox.run_with([OsStr::new("wall-mono"), file.as_os_str()]);
    assert_eq!(code(&output), 0);
    let expected = file.to_str().unwrap().replace("\\n", "\n") + "\n";
    assert_eq!(
        fs::read_to_string(sandbox.data.join("wl/wallpaper.list")).unwrap(),
        expected
    );
}

// ---- ranges --------------------------------------------------------------

#[test]
fn range_mark_stores_the_canonical_target_of_a_symlink() {
    let sandbox = Sandbox::new("range-mark");
    let target = sandbox.pictures.join("two.jpg");
    sandbox.write_image(&target);
    let link = sandbox.pictures.join("link.jpg");
    std::os::unix::fs::symlink(&target, &link).unwrap();
    let output = sandbox.run_with([OsStr::new("range-mark"), link.as_os_str()]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        sandbox.mark().unwrap(),
        format!("{}\n", fs::canonicalize(&target).unwrap().display())
    );

    let output = sandbox.run_with([OsStr::new("range-clear")]);
    assert_eq!(code(&output), 0);
    assert!(sandbox.mark().is_none());
}

#[test]
fn range_mark_handles_missing_files_and_dangling_symlinks() {
    let sandbox = Sandbox::new("range-mark-missing");
    let missing = sandbox.pictures.join("nope.jpg");
    let output = sandbox.run_with([OsStr::new("range-mark"), missing.as_os_str()]);
    assert_eq!(code(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "swayimg-actions: range-mark: file not found: {}\n",
            missing.display()
        )
    );
    assert!(sandbox.mark().is_none());

    // A dangling symlink passes the shell's `[ ! -f ] && [ ! -L ]` guard, and
    // GNU realpath canonicalizes it successfully (it only requires the link's
    // target path, not the target itself): the mark points at a missing file.
    let broken = sandbox.pictures.join("broken.jpg");
    let gone = sandbox.pictures.join("gone.jpg");
    std::os::unix::fs::symlink(&gone, &broken).unwrap();
    let output = sandbox.run_with([OsStr::new("range-mark"), broken.as_os_str()]);
    assert_eq!(code(&output), 0);
    assert!(output.stderr.is_empty());
    assert_eq!(
        sandbox.mark().unwrap(),
        format!(
            "{}\n",
            fs::canonicalize(&sandbox.pictures)
                .unwrap()
                .join("gone.jpg")
                .display()
        )
    );
}

#[test]
fn range_trash_without_a_mark_moves_the_single_file() {
    let sandbox = Sandbox::new("range-trash-no-mark");
    let file = sandbox.pictures.join("five.jpg");
    sandbox.write_image(&file);
    let (listener, socket) = sandbox.listener("ipc.sock");
    let output = sandbox
        .command()
        .env("SWAYIMG_IPC", &socket)
        .args([OsStr::new("range-trash"), file.as_os_str()])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(receive(&listener), b"prev_file\n");
    assert!(sandbox.home.join("trash/1st-level/pic/five.jpg").is_file());
    assert!(!file.exists());
}

#[test]
fn range_trash_clears_a_stale_mark_and_falls_back_to_one_file() {
    let sandbox = Sandbox::new("range-trash-stale");
    let file = sandbox.pictures.join("five.jpg");
    sandbox.write_image(&file);
    sandbox.write_mark(sandbox.pictures.join("deleted.jpg").to_str().unwrap());
    let output = sandbox.run_with([OsStr::new("range-trash"), file.as_os_str()]);
    assert_eq!(code(&output), 0);
    assert!(stderr(&output).contains("stale range mark cleared"));
    assert!(sandbox.mark().is_none());
    assert!(sandbox.home.join("trash/1st-level/pic/five.jpg").is_file());
}

#[test]
fn range_trash_with_an_anchor_moves_the_inclusive_slice() {
    let sandbox = Sandbox::new("range-trash-anchor");
    sandbox.create_images(&["one.jpg", "two.jpg", "three.jpg", "four.jpg", "five.jpg"]);
    sandbox.write_mark(sandbox.pictures.join("three.jpg").to_str().unwrap());
    let (listener, socket) = sandbox.listener("ipc.sock");
    let output = sandbox
        .command()
        .env("SWAYIMG_IPC", &socket)
        .args([
            OsStr::new("range-trash"),
            sandbox.pictures.join("five.jpg").as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(receive(&listener), b"prev_file\n");
    let trash = sandbox.home.join("trash/1st-level/pic");
    for name in ["three.jpg", "four.jpg", "five.jpg"] {
        assert!(trash.join(name).is_file(), "{name} was not trashed");
    }
    for name in ["one.jpg", "two.jpg"] {
        assert!(sandbox.pictures.join(name).is_file(), "{name} was moved");
    }
    assert!(sandbox.mark().is_none());
    assert!(
        !stderr(&output).contains("sed:"),
        "stderr: {}",
        stderr(&output)
    );
}

#[test]
fn range_anchor_outside_the_directory_fails_and_keeps_the_mark() {
    let sandbox = Sandbox::new("range-anchor-other");
    sandbox.create_images(&["one.jpg", "two.jpg", "three.jpg", "four.jpg", "five.jpg"]);
    let other = sandbox.home.join("other/two.jpg");
    sandbox.write_image(&other);
    sandbox.write_mark(other.to_str().unwrap());
    let output = sandbox.run_with([
        OsStr::new("range-trash"),
        sandbox.pictures.join("five.jpg").as_os_str(),
    ]);
    assert_eq!(code(&output), 1);
    assert!(stderr(&output).contains("Range mark not found in current directory"));
    assert!(sandbox.mark().is_some());
    assert!(sandbox.pictures.join("five.jpg").is_file());
}

#[test]
fn range_listing_is_ordered_by_ctime_descending() {
    let sandbox = Sandbox::new("range-order");
    let names: Vec<String> = (1..=11).map(|index| format!("{index:02}.jpg")).collect();
    let refs: Vec<&str> = names.iter().map(String::as_str).collect();
    sandbox.create_images(&refs);
    // 01 was created first (oldest, last line of the newest-first listing) and
    // 11 last (first line), so the inclusive slice is the whole directory.
    sandbox.write_mark(sandbox.pictures.join("01.jpg").to_str().unwrap());
    let output = sandbox.run_with([
        OsStr::new("range-trash"),
        sandbox.pictures.join("11.jpg").as_os_str(),
    ]);
    assert_eq!(code(&output), 0);
    let trash = sandbox.home.join("trash/1st-level/pic");
    assert_eq!(fs::read_dir(&trash).unwrap().count(), 11);
    assert_eq!(fs::read_dir(sandbox.pictures.join("")).unwrap().count(), 0);
    assert!(sandbox.mark().is_none());
}

#[test]
fn range_cp_with_an_anchor_copies_the_inclusive_slice() {
    let sandbox = Sandbox::new("range-cp-anchor");
    sandbox.create_images(&["one.jpg", "two.jpg", "three.jpg", "four.jpg", "five.jpg"]);
    fs::create_dir_all(sandbox.pictures.join("dest")).unwrap();
    sandbox.write_mark(sandbox.pictures.join("three.jpg").to_str().unwrap());
    let output = sandbox
        .command()
        .env("FAKE_VICINAE_OUT", "~/Pictures/dest\n")
        .args([
            OsStr::new("range-cp"),
            sandbox.pictures.join("five.jpg").as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(
        sandbox.captured("vicinae.stdin"),
        b"~/Pictures\n~/Pictures/dest\n"
    );
    for name in ["three.jpg", "four.jpg", "five.jpg"] {
        assert!(sandbox.pictures.join("dest").join(name).is_file(), "{name}");
        assert!(sandbox.pictures.join(name).is_file(), "{name} moved");
    }
    assert!(!sandbox.pictures.join("dest/one.jpg").exists());
    assert!(!sandbox.pictures.join("dest/two.jpg").exists());
    assert!(sandbox.mark().is_none());
}

#[test]
fn range_mv_with_an_anchor_moves_the_slice_and_sends_prev_file() {
    let sandbox = Sandbox::new("range-mv-anchor");
    sandbox.create_images(&["one.jpg", "two.jpg", "three.jpg", "four.jpg", "five.jpg"]);
    fs::create_dir_all(sandbox.pictures.join("dest")).unwrap();
    sandbox.write_mark(sandbox.pictures.join("three.jpg").to_str().unwrap());
    let (listener, socket) = sandbox.listener("ipc.sock");
    let output = sandbox
        .command()
        .env("SWAYIMG_IPC", &socket)
        .env("FAKE_VICINAE_OUT", "~/Pictures/dest\n")
        .args([
            OsStr::new("range-mv"),
            sandbox.pictures.join("five.jpg").as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(receive(&listener), b"prev_file\n");
    for name in ["three.jpg", "four.jpg", "five.jpg"] {
        assert!(sandbox.pictures.join("dest").join(name).is_file(), "{name}");
        assert!(!sandbox.pictures.join(name).exists(), "{name} stayed");
    }
    assert!(sandbox.pictures.join("one.jpg").is_file());
    assert!(sandbox.pictures.join("two.jpg").is_file());
    assert!(sandbox.mark().is_none());
}

#[test]
fn range_current_file_outside_the_image_listing_fails_and_keeps_the_mark() {
    let sandbox = Sandbox::new("range-current-non-image");
    sandbox.create_images(&["one.jpg", "two.jpg", "three.jpg"]);
    sandbox.write_mark(sandbox.pictures.join("three.jpg").to_str().unwrap());
    let notes = sandbox.pictures.join("notes.txt");
    fs::write(&notes, b"not an image").unwrap();
    let output = sandbox.run_with([OsStr::new("range-trash"), notes.as_os_str()]);
    assert_eq!(code(&output), 1);
    assert!(stderr(&output).contains("current file not found in the image listing"));
    assert!(sandbox.mark().is_some());
    for name in ["one.jpg", "two.jpg", "three.jpg"] {
        assert!(sandbox.pictures.join(name).is_file(), "{name} moved");
    }
    assert!(notes.is_file());
}

#[test]
fn range_cp_without_a_mark_copies_the_single_file_to_the_picked_directory() {
    let sandbox = Sandbox::new("range-cp-no-mark");
    sandbox.write_image(&sandbox.pictures.join("five.jpg"));
    fs::create_dir_all(sandbox.pictures.join("dest")).unwrap();
    let output = sandbox
        .command()
        .env("FAKE_VICINAE_OUT", "~/Pictures/dest\n")
        .args([
            OsStr::new("range-cp"),
            sandbox.pictures.join("five.jpg").as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert!(sandbox.pictures.join("dest/five.jpg").is_file());
    assert!(sandbox.pictures.join("five.jpg").is_file());
}

// ---- IPC -----------------------------------------------------------------

#[test]
fn ipc_falls_back_to_the_newest_runtime_socket() {
    let sandbox = Sandbox::new("ipc-newest");
    sandbox.write_image(&sandbox.current_image());
    let old = sandbox.runtime.join("swayimg-old.sock");
    let _old_listener = UnixListener::bind(&old).unwrap();
    thread::sleep(Duration::from_millis(20));
    let (listener, _new_path) = sandbox.listener("run/swayimg-new.sock");
    let destination = sandbox.home.join("trash/1st-level/pic");
    let output = sandbox
        .command()
        .args([
            OsStr::new("mv"),
            sandbox.current_image().as_os_str(),
            destination.as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_eq!(receive(&listener), b"next_file\n");
}

#[test]
fn ipc_gives_up_when_the_newest_match_is_not_a_socket() {
    let sandbox = Sandbox::new("ipc-non-socket");
    sandbox.write_image(&sandbox.current_image());
    let (listener, _live) = sandbox.listener("run/swayimg-old.sock");
    thread::sleep(Duration::from_millis(20));
    fs::write(sandbox.runtime.join("swayimg-zzz.sock"), b"").unwrap();
    let destination = sandbox.home.join("trash/1st-level/pic");
    let output = sandbox
        .command()
        .args([
            OsStr::new("mv"),
            sandbox.current_image().as_os_str(),
            destination.as_os_str(),
        ])
        .output()
        .unwrap();
    assert_eq!(code(&output), 0);
    assert_no_connection(&listener);
    assert!(destination.join("cur.jpg").is_file());
}

// ---- misc ----------------------------------------------------------------

#[test]
fn screen_size_falls_back_when_swaymsg_is_missing() {
    let sandbox = Sandbox::new("no-swaymsg");
    sandbox.write_image(&sandbox.current_image());
    sandbox.remove_tool("swaymsg");
    let output = sandbox.run_with([OsStr::new("wall-fill"), sandbox.current_image().as_os_str()]);
    assert_eq!(code(&output), 0);
    let convert = sandbox
        .invocations()
        .into_iter()
        .find(|call| call.tool == "convert")
        .unwrap();
    assert_eq!(convert.arguments[2], "1920x1080^");
}

#[test]
fn temporary_files_are_removed_on_every_path() {
    let sandbox = Sandbox::new("temp-cleanup");
    sandbox.write_image(&sandbox.current_image());
    sandbox.run_with([
        OsStr::new("mv"),
        sandbox.current_image().as_os_str(),
        sandbox.home.join("dest").as_os_str(),
    ]);
    assert!(sandbox.home.join("tmp").is_dir());
    assert!(sandbox.temp_files().is_empty());
}

#[test]
fn messages_are_written_to_stderr_without_a_trailing_flush_problem() {
    let sandbox = Sandbox::new("messages");
    let output = sandbox.run(&["not-an-action"]);
    assert_eq!(code(&output), 2);
    assert!(output.stdout.is_empty());
    assert_eq!(stderr(&output), "Unknown action: not-an-action\n");
}
