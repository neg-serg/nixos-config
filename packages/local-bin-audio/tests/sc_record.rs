//! Hermetic tests for the `sc-record` port: parameter handling, the engine
//! probe, the `timeout pw-record` argv and the `set -e` status propagation.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_sc-record");

const PWLINK: &str = "printf '%s' \"${FAKE_PWLINK_OUT:-}\"; exit \"${FAKE_PWLINK_CODE:-0}\"\n";
const TIMEOUT: &str = "exit \"${FAKE_TIMEOUT_CODE:-0}\"\n";

const LINKED: &str = "SuperCollider:out_1\nSuperCollider:out_2\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("pw-link", PWLINK);
    sandbox.fake("timeout", TIMEOUT);
    sandbox
}

#[test]
fn a_missing_output_argument_is_a_parameter_error() {
    let sandbox = fixture("no-arg");
    for args in [vec![], vec![""]] {
        let outcome = sandbox.run(&args);
        assert_eq!(outcome.code, 1);
        assert_eq!(outcome.stdout, b"");
        assert_eq!(
            text(&outcome.stderr),
            format!(
                "{}: line 10: 1: usage: sc-record <out.wav> [seconds]\n",
                sandbox.program().display()
            )
        );
    }
    assert_eq!(sandbox.log(), "");
}

#[test]
fn a_missing_engine_link_is_reported() {
    let sandbox = fixture("no-engine");
    let outcome = sandbox.run(&["out.wav"]);
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(
        text(&outcome.stderr),
        "sc-record: SuperCollider out_1 not found — engine not running?\n"
    );
    assert!(sandbox.log_lines_for("timeout").is_empty());
}

#[test]
fn a_failing_pw_link_selects_the_error_branch() {
    let sandbox = fixture("link-fail");
    let outcome = sandbox.run_env(
        &["out.wav"],
        &[("FAKE_PWLINK_OUT", LINKED), ("FAKE_PWLINK_CODE", "3")],
    );
    assert_eq!(outcome.code, 1);
    assert!(text(&outcome.stderr).contains("SuperCollider out_1 not found"));
}

#[test]
fn a_default_recording_uses_sixty_seconds() {
    let sandbox = fixture("default");
    let outcome = sandbox.run_env(&["out.wav"], &[("FAKE_PWLINK_OUT", LINKED)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "sc-record: recording 60s -> out.wav\nsc-record: done -> out.wav\n"
    );
    assert_eq!(
        sandbox.log_lines_for("timeout"),
        vec!["timeout\t60\tpw-record\t--target\tplayback.game-stereo\tout.wav"]
    );
}

#[test]
fn a_custom_duration_is_forwarded() {
    let sandbox = fixture("custom");
    let outcome = sandbox.run_env(&["take.wav", "12"], &[("FAKE_PWLINK_OUT", LINKED)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.log_lines_for("timeout"),
        vec!["timeout\t12\tpw-record\t--target\tplayback.game-stereo\ttake.wav"]
    );
}

#[test]
fn an_empty_duration_uses_the_default() {
    let sandbox = fixture("empty-secs");
    let outcome = sandbox.run_env(&["out.wav", ""], &[("FAKE_PWLINK_OUT", LINKED)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.log_lines_for("timeout"),
        vec!["timeout\t60\tpw-record\t--target\tplayback.game-stereo\tout.wav"]
    );
}

#[test]
fn a_timeout_status_skips_the_done_message() {
    let sandbox = fixture("timeout-status");
    let outcome = sandbox.run_env(
        &["out.wav", "5"],
        &[("FAKE_PWLINK_OUT", LINKED), ("FAKE_TIMEOUT_CODE", "124")],
    );
    assert_eq!(outcome.code, 124);
    assert_eq!(
        text(&outcome.stdout),
        "sc-record: recording 5s -> out.wav\n"
    );
}

#[test]
fn a_missing_timeout_is_fatal() {
    let sandbox = fixture("no-timeout");
    sandbox.remove_fake("timeout");
    let outcome = sandbox.run_env(&["out.wav"], &[("FAKE_PWLINK_OUT", LINKED)]);
    assert_eq!(outcome.code, 127);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "{}: line 19: timeout: command not found\n",
            sandbox.program().display()
        )
    );
    assert_eq!(
        text(&outcome.stdout),
        "sc-record: recording 60s -> out.wav\n"
    );
}

#[test]
fn a_signalled_timeout_propagates_the_signal_status() {
    let sandbox = fixture("signalled");
    sandbox.fake("timeout", "kill -TERM $$\n");
    let outcome = sandbox.run_env(&["out.wav"], &[("FAKE_PWLINK_OUT", LINKED)]);
    assert_eq!(outcome.code, 143);
    assert_eq!(
        text(&outcome.stdout),
        "sc-record: recording 60s -> out.wav\n"
    );
}

#[test]
fn a_missing_pw_link_degrades_to_the_engine_error() {
    let sandbox = fixture("no-pwlink");
    sandbox.remove_fake("pw-link");
    let outcome = sandbox.run(&["out.wav"]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        text(&outcome.stderr),
        "sc-record: SuperCollider out_1 not found — engine not running?\n"
    );
}
