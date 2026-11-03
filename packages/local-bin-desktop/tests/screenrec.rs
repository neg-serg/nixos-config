//! Hermetic tests for the `screenrec` port.
//!
//! The fake `wf-recorder` stops itself (`kill -STOP $$`) so it looks alive to
//! the liveness probe and to `kill -0`; the tests reap it afterwards.

mod support;

use std::path::PathBuf;

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
    let _ = std::fs::remove_file(sandbox.pidfile());
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
