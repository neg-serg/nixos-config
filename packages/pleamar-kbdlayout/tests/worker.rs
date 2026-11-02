//! Hermetic integration tests for the worker.
//!
//! Every test builds its own temporary tree: a fake `hyprctl` (and where the
//! event stream is exercised, a fake `socat`) is generated as an executable
//! shell script, device/submap answers live in files next to it, and the
//! Hyprland discovery environment points into the same tree so a real
//! compositor on the test host can never leak in.

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixListener;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::sync::{Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const BIN: &str = env!("CARGO_BIN_EXE_pleamar-kbdlayout");
const HANDSHAKE: &str = r#"{"ok":true,"worker":"kbdlayout","version":1,"topics":["layout"]}"#;

const DEVICES: &str = concat!(
    r#"{"keyboards":["#,
    r#"{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"},"#,
    r#"{"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0,"active_keymap":"German"},"#,
    r#"{"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":0,"active_keymap":"French"}"#,
    r#"]}"#
);

/// The same data object the shipped shell worker emits for [`DEVICES`].
const EXPECTED_DATA: &str = concat!(
    r#"{"device":"kbd-main","main":true,"index":1,"keymap":"Russian","code":"ru","layouts":["us","ru"],"#,
    r#""submap":"","caps":false,"keyboards":[{"name":"kbd-main","main":true},"#,
    r#"{"name":"virtual-keyboard","main":false},{"name":"kbd-2","main":false}]}"#
);

static SEQUENCE: AtomicU64 = AtomicU64::new(0);

/// A freshly written executable must not be handed to `exec` while another
/// test thread is between `fork` and `exec`: the forked child temporarily
/// holds a write descriptor to it, and Linux answers ETXTBSY. The tests are
/// hermetic and fast, so running them one at a time is the cheapest way to
/// remove that window. (It is a test-only fork/exec artifact: the worker never
/// writes the programs it executes.)
static EXCLUSIVE: Mutex<()> = Mutex::new(());

fn exclusive() -> MutexGuard<'static, ()> {
    EXCLUSIVE.lock().unwrap_or_else(|error| error.into_inner())
}

struct Scratch {
    path: PathBuf,
}

