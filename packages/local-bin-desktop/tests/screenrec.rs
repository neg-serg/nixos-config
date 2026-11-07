//! Hermetic tests for the `screenrec` port.
//!
//! The fake `wf-recorder` and the fake sound sidecar stop themselves
//! (`kill -STOP $$`) so they look alive to the liveness probe and to `kill -0`;
//! the tests reap them afterwards, the sidecar through the state file.

mod support;

use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use local_bin_desktop::json::Json;
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_screenrec");
const DATE: &str = "20260102-03.04.05";

fn recordings(sandbox: &Sandbox) -> PathBuf {
    sandbox.home.join("vid/recordings")
}

fn kill_fake(sandbox: &Sandbox) {
    let text = str_of(&sandbox.read(&sandbox.wfrec_pid));
    if let Ok(pid) = text.trim().parse::<i32>() {
        let _ = kill(Pid::from_raw(pid), Signal::SIGKILL);
        let _ = kill(Pid::from_raw(pid), Signal::SIGCONT);
    }
    // The sound sidecar is a stopped process of its own: it outlives the
    // recorder in the sandbox unless the state file names it.
    if let Ok(bytes) = std::fs::read(sandbox.statefile()) {
        if let Ok(json) = Json::parse(&bytes) {
            if let Some(pid) = json.get("audio_pid").and_then(Json::as_number) {
                let pid = pid as i32;
                if pid > 0 {
                    let _ = kill(Pid::from_raw(pid), Signal::SIGKILL);
                    let _ = kill(Pid::from_raw(pid), Signal::SIGCONT);
                }
            }
        }
    }
    let _ = std::fs::remove_file(sandbox.pidfile());
    let _ = std::fs::remove_file(sandbox.statefile());
}

fn dated_env<'a>(date: &'a str) -> Vec<(&'a str, &'a str)> {
    vec![("FAKE_DATE_OUT", date)]
}

#[test]
fn start_in_screen_mode_writes_the_pidfile() {
    let sandbox = Sandbox::new("sr-start");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");

    let pidfile = sandbox.pidfile();
    let pid = str_of(&sandbox.read(&pidfile));
    assert_eq!(pid.trim(), str_of(&sandbox.read(&sandbox.wfrec_pid)).trim());
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-u".to_vec(),
            b"low".to_vec(),
            b"Screen Recording".to_vec(),
            b"Recording started...".to_vec(),
        ]]
    );
    let expected = format!("{}/rec-{DATE}.mp4", recordings(&sandbox).display());
    // No jq in the sandbox, so the hyprctl output probe is skipped exactly like
    // the original's `command -v jq` guard, and `wf-recorder -L` is asked once
    // for the output count.
    assert_eq!(
        sandbox.calls("wf-recorder"),
        vec![
            call("wf-recorder", &["-L"]),
            call(
                "wf-recorder",
                &[
                    "-c",
                    "libx264rgb",
                    "-r",
                    "60",
                    "-p",
                    "crf=20",
                    "-p",
                    "preset=superfast",
                    "-f",
                    &expected
                ]
            )
        ]
    );
    assert_eq!(
        sandbox.calls("date"),
        vec![call("date", &["+%Y%m%d-%H.%M.%S"])]
    );
    assert!(recordings(&sandbox).is_dir(), "the directory is created");
    kill_fake(&sandbox);
}

