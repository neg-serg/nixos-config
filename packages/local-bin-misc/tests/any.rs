//! Hermetic tests for the `any` port: fake `pgrep`/`ps` log their argv, and
//! `ps`'s exit status must become the script's status.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_any");

const PGREP: &str = r#"#!/bin/sh
printf 'pgrep\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_PGREP_ERR:-}" >&2
printf '%s' "${FAKE_PGREP_OUT:-}"
exit "${FAKE_PGREP_CODE:-0}"
"#;

const PS: &str = r#"#!/bin/sh
printf 'ps\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_PS_OUT:-}"
printf '%s' "${FAKE_PS_ERR:-}" >&2
exit "${FAKE_PS_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("pgrep", PGREP);
    case.write_fake("ps", PS);
    case
}

fn expected_pgrep(arguments: &[&str]) -> String {
    let mut log = String::from("pgrep\n");
    for argument in ["-f", "--"] {
        log.push_str(&format!("  {argument}\n"));
    }
    for argument in arguments {
        log.push_str(&format!("  {argument}\n"));
    }
    log
}

fn expected_ps(list: &str) -> String {
    format!("ps\n  uwww\n  -p\n  {list}\n")
}

#[test]
fn matches_are_joined_and_passed_to_ps() {
    let case = fixture("any-matches");
    let output = case
        .command()
        .args(["foo", "-x"])
        .env("FAKE_PGREP_OUT", "11\n22\n")
        .env("FAKE_PS_OUT", "ps-out\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "ps-out\n");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["foo", "-x"]), expected_ps("11,22"))
    );
}

#[test]
fn user_pgrep_options_and_no_pattern_are_passed_verbatim() {
    let case = fixture("any-options");
    let output = case
        .command()
        .args(["-u", "neg", "-x", "sshd"])
        .env("FAKE_PGREP_OUT", "7\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        format!(
            "{}{}",
            expected_pgrep(&["-u", "neg", "-x", "sshd"]),
            expected_ps("7")
        )
    );

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    let output = case
        .command()
        .env("FAKE_PGREP_OUT", "3\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&[]), expected_ps("3"))
    );
}

#[test]
fn no_matches_exits_1_before_ps_runs() {
    let case = fixture("any-nomatch");
    let output = case
        .command()
        .args(["missing"])
        .env("FAKE_PGREP_OUT", "")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "any: no matches\n");
    assert_eq!(case.argv_log(), expected_pgrep(&["missing"]));
}

#[test]
fn pgrep_stderr_is_discarded() {
    let case = fixture("any-noise");
    let output = case
        .command()
        .args(["foo"])
        .env("FAKE_PGREP_OUT", "9\n")
        .env("FAKE_PGREP_ERR", "pgrep-noise\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["foo"]), expected_ps("9"))
    );
}

#[test]
fn pgrep_failure_still_uses_captured_output() {
    let case = fixture("any-pgrep-fail");
    let output = case
        .command()
        .args(["foo"])
        .env("FAKE_PGREP_OUT", "7\n")
        .env("FAKE_PGREP_CODE", "2")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["foo"]), expected_ps("7"))
    );

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    let output = case
        .command()
        .args(["foo"])
        .env("FAKE_PGREP_CODE", "2")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "any: no matches\n");
}

#[test]
fn trailing_newlines_and_blank_lines_join_like_paste() {
    let case = fixture("any-paste");
    let output = case
        .command()
        .args(["x"])
        .env("FAKE_PGREP_OUT", "1\n2\n\n\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["x"]), expected_ps("1,2"))
    );

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    case.command()
        .args(["x"])
        .env("FAKE_PGREP_OUT", "1\n\n2")
        .output()
        .expect("run any");
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["x"]), expected_ps("1,,2"))
    );

    std::fs::write(case.path("argv.log"), "").expect("clear argv log");
    case.command()
        .args(["x"])
        .env("FAKE_PGREP_OUT", "\n1")
        .output()
        .expect("run any");
    assert_eq!(
        case.argv_log(),
        format!("{}{}", expected_pgrep(&["x"]), expected_ps(",1"))
    );
}

#[test]
fn help_variants_use_the_usage_path() {
    for argument in ["-h", "--help", "help", "?"] {
        let case = Case::new("any-help", BIN);
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 1, "argument {argument}");
        assert_eq!(stdout(&output), "", "argument {argument}");
        assert_eq!(
            stderr(&output),
            "Usage: any [PGREP_OPTS...] PATTERN\n",
            "argument {argument}"
        );
        assert_eq!(case.argv_log(), "", "argument {argument}");
    }
}

#[test]
fn a_missing_pgrep_is_warned_about_and_means_no_matches() {
    let case = Case::new("any-no-pgrep", BIN);
    case.write_fake("ps", PS);
    let output = case.run(&["x"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "any: missing pgrep\nany: no matches\n");
    assert_eq!(case.argv_log(), "");
}

#[test]
fn a_missing_ps_warns_then_the_exec_failure_is_reported() {
    let case = Case::new("any-no-ps", BIN);
    case.write_fake("pgrep", PGREP);
    let output = case
        .command()
        .args(["x"])
        .env("FAKE_PGREP_OUT", "5\n")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("any: missing ps\n{BIN}: line 28: exec: ps: not found\n")
    );
}

#[test]
fn ps_output_streams_and_exit_status_are_the_script_ones() {
    let case = fixture("any-ps-status");
    let output = case
        .command()
        .args(["x"])
        .env("FAKE_PGREP_OUT", "4\n")
        .env("FAKE_PS_OUT", "ps-stdout\n")
        .env("FAKE_PS_ERR", "ps-stderr\n")
        .env("FAKE_PS_CODE", "7")
        .output()
        .expect("run any");
    assert_eq!(exited(&output), 7);
    assert_eq!(stdout(&output), "ps-stdout\n");
    assert_eq!(stderr(&output), "ps-stderr\n");
}