impl Scratch {
    fn new(label: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let path = std::env::temp_dir().join(format!(
            "pleamar-kbdlayout-it-{label}-{}-{nanos}-{}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).expect("scratch directory");
        Self { path }
    }

    fn path(&self) -> &Path {
        &self.path
    }

    fn write(&self, name: &str, contents: &str) -> PathBuf {
        let path = self.path.join(name);
        fs::write(&path, contents).expect("fixture file");
        path
    }

    fn script(&self, name: &str, body: &str) -> PathBuf {
        let path = self.write(name, body);
        let mut permissions = fs::metadata(&path).expect("metadata").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("chmod");
        path
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// A fake compositor and the files it reads, plus the isolation environment.
struct Fixture {
    scratch: Scratch,
    hyprctl: PathBuf,
    devices: PathBuf,
    submap: PathBuf,
    switch_log: PathBuf,
    runtime: PathBuf,
    signature: String,
}

impl Fixture {
    fn new(label: &str) -> Self {
        let scratch = Scratch::new(label);
        let devices = scratch.write("devices.json", DEVICES);
        let submap = scratch.write("submap.txt", "default\n");
        let switch_log = scratch.path().join("switch.log");
        let runtime = scratch.path().join("runtime");
        fs::create_dir_all(&runtime).expect("runtime directory");
        let body = format!(
            "#!/bin/sh\n\
             case \"$1\" in\n\
               -j) cat '{}' ;;\n\
               submap) cat '{}' ;;\n\
               switchxkblayout) printf '%s %s\\n' \"$2\" \"$3\" >> '{}' ;;\n\
             esac\n",
            devices.display(),
            submap.display(),
            switch_log.display()
        );
        let hyprctl = scratch.script("hyprctl", &body);
        let signature = format!("pleamar-kbdlayout-test-{}", scratch.path().display());
        Self {
            scratch,
            hyprctl,
            devices,
            submap,
            switch_log,
            runtime,
            signature,
        }
    }

    fn set_devices(&self, devices: &str) {
        fs::write(&self.devices, devices).expect("devices");
    }

    fn set_submap(&self, submap: &str) {
        fs::write(&self.submap, format!("{submap}\n")).expect("submap");
    }

    fn switch_log(&self) -> String {
        fs::read_to_string(&self.switch_log).unwrap_or_default()
    }

    fn command(&self, arguments: &[&str]) -> Command {
        let mut command = Command::new(BIN);
        command
            .args(arguments)
            .env("PLEAMAR_HYPRCTL", &self.hyprctl)
            .env("XDG_RUNTIME_DIR", &self.runtime)
            .env("HYPRLAND_INSTANCE_SIGNATURE", &self.signature)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        command
    }

    /// Run to completion with `input` on stdin and collect everything.
    fn run(&self, arguments: &[&str], input: &str) -> Capture {
        let mut command = self.command(arguments);
        let mut child = command.spawn().expect("spawn worker");
        {
            let mut stdin = child.stdin.take().expect("stdin pipe");
            stdin.write_all(input.as_bytes()).expect("write stdin");
        }
        let stdout = child.stdout.take().expect("stdout pipe");
        let stderr = child.stderr.take().expect("stderr pipe");
        let stdout_thread = thread::spawn(move || read_all(stdout));
        let stderr_thread = thread::spawn(move || read_all(stderr));
        let status = wait_timeout(&mut child, Duration::from_secs(15), "worker");
        Capture {
            stdout: stdout_thread.join().expect("stdout thread"),
            stderr: stderr_thread.join().expect("stderr thread"),
            status,
        }
    }
}

struct Capture {
    stdout: String,
    stderr: String,
    status: ExitStatus,
}

fn read_all(mut reader: impl Read) -> String {
    let mut text = String::new();
    reader.read_to_string(&mut text).expect("read pipe");
    text
}

fn wait_timeout(child: &mut Child, limit: Duration, what: &str) -> ExitStatus {
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().expect("try_wait") {
            return status;
        }
        if start.elapsed() > limit {
            let _ = child.kill();
            let _ = child.wait();
            panic!("{what} did not finish within {limit:?}");
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn lines(text: &str) -> Vec<String> {
    text.lines().map(str::to_string).collect()
}

/// Replace the wall-clock `"t":<ms>` value so two runs compare equal.
fn normalize(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index..].starts_with(br#""t":"#) {
            output.extend_from_slice(br#""t":<n>"#);
            index += 4;
            while index < bytes.len() && bytes[index].is_ascii_digit() {
                index += 1;
            }
        } else {
            output.push(bytes[index]);
            index += 1;
        }
    }
    String::from_utf8(output).expect("utf-8")
}

fn data_of(line: &str) -> serde_json::Value {
    let value: serde_json::Value = serde_json::from_str(line).expect("protocol JSON");
    value["data"].clone()
}

fn expected_sample_line(caps: bool) -> String {
    let data = EXPECTED_DATA.replace(
        r#""caps":false"#,
        if caps {
            r#""caps":true"#
        } else {
            r#""caps":false"#
        },
    );
    format!(r#"{{"ok":true,"worker":"kbdlayout","topic":"layout","t":<n>,"data":{data}}}"#)
}

fn bind_socket(directory: &Path) -> (UnixListener, PathBuf) {
    fs::create_dir_all(directory).expect("socket directory");
    let path = directory.join(".socket2.sock");
    let listener = UnixListener::bind(&path).expect("bind unix socket");
    (listener, path)
}

/// A running worker with stdin held open, for event/signal tests.
struct LiveWorker {
    child: Child,
    stdin: Option<ChildStdin>,
    channel: Receiver<Option<String>>,
    seen: Vec<String>,
}

impl LiveWorker {
    fn start(fixture: &Fixture, arguments: &[&str], environment: &[(&str, &str)]) -> Self {
        let mut command = fixture.command(arguments);
        for (key, value) in environment {
            command.env(key, value);
        }
        let mut child = command.spawn().expect("spawn worker");
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().expect("stdout pipe");
        let (sender, channel) = mpsc::channel();
        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                match line {
                    Ok(line) => {
                        if sender.send(Some(line)).is_err() {
                            return;
                        }
                    }
                    Err(_) => return,
                }
            }
            let _ = sender.send(None);
        });
        Self {
            child,
            stdin,
            channel,
            seen: Vec::new(),
        }
    }

    /// Next line, `None` when the stream ended or `timeout` elapsed.
    fn next_line(&mut self, timeout: Duration) -> Option<String> {
        match self.channel.recv_timeout(timeout) {
            Ok(Some(line)) => {
                self.seen.push(line.clone());
                Some(line)
            }
            Ok(None) | Err(RecvTimeoutError::Disconnected) => None,
            Err(RecvTimeoutError::Timeout) => None,
        }
    }

    fn close_stdin(&mut self) {
        let _ = self.stdin.take();
    }

    fn terminate(&mut self) {
        let pid = self.child.id().to_string();
        let status = Command::new("bash")
            .args(["-c", "kill -TERM \"$1\"", "_", &pid])
            .status()
            .expect("run kill");
        assert!(status.success(), "kill -TERM {pid} failed");
    }

    fn wait(&mut self, limit: Duration) -> ExitStatus {
        let status = wait_timeout(&mut self.child, limit, "live worker");
        self.close_stdin();
        status
    }
}

#[test]
fn help_prints_the_frozen_usage() {
    let _guard = exclusive();
    let fixture = Fixture::new("help");
    let capture = fixture.run(&["--help"], "");
    assert!(capture.status.success());
    assert!(capture.stderr.is_empty());
    assert_eq!(
        capture.stdout,
        concat!(
            "kbd.sh - keyboard-layout worker (JSON lines, INTERFACES.md §7)\n",
            "\n",
            "Usage:\n",
            "  kbd.sh [options] [command]\n",
            "\n",
            "Commands:\n",
            "  (none)                     run as the worker: handshake, subscribe, samples\n",
            "  switch [next|prev]         switch the current keyboard's layout once\n",
            "  switch DEVICE [next|prev]  switch a named keyboard once (default: next)\n",
            "\n",
            "Options:\n",
            "  --once               print the handshake and one sample, then exit\n",
            "  --socket PATH        Hyprland .socket2.sock (default: from\n",
            "                       $HYPRLAND_INSTANCE_SIGNATURE)\n",
            "  --interval-ms N      heartbeat cadence of the `layout` topic, 100..60000\n",
            "                       (default: 5000)\n",
            "  -h, --help           this text\n",
            "\n",
            "Topic: layout. Commands (JSON): subscribe, unsubscribe, set, sample, switch,\n",
            "stop; the plain line `switch …` is accepted too.\n",
            "\n",
            "Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"
        )
    );
}

#[test]
fn option_errors_exit_with_two_and_the_shell_text() {
    let _guard = exclusive();
    let fixture = Fixture::new("options");
    let cases: &[(&[&str], &str)] = &[
        (&["--interval-ms"], "--interval-ms needs a value"),
        (&["--socket"], "--socket needs a value"),
        (
            &["--interval-ms", "x"],
            "--interval-ms must be an integer (got 'x')",
        ),
        (&["--interval-ms", "99"], "--interval-ms must be 100..60000"),
        (
            &["--interval-ms", "60001"],
            "--interval-ms must be 100..60000",
        ),
        (&["--bogus"], "unknown argument '--bogus' (see --help)"),
    ];
    for (arguments, message) in cases {
        let capture = fixture.run(arguments, "");
        assert_eq!(capture.status.code(), Some(2), "arguments {arguments:?}");
        assert!(capture.stdout.is_empty(), "arguments {arguments:?}");
        assert_eq!(
            capture.stderr,
            format!("kbd: error: {message}\n"),
            "arguments {arguments:?}"
        );
    }
}

#[test]
fn missing_hyprctl_is_a_start_error() {
    let _guard = exclusive();
    let fixture = Fixture::new("no-hyprctl");
    let mut command = fixture.command(&["--once"]);
    command.env("PLEAMAR_HYPRCTL", "/nonexistent/pleamar-kbdlayout-hyprctl");
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "{\"ok\":false,\"worker\":\"kbdlayout\",\"err\":\"hyprctl not found\"}\n"
    );
    assert!(output.stderr.is_empty());
}

#[test]
fn once_emits_the_handshake_and_the_reference_sample() {
    let _guard = exclusive();
    let fixture = Fixture::new("once");
    let capture = fixture.run(&["--once"], "");
    assert!(capture.status.success());
    assert!(capture.stderr.is_empty());
    let output = lines(&capture.stdout);
    assert_eq!(output.len(), 2);
    assert_eq!(output[0], HANDSHAKE);
    let data = data_of(&output[1]);
    let caps = data["caps"].as_bool().expect("caps is a boolean");
    assert_eq!(
        normalize(&capture.stdout),
        format!("{HANDSHAKE}\n{}\n", expected_sample_line(caps))
    );
}

#[test]
fn once_reports_compositor_failures_as_error_samples() {
    let _guard = exclusive();
    // A failing `hyprctl -j devices`.
    let fixture = Fixture::new("devices-fail");
    fs::write(&fixture.devices, "ignored").expect("devices");
    let failing = fixture.scratch.script(
        "hyprctl",
        "#!/bin/sh\ncase \"$1\" in\n  -j) exit 1 ;;\n  submap) printf 'default\\n' ;;\nesac\n",
    );
    let mut command = fixture.command(&["--once"]);
    command.env("PLEAMAR_HYPRCTL", &failing);
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(stdout.contains(
        r#"{"ok":false,"worker":"kbdlayout","err":"hyprctl -j devices failed (is Hyprland running?)","#
    ));

    // A non-JSON answer.
    let fixture = Fixture::new("devices-json");
    let not_json = fixture.scratch.script(
        "hyprctl",
        "#!/bin/sh\ncase \"$1\" in\n  -j) printf 'not json\\n' ;;\n  submap) printf 'default\\n' ;;\nesac\n",
    );
    let mut command = fixture.command(&["--once"]);
    command.env("PLEAMAR_HYPRCTL", &not_json);
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(output.status.success());
    assert!(stdout.contains(
        r#"{"ok":false,"worker":"kbdlayout","err":"hyprctl -j devices did not return JSON","#
    ));
}

#[test]
fn once_uses_the_selection_fallbacks_and_the_submap() {
    let _guard = exclusive();
    let fixture = Fixture::new("selection");
    fixture.set_devices(
        r#"{"keyboards":[
            {"name":"virtual-keyboard","main":false,"layout":"de","active_layout_index":0,"active_keymap":"German"},
            {"name":"kbd-2","main":false,"layout":"fr,de","active_layout_index":1,"active_keymap":"German"}
        ]}"#,
    );
    fixture.set_submap("resize");
    let capture = fixture.run(&["--once"], "");
    let output = lines(&capture.stdout);
    let data = data_of(&output[1]);
    assert_eq!(data["device"], "kbd-2");
    assert_eq!(data["index"], 1);
    assert_eq!(data["keymap"], "German");
    assert_eq!(data["code"], "de");
    assert_eq!(data["submap"], "resize");
    assert_eq!(data["layouts"], serde_json::json!(["fr", "de"]));
    assert_eq!(
        data["keyboards"],
        serde_json::json!([
            {"name": "virtual-keyboard", "main": false},
            {"name": "kbd-2", "main": false}
        ])
    );

