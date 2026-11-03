//! Hermetic tests for the `cursor-stretch` port.

mod support;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_cursor-stretch");

#[test]
fn status_prints_the_current_value() {
    let sandbox = Sandbox::new("cursor-status");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["status"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"dynamic_cursors enabled=true\n");
    assert_eq!(
        sandbox.calls("hyprctl"),
        vec![call(
            "hyprctl",
            &["-j", "getoption", "plugin:dynamic_cursors:enabled"]
        )]
    );
}

#[test]
fn status_reports_false_and_null_like_jq() {
    let sandbox = Sandbox::new("cursor-status-values");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["status"], &[("FAKE_GETOPTION", r#"{"bool":false}"#)]);
    assert_eq!(outcome.stdout, b"dynamic_cursors enabled=false\n");

    sandbox.reset();
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["status"], &[("FAKE_GETOPTION", r#"{"other":1}"#)]);
    assert_eq!(outcome.stdout, b"dynamic_cursors enabled=null\n");
}

#[test]
fn on_and_off_write_the_eval_snippet() {
    let sandbox = Sandbox::new("cursor-eval");
    for (verb, expected) in [("on", "true"), ("off", "false")] {
        sandbox.reset();
        sandbox.install_default_fakes();
        let outcome = sandbox.run(BIN, &[verb]);
        assert_eq!(outcome.code, 0, "verb {verb}");
        assert_eq!(
            sandbox.eval_snippet(),
            format!(
                "\nhl.config({{ plugin = {{ dynamic_cursors = {{ enabled = {expected} }} }} }})"
            )
            .into_bytes()
        );
        assert_eq!(
            sandbox.notifications(),
            vec![vec![
                b"-t".to_vec(),
                b"1200".to_vec(),
                format!("cursor stretch: {expected}").into_bytes()
            ]]
        );
        assert_eq!(
            sandbox.calls("hyprctl").len(),
            2,
            "getoption then eval, got {}",
            render(&sandbox.calls("hyprctl"))
        );
    }
}

#[test]
fn toggle_flips_the_current_value() {
    let sandbox = Sandbox::new("cursor-toggle");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["toggle"]);
    assert_eq!(outcome.code, 0);
    assert!(str_of(&sandbox.eval_snippet()).contains("enabled = false"));

    sandbox.reset();
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["toggle"], &[("FAKE_GETOPTION", r#"{"bool":false}"#)]);
    assert_eq!(outcome.code, 0);
    assert!(str_of(&sandbox.eval_snippet()).contains("enabled = true"));
}

#[test]
fn unknown_verb_prints_usage_and_exits_2() {
    let sandbox = Sandbox::new("cursor-usage");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["bogus"]);
    assert_eq!(outcome.code, 2);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(
        outcome.stderr,
        b"Usage: cursor-stretch [on|off|toggle|status]\n"
    );
    // The original reads the option before it parses the verb.
    assert_eq!(sandbox.calls("hyprctl").len(), 1);
    assert!(sandbox.eval_snippet().is_empty());
}

#[test]
fn missing_notify_send_leaves_status_1() {
    let sandbox = Sandbox::new("cursor-nonotify");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("notify-send")).expect("drop fake notify-send");
    let outcome = sandbox.run(BIN, &["on"]);
    assert_eq!(outcome.code, 1);
    assert!(!sandbox.eval_snippet().is_empty(), "eval must still run");
}

#[test]
fn eval_failure_is_fatal() {
    let sandbox = Sandbox::new("cursor-evalfail");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["on"], &[("FAKE_HYPRCTL_EVAL_EXIT", "3")]);
    assert_eq!(outcome.code, 3);
    assert!(sandbox.notifications().is_empty());
}

#[test]
fn failing_notify_send_propagates_the_status() {
    let sandbox = Sandbox::new("cursor-notifyfail");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["on"], &[("FAKE_NOTIFY_EXIT", "4")]);
    assert_eq!(outcome.code, 4);
}
