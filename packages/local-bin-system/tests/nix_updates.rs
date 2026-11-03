//! Hermetic tests for the `nix-updates` port: the two tool invocations, their
//! ignored statuses, the `need nix` warning and the one-line help.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_nix-updates");

const NIX: &str = r#"#!/bin/sh
printf 'cmd nix\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf 'nix-out\n'
exit "${FAKE_NIX_CODE:-0}"
"#;

const DIX: &str = r#"#!/bin/sh
printf 'cmd dix\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_DIX_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("nix", NIX);
    case.write_fake("dix", DIX);
    case
}

#[test]
fn help_prints_two_lines() {
    let case = fixture("help");
    for argument in ["--help", "-h"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0);
        assert_eq!(
            stdout(&output),
            "nix-updates: show diffs between booted/current system profiles\nUsage: nix-updates\n"
        );
        assert_eq!(stderr(&output), "");
    }
    assert_eq!(case.argv_log(), "");
}

#[test]
fn both_tools_run_in_order() {
    let case = fixture("run");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "nix-out\n");
    assert_eq!(
        case.argv_log(),
        "cmd nix\n  profile\n  diff-closures\n  --profile\n  /nix/var/nix/profiles/system\ncmd dix\n  /run/booted-system\n  /run/current-system\n"
    );
}

#[test]
fn a_failing_nix_still_runs_dix_and_exits_zero() {
    let case = fixture("nix-fails");
    let output = case.run_env(&[], &[("FAKE_NIX_CODE", "3")]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv_log().contains("cmd dix"));
}

#[test]
fn a_failing_dix_is_ignored() {
    let case = fixture("dix-fails");
    let output = case.run_env(&[], &[("FAKE_DIX_CODE", "4")]);
    assert_eq!(exited(&output), 0);
}

#[test]
fn missing_nix_warns_but_continues() {
    let case = fixture("no-nix");
    case.remove_fake("nix");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "nix-updates: missing nix\n");
    assert!(!case.argv_log().contains("cmd nix"));
    assert!(case.argv_log().contains("cmd dix"));
}

#[test]
fn without_dix_only_nix_runs() {
    let case = fixture("no-dix");
    case.remove_fake("dix");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert!(!case.argv_log().contains("cmd dix"));
}

#[test]
fn help_is_only_recognized_as_the_first_argument() {
    let case = fixture("help-late");
    let output = case.run(&["7d", "--help"]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv_log().contains("cmd nix"));
}