    // `default` and `reset` are reported as "".
    fixture.set_submap("default");
    let capture = fixture.run(&["--once"], "");
    let data = data_of(&lines(&capture.stdout)[1]);
    assert_eq!(data["submap"], "");

    // No keyboards at all: every field takes its shell default.
    fixture.set_devices("{}");
    let capture = fixture.run(&["--once"], "");
    let data = data_of(&lines(&capture.stdout)[1]);
    assert_eq!(data["device"], "");
    assert_eq!(data["main"], false);
    assert_eq!(data["index"], 0);
    assert_eq!(data["layouts"], serde_json::json!([]));
    assert_eq!(data["keyboards"], serde_json::json!([]));
}

#[test]
fn protocol_dialogue_matches_the_shell_acks_and_errors() {
    let _guard = exclusive();
    let fixture = Fixture::new("dialogue");
    let input = concat!(
        "{\"cmd\":\"subscribe\",\"topic\":\"layout\",\"interval_ms\":60000}\n",
        "{\"cmd\":\"sample\",\"topic\":\"layout\"}\n",
        "{\"cmd\":\"unsubscribe\",\"topic\":\"layout\"}\n",
        "{\"cmd\":\"sample\"}\n",
        "{\"cmd\":\"switch\",\"device\":\"kbd-main\",\"direction\":\"prev\"}\n",
        "{\"cmd\":\"switch\",\"direction\":\"sideways\"}\n",
        "{\"cmd\":\"subscribe\",\"topic\":\"nope\"}\n",
        "{\"cmd\":\"subscribe\",\"topic\":\"layout\",\"interval_ms\":100.0}\n",
        "{\"cmd\":\"set\"}\n",
        "{\"cmd\":\"bogus\"}\n",
        "not json\n",
        "{}\n",
        "switch kbd-2 prev\n",
        "nonsense here\n",
        "\n",
        "{\"cmd\":\"stop\"}\n"
    );
    let capture = fixture.run(
        &[
            "--interval-ms",
            "60000",
            "--socket",
            "/nonexistent/pleamar.sock",
        ],
        input,
    );
    assert!(capture.status.success());
    assert!(capture.stderr.is_empty());

    let output_lines = lines(&capture.stdout);
    let controls: Vec<String> = output_lines
        .iter()
        .filter(|line| !line.contains(r#""topic":"layout""#))
        .map(|line| normalize(line))
        .collect();
    assert_eq!(
        controls,
        vec![
            HANDSHAKE.to_string(),
            r#"{"ok":false,"worker":"kbdlayout","err":"hyprland event socket not available; polling hyprctl","t":<n>}"#.to_string(),
            r#"{"ok":true,"ack":"subscribe"}"#.to_string(),
            r#"{"ok":true,"ack":"sample"}"#.to_string(),
            r#"{"ok":true,"ack":"unsubscribe"}"#.to_string(),
            r#"{"ok":true,"ack":"sample"}"#.to_string(),
            r#"{"ok":true,"ack":"switch"}"#.to_string(),
            r#"{"ok":true,"ack":"switch"}"#.to_string(),
            r#"{"ok":false,"err":"switch: unknown direction 'sideways' (next|prev)"}"#.to_string(),
            r#"{"ok":false,"err":"unknown topic: nope"}"#.to_string(),
            r#"{"ok":false,"err":"interval_ms must be an integer"}"#.to_string(),
            r#"{"ok":false,"err":"set needs interval_ms"}"#.to_string(),
            r#"{"ok":false,"err":"unknown cmd: bogus"}"#.to_string(),
            r#"{"ok":false,"err":"unknown command: not json"}"#.to_string(),
            r#"{"ok":false,"err":"unknown cmd: "}"#.to_string(),
            r#"{"ok":true,"ack":"switch"}"#.to_string(),
            r#"{"ok":false,"err":"unknown command: nonsense here"}"#.to_string(),
            r#"{"ok":true,"ack":"stop"}"#.to_string(),
        ]
    );

    let samples: Vec<String> = lines(&capture.stdout)
        .into_iter()
        .filter(|line| line.contains(r#""topic":"layout""#))
        .collect();
    // One due sample, two from `sample`, one from the JSON switch, one from
    // the plain switch line, and the due sample that `subscribe` re-armed.
    assert_eq!(samples.len(), 6);
    let caps = data_of(&samples[0])["caps"].as_bool().expect("caps");
    for sample in &samples {
        assert_eq!(normalize(sample), expected_sample_line(caps));
    }
    assert_eq!(fixture.switch_log(), "kbd-main prev\nkbd-2 prev\n");
}

#[test]
fn closed_stdin_finishes_the_worker_after_the_fallback_sample() {
    let _guard = exclusive();
    let fixture = Fixture::new("closed-stdin");
    let capture = fixture.run(&[], "");
    assert!(capture.status.success());
    let output = lines(&capture.stdout);
    assert_eq!(output[0], HANDSHAKE);
    assert_eq!(output.len(), 2);
    assert!(output[1].contains(
        r#"{"ok":false,"worker":"kbdlayout","err":"hyprland event socket not available; polling hyprctl","#
    ));
}

#[test]
fn cli_switch_runs_once_and_samples() {
    let _guard = exclusive();
    let fixture = Fixture::new("switch-cli");
    let capture = fixture.run(&["switch", "kbd-main", "prev"], "");
    assert!(capture.status.success());
    let output = lines(&capture.stdout);
    assert_eq!(output.len(), 3);
    assert_eq!(output[0], HANDSHAKE);
    assert_eq!(output[1], r#"{"ok":true,"ack":"switch"}"#);
    let caps = data_of(&output[2])["caps"].as_bool().expect("caps");
    assert_eq!(normalize(&output[2]), expected_sample_line(caps));
    assert_eq!(fixture.switch_log(), "kbd-main prev\n");
}

#[test]
fn cli_switch_defaults_to_current_and_next() {
    let _guard = exclusive();
    let fixture = Fixture::new("switch-defaults");
    let capture = fixture.run(&["switch"], "");
    assert!(capture.status.success());
    assert_eq!(fixture.switch_log(), "current next\n");
}

#[test]
fn cli_switch_failure_is_an_error_sample_and_exit_zero() {
    let _guard = exclusive();
    let fixture = Fixture::new("switch-fail");
    let body = format!(
        "#!/bin/sh\ncase \"$1\" in\n  -j) cat '{}' ;;\n  submap) printf 'default\\n' ;;\n  switchxkblayout) printf 'first line\\nsecond line\\n' >&2; exit 6 ;;\nesac\n",
        fixture.devices.display()
    );
    let failing = fixture.scratch.script("hyprctl-failing", &body);
    let mut command = fixture.command(&["switch", "current", "next"]);
    command.env("PLEAMAR_HYPRCTL", &failing);
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    assert_eq!(output.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(
        r#"{"ok":false,"worker":"kbdlayout","err":"hyprctl switchxkblayout current next failed: second line","#
    ));
}

#[test]
fn cli_switch_unknown_direction_is_an_error_line_and_exit_zero() {
    let _guard = exclusive();
    let fixture = Fixture::new("switch-direction");
    let capture = fixture.run(&["switch", "kbd-main", "sideways"], "");
    assert!(capture.status.success());
    let output = lines(&capture.stdout);
    assert_eq!(output.len(), 3);
    assert_eq!(output[0], HANDSHAKE);
    assert_eq!(output[1], r#"{"ok":true,"ack":"switch"}"#);
    assert_eq!(
        output[2],
        r#"{"ok":false,"err":"switch: unknown direction 'sideways' (next|prev)"}"#
    );
    assert_eq!(fixture.switch_log(), "");
}

#[test]
fn unavailable_socket_falls_back_to_polling() {
    let _guard = exclusive();
    let fixture = Fixture::new("socket-missing");
    let capture = fixture.run(&["--socket", "/nonexistent/pleamar.sock"], "");
    assert!(capture.status.success());
    let output = lines(&capture.stdout);
    assert_eq!(output[0], HANDSHAKE);
    assert!(output[1].contains("hyprland event socket not available; polling hyprctl"));
}

#[test]
fn missing_socat_falls_back_to_polling() {
    let _guard = exclusive();
    let fixture = Fixture::new("socat-missing");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let mut command = fixture.command(&["--socket", &socket.to_string_lossy()]);
    command.env("PLEAMAR_SOCAT", "/nonexistent/pleamar-kbdlayout-socat");
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    drop(listener);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(r#""err":"socat not found; polling hyprctl""#));
}

#[test]
fn event_pipe_failure_falls_back_to_polling() {
    let _guard = exclusive();
    let fixture = Fixture::new("fifo-failure");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let socat = fixture.scratch.script("socat", "#!/bin/sh\nsleep 5\n");
    let missing = fixture.scratch.path().join("no-such-tmp");
    let mut command = fixture.command(&["--socket", &socket.to_string_lossy()]);
    command.env("PLEAMAR_SOCAT", &socat).env("TMPDIR", &missing);
    let mut child = command.spawn().expect("spawn");
    child.stdin.take();
    let output = child.wait_with_output().expect("output");
    drop(listener);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains(r#""err":"cannot create the event pipe; polling hyprctl""#));
}

#[test]
fn socket_events_emit_a_changed_sample() {
    let _guard = exclusive();
    let fixture = Fixture::new("socket-events");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let calls = fixture.scratch.path().join("calls");
    let first = fixture.scratch.write(
        "devices-first.json",
        r#"{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":0,"active_keymap":"English"}]}"#,
    );
    let second = fixture.scratch.write(
        "devices-second.json",
        r#"{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"}]}"#,
    );
    let body = format!(
        "#!/bin/sh\n\
         case \"$1\" in\n\
           -j) n=0; [ -f '{}' ] && n=$(cat '{}'); n=$((n+1)); printf '%s' \"$n\" > '{}';\n\
               if [ \"$n\" -eq 1 ]; then cat '{}'; else cat '{}'; fi ;;\n\
           submap) printf 'default\\n' ;;\n\
         esac\n",
        calls.display(),
        calls.display(),
        calls.display(),
        first.display(),
        second.display()
    );
    let hyprctl = fixture.scratch.script("hyprctl-events", &body);
    let socat = fixture.scratch.script(
        "socat",
        "#!/bin/sh\nsleep 0.25\nprintf 'activelayout>>Russian\\n'\nsleep 5\n",
    );
    let tmp = fixture.scratch.path().join("tmp");
    fs::create_dir_all(&tmp).expect("tmp");
    let mut command = fixture.command(&["--socket", &socket.to_string_lossy()]);
    command
        .env("PLEAMAR_HYPRCTL", &hyprctl)
        .env("PLEAMAR_SOCAT", &socat)
        .env("TMPDIR", &tmp);
    let mut child = command.spawn().expect("spawn");
    let stdin = child.stdin.take();
    let stdout = child.stdout.take().expect("stdout");
    let stderr = child.stderr.take().expect("stderr");
    let stderr_thread = thread::spawn(move || read_all(stderr));
    let mut reader = BufReader::new(stdout);
    let mut output = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut line = String::new();
    while Instant::now() < deadline {
        line.clear();
        let read = reader.read_line(&mut line).expect("read line");
        if read == 0 {
            break;
        }
        output.push(line.trim_end().to_string());
        if output.len() >= 3 {
            break;
        }
    }
    drop(stdin);
    let status = wait_timeout(&mut child, Duration::from_secs(5), "worker");
    drop(listener);
    assert!(status.success());
    assert!(stderr_thread.join().expect("stderr").is_empty());
    assert_eq!(output[0], HANDSHAKE);
    let first_sample = data_of(&output[1]);
    assert_eq!(first_sample["index"], 0);
    assert_eq!(first_sample["keymap"], "English");
    let second_sample = data_of(&output[2]);
    assert_eq!(second_sample["index"], 1);
    assert_eq!(second_sample["keymap"], "Russian");
    // The FIFO was consumed, not left in TMPDIR.
    let leftover: Vec<_> = fs::read_dir(&tmp)
        .expect("tmp dir")
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("pleamar-kbd."))
        .collect();
    assert!(leftover.is_empty(), "leftover fifo: {leftover:?}");
}

#[test]
fn socket_close_falls_back_to_polling() {
    let _guard = exclusive();
    let fixture = Fixture::new("socket-closed");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let socat = fixture.scratch.script("socat", "#!/bin/sh\nexit 0\n");
    let tmp = fixture.scratch.path().join("tmp");
    fs::create_dir_all(&tmp).expect("tmp");
    let mut command = fixture.command(&["--socket", &socket.to_string_lossy()]);
    command.env("PLEAMAR_SOCAT", &socat).env("TMPDIR", &tmp);
    let mut child = command.spawn().expect("spawn");
    let stdin = child.stdin.take();
    let stdout = child.stdout.take().expect("stdout");
    let stderr = child.stderr.take().expect("stderr");
    let stderr_thread = thread::spawn(move || read_all(stderr));
    let mut reader = BufReader::new(stdout);
    let mut output = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut line = String::new();
    while Instant::now() < deadline {
        line.clear();
        if reader.read_line(&mut line).expect("read line") == 0 {
            break;
        }
        output.push(line.trim_end().to_string());
        if output
            .iter()
            .any(|line| line.contains("event socket closed"))
        {
            break;
        }
    }
    drop(stdin);
    let status = wait_timeout(&mut child, Duration::from_secs(5), "worker");
    drop(listener);
    assert!(status.success());
    assert!(stderr_thread.join().expect("stderr").is_empty());
    assert_eq!(output[0], HANDSHAKE);
    assert!(
        output
            .iter()
            .any(|line| line.contains(r#""err":"hyprland event socket closed; polling hyprctl""#)),
        "no fallback error line in {output:?}"
    );
}

#[test]
fn sigterm_cleans_up_and_exits_zero() {
    let _guard = exclusive();
    let fixture = Fixture::new("sigterm");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let socat = fixture.scratch.script("socat", "#!/bin/sh\nsleep 5\n");
    let tmp = fixture.scratch.path().join("tmp");
    fs::create_dir_all(&tmp).expect("tmp");
    let mut worker = LiveWorker::start(
        &fixture,
        &[
            "--interval-ms",
            "60000",
            "--socket",
            &socket.to_string_lossy(),
        ],
        &[
            ("PLEAMAR_SOCAT", &socat.to_string_lossy()),
            ("TMPDIR", &tmp.to_string_lossy()),
        ],
    );
    assert_eq!(
        worker.next_line(Duration::from_secs(5)).as_deref(),
        Some(HANDSHAKE)
    );
    worker.terminate();
    let status = worker.wait(Duration::from_secs(5));
    drop(listener);
    assert!(status.success(), "exit status {status:?}");
    let leftover: Vec<_> = fs::read_dir(&tmp)
        .expect("tmp dir")
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("pleamar-kbd."))
        .collect();
    assert!(leftover.is_empty(), "leftover fifo: {leftover:?}");
}

#[test]
fn socket_threads_are_not_left_when_the_worker_is_finished() {
    let _guard = exclusive();
    // A worker with a live mock event stream accepted a `stop` and exited 0;
    // the fake `socat` must not keep the process alive.
    let fixture = Fixture::new("stop-socket");
    let (listener, socket) = bind_socket(fixture.scratch.path());
    let socat = fixture.scratch.script("socat", "#!/bin/sh\nsleep 5\n");
    let tmp = fixture.scratch.path().join("tmp");
    fs::create_dir_all(&tmp).expect("tmp");
    let mut command = fixture.command(&["--socket", &socket.to_string_lossy()]);
    command.env("PLEAMAR_SOCAT", &socat).env("TMPDIR", &tmp);
    let mut child = command.spawn().expect("spawn");
    {
        let mut stdin = child.stdin.take().expect("stdin");
        stdin
            .write_all(b"{\"cmd\":\"stop\"}\n")
            .expect("write stop");
    }
    let output = child.wait_with_output().expect("output");
    drop(listener);
    assert!(output.status.success());
    let stdout = String::from_utf8_lossy(&output.stdout);
    let output_lines = lines(&stdout);
    assert_eq!(output_lines[0], HANDSHAKE);
    assert!(output_lines.contains(&r#"{"ok":true,"ack":"stop"}"#.to_string()));
}
