//! Hermetic tests for the `unlock` port.

mod support;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_unlock");

#[test]
fn starts_an_agent_and_feeds_expect() {
    let sandbox = Sandbox::new("unlock-agent");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("FAKE_SSH_SOCK", "/tmp/agent.sock"),
            ("FAKE_SSH_PID", "999"),
            ("FAKE_PASS_KEY", "secret"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"Agent pid 999\n");
    assert_eq!(outcome.stderr, b"");
    assert_eq!(sandbox.calls("ssh-agent"), vec![call("ssh-agent", &["-s"])]);
    assert_eq!(
        sandbox.calls("pass"),
        vec![
            call("pass", &["show", "ssh-key"]),
            call("pass", &["show", "wrk/ssh-key"]),
        ],
        "the quiet work-key probe always runs"
    );
    let home = sandbox.home.display();
    let expected = format!(
        "    spawn ssh-add {home}/.ssh/id_neg\n    expect \"Enter passphrase\"\n    send \"secret\\r\"\n    expect eof\n"
    );
    assert_eq!(str_of(&sandbox.expect_script()), expected);
    assert_eq!(str_of(&sandbox.expect_environment()), "/tmp/agent.sock");
}

#[test]
fn existing_agent_is_reused() {
    let sandbox = Sandbox::new("unlock-existing");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", "secret"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"", "no agent is started");
    assert!(sandbox.calls("ssh-agent").is_empty());
    assert_eq!(
        str_of(&sandbox.expect_environment()),
        "/tmp/existing.sock",
        "the inherited socket is passed to expect"
    );
}

#[test]
fn work_key_is_fetched_when_present() {
    let sandbox = Sandbox::new("unlock-wrk");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", "secret"),
            ("FAKE_PASS_WRK_KEY", "work"),
            ("FAKE_PASS_WRK_EXIT", "0"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pass"),
        vec![
            call("pass", &["show", "ssh-key"]),
            call("pass", &["show", "wrk/ssh-key"]),
            call("pass", &["show", "wrk/ssh-key"]),
        ],
        "the quiet probe and the value fetch are two separate calls"
    );
}

#[test]
fn missing_work_key_is_ignored() {
    let sandbox = Sandbox::new("unlock-nowrk");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", "secret"),
            ("FAKE_PASS_WRK_EXIT", "1"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.calls("pass").len(), 2, "probe only, no value fetch");
}

#[test]
fn failing_pass_leaves_the_passphrase_empty() {
    let sandbox = Sandbox::new("unlock-passfail");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", ""),
            ("FAKE_PASS_KEY_EXIT", "1"),
        ],
    );
    assert_eq!(outcome.code, 0, "no set -e, expect still runs");
    let script = str_of(&sandbox.expect_script());
    assert!(script.contains("    send \"\\r\"\n"), "{script}");
}

#[test]
fn expect_exit_status_is_propagated() {
    let sandbox = Sandbox::new("unlock-status");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", "secret"),
            ("FAKE_EXPECT_EXIT", "4"),
        ],
    );
    assert_eq!(outcome.code, 4);
}

#[test]
fn missing_expect_is_reported_like_the_shell() {
    let sandbox = Sandbox::new("unlock-missing");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("expect")).expect("drop fake expect");
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("SSH_AUTH_SOCK", "/tmp/existing.sock"),
            ("FAKE_PASS_KEY", "secret"),
        ],
    );
    assert_eq!(outcome.code, 127);
    let stderr = str_of(&outcome.stderr);
    assert!(
        stderr.contains(": line 21: expect: command not found\n"),
        "{stderr}"
    );
}

#[test]
fn agent_start_is_reported_on_stdout() {
    let sandbox = Sandbox::new("unlock-echo");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("FAKE_SSH_SOCK", "/tmp/agent.sock"),
            ("FAKE_SSH_PID", "4242"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"Agent pid 4242\n");
    assert_eq!(str_of(&sandbox.expect_environment()), "/tmp/agent.sock");
}
