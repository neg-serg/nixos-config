//! Hermetic tests for the `kitty-font-zoom` port.
//!
//! Every test uses its own fake kitty pid: the socket lives at `/tmp/kitty-<pid>`
//! and cargo runs the tests in parallel.

mod support;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_kitty-font-zoom");

fn active_window(pid: u32) -> String {
    format!(r#"{{"pid":{pid}}}"#)
}

fn kitty_envs(sandbox: &Sandbox, pid: u32) -> Vec<(&'static str, String)> {
    sandbox.install_default_fakes();
    drop(bind_kitty_socket(pid));
    vec![("FAKE_ACTIVEWINDOW", active_window(pid))]
}

fn as_refs<'a>(pairs: &'a [(&'static str, String)]) -> Vec<(&'static str, &'a str)> {
    pairs
        .iter()
        .map(|(name, value)| (*name, value.as_str()))
        .collect()
}

#[test]
fn usage_exits_2() {
    let sandbox = Sandbox::new("kfz-usage");
    sandbox.install_default_fakes();
    for arguments in [vec![], vec!["bogus"]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 2);
        assert_eq!(outcome.stdout, b"");
        assert_eq!(
            outcome.stderr,
            b"Usage: kitty-font-zoom up|down|reset|off|on|toggle\n"
        );
    }
}

#[test]
fn empty_activewindow_exits_0() {
    let sandbox = Sandbox::new("kfz-empty");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["up"], &[("FAKE_ACTIVEWINDOW", "")]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("kitten").is_empty());
}

#[test]
fn missing_pid_exits_0() {
    let sandbox = Sandbox::new("kfz-nopid");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["up"], &[("FAKE_ACTIVEWINDOW", r#"{"pid":null}"#)]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("kitten").is_empty());
}

#[test]
fn missing_socket_exits_0() {
    let sandbox = Sandbox::new("kfz-nosock");
    sandbox.install_default_fakes();
    let pid = 5201;
    remove_kitty_socket(pid);
    let window = active_window(pid);
    let outcome = sandbox.run_env(BIN, &["up"], &[("FAKE_ACTIVEWINDOW", window.as_str())]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("kitten").is_empty());
}

#[test]
fn zoom_verbs_send_the_original_arguments() {
    let sandbox = Sandbox::new("kfz-zoom");
    let pid = 5202;
    let pairs = kitty_envs(&sandbox, pid);
    for (verb, argument) in [("up", "+0.5"), ("down", "-0.5"), ("reset", "0")] {
        sandbox.reset();
        sandbox.install_default_fakes();
        drop(bind_kitty_socket(pid));
        let outcome = sandbox.run_env(BIN, &[verb], &as_refs(&pairs));
        assert_eq!(outcome.code, 0, "verb {verb}");
        assert_eq!(
            sandbox.calls("kitten"),
            vec![call(
                "kitten",
                &[
                    "@",
                    "--to",
                    &format!("unix:/tmp/kitty-{pid}"),
                    "set-font-size",
                    "--",
                    argument
                ]
            )],
            "verb {verb}"
        );
    }
    remove_kitty_socket(pid);
}

#[test]
fn off_and_on_keep_the_doubled_prefix() {
    let sandbox = Sandbox::new("kfz-var");
    let pid = 5203;
    let pairs = kitty_envs(&sandbox, pid);
    for verb in ["off", "on"] {
        sandbox.reset();
        sandbox.install_default_fakes();
        drop(bind_kitty_socket(pid));
        let outcome = sandbox.run_env(BIN, &[verb], &as_refs(&pairs));
        assert_eq!(outcome.code, 0, "verb {verb}");
        assert_eq!(
            sandbox.calls("kitten"),
            vec![call(
                "kitten",
                &[
                    "@",
                    "--to",
                    &format!("unix:/tmp/kitty-{pid}"),
                    "set-user-vars",
                    &format!("font_zoom=font_zoom={verb}")
                ]
            )],
            "verb {verb}"
        );
    }
    remove_kitty_socket(pid);
}

#[test]
fn toggle_reads_the_variable_then_flips_it() {
    let sandbox = Sandbox::new("kfz-toggle");
    let pid = 5204;
    let pairs = kitty_envs(&sandbox, pid);
    for (current, next) in [
        ("font_zoom=off", "font_zoom=on"),
        ("font_zoom=on", "font_zoom=off"),
    ] {
        sandbox.reset();
        sandbox.install_default_fakes();
        drop(bind_kitty_socket(pid));
        let mut overrides = as_refs(&pairs);
        overrides.push(("FAKE_KITTEN_VARS", current));
        let outcome = sandbox.run_env(BIN, &["toggle"], &overrides);
        assert_eq!(outcome.code, 0);
        let calls = sandbox.calls("kitten");
        assert_eq!(calls.len(), 2, "current {current}: {}", render(&calls));
        assert_eq!(calls[0][4], "set-user-vars");
        assert_eq!(calls[0].len(), 5, "the probe has no value argument");
        assert_eq!(calls[1][4], "set-user-vars");
        assert_eq!(calls[1][5], next);
    }
    remove_kitty_socket(pid);
}

#[test]
fn hyprctl_failure_exits_0() {
    let sandbox = Sandbox::new("kfz-hyprfail");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["up"], &[("FAKE_HYPRCTL_AW_EXIT", "1")]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("kitten").is_empty());
}