#[test]
fn area_inside_the_output_adds_geometry_and_output() {
    let sandbox = Sandbox::new("sr-area-in");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    sandbox.fake("jq", "exit 0\n");
    let outcome = sandbox.run_env(
        BIN,
        &["area"],
        &[
            ("FAKE_DATE_OUT", DATE),
            ("FAKE_SLURP_OUT", "100 200 300 400"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("slurp"),
        vec![call("slurp", &["-f", "%x %y %w %h"])]
    );
    let recorder = &sandbox.calls("wf-recorder")[0];
    let index = recorder
        .iter()
        .position(|argument| argument == "-g")
        .expect("-g present");
    assert_eq!(recorder[index + 1], "100,200 300x400");
    let index = recorder
        .iter()
        .position(|argument| argument == "-o")
        .expect("-o present");
    assert_eq!(recorder[index + 1], "DP-1");
    kill_fake(&sandbox);
}

#[test]
fn area_outside_the_output_drops_the_output_argument() {
    let sandbox = Sandbox::new("sr-area-out");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    sandbox.fake("jq", "exit 0\n");
    let outcome = sandbox.run_env(
        BIN,
        &["area"],
        &[
            ("FAKE_DATE_OUT", DATE),
            ("FAKE_SLURP_OUT", "100 200 300 400"),
            (
                "FAKE_MONITORS",
                r#"[{"name":"DP-1","focused":true,"x":500,"y":500,"width":2560,"height":1440,"scale":1}]"#,
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    let recorder = &sandbox.calls("wf-recorder")[0];
    assert!(recorder.iter().any(|argument| argument == "-g"));
    assert!(
        !recorder.iter().any(|argument| argument == "-o"),
        "{}",
        render(&sandbox.calls("wf-recorder"))
    );
    kill_fake(&sandbox);
}

#[test]
fn cancelled_slurp_exits_0_without_recording() {
    let sandbox = Sandbox::new("sr-cancel");
    sandbox.install_default_fakes();
    // A cancelled selection is an EOF without a newline: `read` fails and the
    // script exits before wf-recorder is even considered.
    sandbox.fake("slurp", "printf '%s' ''\nexit 0\n");
    let outcome = sandbox.run_env(BIN, &["area"], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("wf-recorder").is_empty());
    assert!(!sandbox.pidfile().exists());
}

#[test]
fn recorder_that_dies_right_away_is_reported() {
    let sandbox = Sandbox::new("sr-die");
    sandbox.install_default_fakes();
    assert!(
        sandbox.install_real_sleep(),
        "test environment needs a real sleep"
    );
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[("FAKE_DATE_OUT", DATE), ("FAKE_WFREC_DIE", "1")],
    );
    assert_eq!(outcome.code, 1);
    assert!(!sandbox.pidfile().exists());
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-u".to_vec(),
            b"low".to_vec(),
            b"Screen Recording".to_vec(),
            b"Recording failed to start".to_vec(),
        ]]
    );
}

#[test]
fn missing_recorder_is_reported_like_the_shell() {
    let sandbox = Sandbox::new("sr-missing");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("wf-recorder")).expect("drop fake");
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 1);
    let stderr = str_of(&outcome.stderr);
    assert!(
        stderr.contains(": line 110: wf-recorder: command not found\n"),
        "{stderr}"
    );
    assert_eq!(
        sandbox.notifications()[0][3],
        b"Recording failed to start".to_vec()
    );
}

#[test]
fn stop_signals_the_running_recorder() {
    let sandbox = Sandbox::new("sr-stop");
    sandbox.install_default_fakes();
    // A recorder that blocks until SIGINT instead of stopping itself.
    sandbox.fake(
        "wf-recorder",
        "printf '%s' $$ > \"$FAKE_WFREC_PIDFILE\"\nIFS= read -r line\n",
    );
    let mut child = sandbox.spawn_fake("wf-recorder", &[]);
    let pid = child.id();
    sandbox.write_pidfile(pid);
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-u".to_vec(),
            b"low".to_vec(),
            b"Screen Recording".to_vec(),
            b"Recording stopped".to_vec(),
        ]]
    );
    assert!(!sandbox.pidfile().exists());
    let _ = child.kill();
    let _ = child.wait();
}

#[test]
fn stale_pidfile_does_not_block_a_new_recording() {
    let sandbox = Sandbox::new("sr-stale");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    sandbox.write_pidfile(999_999);
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    // A dead pid makes `is_recording` false, so the toggle starts recording and
    // overwrites the pidfile. (The stale-file removal in `stop_recording` is
    // unreachable in the original, so it is not emulated as a cleanup step.)
    assert_eq!(
        sandbox.notifications()[0][3],
        b"Recording started...".to_vec()
    );
    let pid = str_of(&sandbox.read(&sandbox.pidfile()));
    assert_eq!(pid.trim(), str_of(&sandbox.read(&sandbox.wfrec_pid)).trim());
    kill_fake(&sandbox);
}

#[test]
fn single_output_is_taken_from_wf_recorder_listing() {
    let sandbox = Sandbox::new("sr-single");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("FAKE_DATE_OUT", DATE),
            ("FAKE_WFREC_LIST", "output Name: DP-1\n\tOutput DP-1\n"),
        ],
    );
    assert_eq!(outcome.code, 0);
    let all = sandbox.calls("wf-recorder");
    let recorder = all
        .iter()
        .find(|call| call.len() > 2)
        .expect("the recorder start call");
    let index = recorder
        .iter()
        .position(|argument| argument == "-o")
        .unwrap_or_else(|| panic!("-o present: {}", render(&all)));
    assert_eq!(recorder[index + 1], "DP-1");
    assert_eq!(
        sandbox
            .calls("wf-recorder")
            .iter()
            .filter(|call| call.len() == 2 && call[1] == "-L")
            .count(),
        2,
        "the shell asks twice: once for the count, once for the name: {}",
        render(&all)
    );
    kill_fake(&sandbox);
}

