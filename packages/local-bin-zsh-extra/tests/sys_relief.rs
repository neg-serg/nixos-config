//! Hermetic tests for the `sys-relief` port.
//!
//! sudo, sysctl, sync, sleep and notify-send are fakes; nothing touches the
//! host's caches or sysctl values. The timed restore re-executes the binary
//! with LOCAL_BIN_ZSH_EXTRA_RESTORE set, so the fake sleep returns immediately
//! and the whole flow is observable.

mod support;

use support::{exited, expected_argv, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_sys-relief");

const NOTIFY: &str = r#"#!/bin/sh
{ printf 'notify-send\n'; printf 'notify-send\n' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/notify-send.argv"
exit "${FAKE_NOTIFY_CODE:-0}"
"#;

const SYNC: &str = r#"#!/bin/sh
{ printf 'sync\n'; printf 'sync\n' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/sync.argv"
exit "${FAKE_SYNC_CODE:-0}"
"#;

const SUDO: &str = r#"#!/bin/sh
{ printf 'sudo\n'; printf 'sudo\n' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/sudo.argv"
case "$*" in
  *vm.drop_caches=3*) exit "${FAKE_SUDO_DROP_CODE:-0}" ;;
  *vm.compact_memory=1*) exit "${FAKE_SUDO_COMPACT_CODE:-0}" ;;
  *vm.swappiness=10*) exit "${FAKE_SUDO_RESTORE_CODE:-0}" ;;
  *) exit "${FAKE_SUDO_CODE:-0}" ;;
esac
"#;

const SLEEP: &str = r#"#!/bin/sh
{ printf 'sleep\n'; printf 'sleep\n' >> "$FAKE_LOG_DIR/calls.log"; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/sleep.argv"
exit "${FAKE_SLEEP_CODE:-0}"
"#;

fn case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("notify-send", NOTIFY);
    case.write_fake("sync", SYNC);
    case.write_fake("sudo", SUDO);
    case.write_fake("sleep", SLEEP);
    case
}

const FOREGROUND_SEQUENCE: &str = "notify-send\nsync\nsudo\nsudo\nsudo\nsudo\nsudo\nnotify-send\n";
const RESTORE_SEQUENCE: &str = "sleep\nsudo\nnotify-send\n";

#[test]
fn the_normal_flow_applies_and_restores() {
    let case = case("relief-normal");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.calls(),
        format!("{FOREGROUND_SEQUENCE}{RESTORE_SEQUENCE}")
    );

    let mut expected = expected_argv("sudo", &["sysctl", "-w", "vm.drop_caches=3"]);
    expected.push_str(&expected_argv(
        "sudo",
        &["sysctl", "-w", "vm.compact_memory=1"],
    ));
    expected.push_str(&expected_argv("sudo", &["sysctl", "-w", "vm.swappiness=1"]));
    expected.push_str(&expected_argv(
        "sudo",
        &["sysctl", "-w", "vm.dirty_background_bytes=16777216"],
    ));
    expected.push_str(&expected_argv(
        "sudo",
        &["sysctl", "-w", "vm.dirty_bytes=67108864"],
    ));
    expected.push_str(&expected_argv(
        "sudo",
        &[
            "sysctl",
            "-w",
            "vm.swappiness=10",
            "vm.dirty_background_bytes=67108864",
            "vm.dirty_bytes=268435456",
        ],
    ));
    assert_eq!(case.argv("sudo"), expected);
    assert_eq!(case.argv("sleep"), expected_argv("sleep", &["300"]));

    let mut notifications = expected_argv(
        "notify-send",
        &[
            "-a",
            "sys-relief",
            "-u",
            "low",
            "Relief...",
            "Syncing dirty pages...",
        ],
    );
    notifications.push_str(&expected_argv(
        "notify-send",
        &[
            "-a",
            "sys-relief",
            "Relief applied",
            "Caches dropped, IO reduced.\\nRestoring in 5 min.",
        ],
    ));
    notifications.push_str(&expected_argv(
        "notify-send",
        &[
            "-a",
            "sys-relief",
            "-u",
            "low",
            "Relief",
            "Sysctl restored to normal.",
        ],
    ));
    assert_eq!(case.argv("notify-send"), notifications);
}

#[test]
fn a_compact_memory_failure_is_ignored() {
    let case = case("relief-compact-fails");
    let output = case
        .command()
        .env("FAKE_SUDO_COMPACT_CODE", "1")
        .output()
        .expect("run sys-relief");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.calls(),
        format!("{FOREGROUND_SEQUENCE}{RESTORE_SEQUENCE}")
    );
}

#[test]
fn a_drop_caches_failure_aborts_before_the_timer() {
    let case = case("relief-drop-fails");
    let output = case
        .command()
        .env("FAKE_SUDO_DROP_CODE", "1")
        .output()
        .expect("run sys-relief");
    assert_eq!(exited(&output), 1);
    assert_eq!(case.calls(), "notify-send\nsync\nsudo\n");
    assert_eq!(case.argv("sleep"), "");
}

#[test]
fn a_sync_failure_aborts() {
    let case = case("relief-sync-fails");
    let output = case
        .command()
        .env("FAKE_SYNC_CODE", "3")
        .output()
        .expect("run sys-relief");
    assert_eq!(exited(&output), 3);
    assert_eq!(case.calls(), "notify-send\nsync\n");
}

#[test]
fn a_missing_notify_send_is_silent_and_non_fatal() {
    let case = case("relief-no-notify");
    case.remove_fake("notify-send");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.calls(),
        "sync\nsudo\nsudo\nsudo\nsudo\nsudo\nsleep\nsudo\n"
    );
}

#[test]
fn a_missing_sync_is_a_zsh_style_failure() {
    let case = case("relief-no-sync");
    case.remove_fake("sync");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        format!("{BIN}:14: command not found: sync\n")
    );
    assert_eq!(case.calls(), "notify-send\n");
}

#[test]
fn the_restore_child_can_be_run_directly() {
    let case = case("relief-restore");
    let output = case
        .command()
        .env("LOCAL_BIN_ZSH_EXTRA_RESTORE", "1")
        .output()
        .expect("run sys-relief restore");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(case.calls(), RESTORE_SEQUENCE);
    assert_eq!(case.argv("sleep"), expected_argv("sleep", &["300"]));
    assert_eq!(
        case.argv("notify-send"),
        expected_argv(
            "notify-send",
            &[
                "-a",
                "sys-relief",
                "-u",
                "low",
                "Relief",
                "Sysctl restored to normal."
            ]
        )
    );
}

#[test]
fn a_restore_failure_skips_the_second_notification() {
    let case = case("relief-restore-fails");
    let output = case
        .command()
        .env("FAKE_SUDO_RESTORE_CODE", "1")
        .output()
        .expect("run sys-relief");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.calls(), format!("{FOREGROUND_SEQUENCE}sleep\nsudo\n"));
}