#[test]
fn unknown_mode_records_the_whole_screen() {
    // `screenrec` ignores unknown modes and records the whole screen.
    let sandbox = Sandbox::new("sr-unknown");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    let outcome = sandbox.run_env(BIN, &["bogus"], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    let recorder: Vec<_> = sandbox
        .calls("wf-recorder")
        .into_iter()
        .filter(|call| call.len() > 2)
        .collect();
    assert_eq!(
        recorder.len(),
        1,
        "{}",
        render(&sandbox.calls("wf-recorder"))
    );
    kill_fake(&sandbox);
}

fn now_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn state_of(sandbox: &Sandbox) -> Json {
    let bytes = sandbox.read(&sandbox.statefile());
    Json::parse(&bytes).unwrap_or_else(|_| panic!("{} is JSON", str_of(&bytes)))
}

#[test]
fn start_records_microphone_and_system_sound() {
    let sandbox = Sandbox::new("sr-audio");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.notifications()[0][3],
        b"Recording started...".to_vec()
    );

    let calls = sandbox.calls("ffmpeg");
    assert_eq!(calls.len(), 1, "{}", render(&calls));
    let args = &calls[0];
    for expected in ["@DEFAULT_SOURCE@", "@DEFAULT_MONITOR@", "amix"] {
        assert!(
            args.iter().any(|argument| argument.contains(expected)),
            "{expected} missing: {}",
            render(&calls)
        );
    }
    let sidecar = args.last().expect("the sidecar path");
    assert!(
        sidecar.ends_with(&format!("/vid/recordings/rec-{DATE}.mka")),
        "{sidecar}"
    );

    let state = state_of(&sandbox);
    assert!(str_of(&state.get("video").unwrap().raw()).ends_with(&format!("rec-{DATE}.mp4")));
    assert!(str_of(&state.get("audio").unwrap().raw()).ends_with(&format!("rec-{DATE}.mka")));
    assert!(
        state.get("audio_pid").unwrap().as_number().unwrap() > 0.0,
        "the sidecar is alive"
    );
    kill_fake(&sandbox);
}

#[test]
fn start_without_ffmpeg_keeps_the_video() {
    let sandbox = Sandbox::new("sr-noaudio");
    sandbox.install_default_fakes();
    assert!(sandbox.install_real_sleep(), "needs a real sleep");
    std::fs::remove_file(sandbox.bin.join("ffmpeg")).expect("drop the sidecar fake");
    let outcome = sandbox.run_env(BIN, &[], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.notifications()[0][3],
        b"Recording started (no audio)".to_vec()
    );
    let state = state_of(&sandbox);
    assert_eq!(state.get("audio_pid").unwrap().as_number(), Some(0.0));
    assert_eq!(state.get("audio").unwrap().as_str(), Some(&b""[..]));
    kill_fake(&sandbox);
}

#[test]
fn status_without_a_take_is_off() {
    let sandbox = Sandbox::new("sr-status-idle");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["status"], &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"{\"screen\":false}\n");
    assert!(sandbox.notifications().is_empty());
}

#[test]
fn status_reports_the_take_its_sound_and_its_clock() {
    let sandbox = Sandbox::new("sr-status-live");
    sandbox.install_default_fakes();
    let mut recorder = sandbox.spawn_fake("wf-recorder", &[]);
    let recorder_pid = recorder.id();
    sandbox.write_pidfile(recorder_pid);
    let mut audio = sandbox.spawn_fake("ffmpeg", &[]);
    let audio_pid = audio.id();
    let started = now_seconds() - 42;
    std::fs::write(
        sandbox.statefile(),
        format!(
            "{{\"video\":\"/tmp/v.mp4\",\"audio\":\"/tmp/a.mka\",\"started\":{started},\"audio_pid\":{audio_pid}}}"
        ),
    )
    .expect("write state");

    let outcome = sandbox.run_env(BIN, &["status"], &[]);
    assert_eq!(outcome.code, 0);
    let line = Json::parse(&outcome.stdout).expect("one JSON line");
    assert!(line.get("screen").map(Json::truthy).unwrap_or(false));
    assert!(line.get("audio").map(Json::truthy).unwrap_or(false));
    let elapsed = line.get("elapsed").and_then(Json::as_number).unwrap();
    assert!(
        (41.0..=45.0).contains(&elapsed),
        "elapsed {elapsed} around 42"
    );
    assert_eq!(
        line.get("pid").and_then(Json::as_number),
        Some(recorder_pid as f64)
    );

    let _ = kill(Pid::from_raw(audio_pid as i32), Signal::SIGKILL);
    let _ = kill(Pid::from_raw(recorder_pid as i32), Signal::SIGKILL);
    let _ = audio.wait();
    let _ = recorder.wait();
    let _ = std::fs::remove_file(sandbox.statefile());
}

#[test]
fn stop_while_idle_never_starts() {
    let sandbox = Sandbox::new("sr-stop-idle");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["stop"], &dated_env(DATE));
    assert_eq!(outcome.code, 0);
    assert!(sandbox.notifications().is_empty());
    assert!(!sandbox.pidfile().exists());
    assert!(!sandbox.statefile().exists());
    assert!(
        sandbox
            .calls("wf-recorder")
            .iter()
            .all(|call| call.len() == 2 && call[1] == "-L"),
        "{}",
        render(&sandbox.calls("wf-recorder"))
    );
}
