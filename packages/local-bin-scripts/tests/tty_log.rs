//! Hermetic tests for the `tty-log` port: fake `mkdir`, `tail`, `mv` and
//! `script` programs log every argv element, so both the log-rotation and the
//! `exec script` behaviour are observable.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_tty-log");

const MKDIR: &str = r#"#!/bin/sh
printf 'mkdir\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_MKDIR_CODE:-0}"
"#;

const TAIL: &str = r#"#!/bin/sh
printf 'tail\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_TAIL_OUT:-}"
exit "${FAKE_TAIL_CODE:-0}"
"#;

const MV: &str = r#"#!/bin/sh
printf 'mv\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_MV_CODE:-0}"
"#;

const SCRIPT: &str = r#"#!/bin/sh
printf 'script\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'script-stdout\n'
printf 'script-stderr\n' >&2
exit "${FAKE_SCRIPT_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("mkdir", MKDIR);
    case.write_fake("tail", TAIL);
    case.write_fake("mv", MV);
    case.write_fake("script", SCRIPT);
    // `mkdir -p` runs for real in the original and the fake here; pre-creating
    // the log directory keeps the fake free of external commands.
    std::fs::create_dir_all(log_dir(&case)).expect("create log directory");
    case
}

fn log_dir(case: &Case) -> std::path::PathBuf {
    case.home.join(".cache/quickshell/tty-logs")
}

fn log_file(case: &Case, name: &str) -> std::path::PathBuf {
    log_dir(case).join(format!("{name}.log"))
}

fn expected_mkdir(case: &Case) -> String {
    format!("mkdir\n  -p\n  {}\n", log_dir(case).display())
}

#[test]
fn missing_name_is_a_usage_error() {
    let case = fixture("missing-name");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!(
            "{}: line 9: 1: Usage: tty-log <name> [command...]\n",
            case.program().display()
        )
    );
    assert_eq!(case.argv_log(), "");

    let output = case.run(&[""]);
    assert_eq!(exited(&output), 1);
    assert!(stderr(&output).contains("Usage: tty-log <name> [command...]"));
}

#[test]
fn captures_the_shell_session_when_no_command_is_given() {
    let case = fixture("session");
    let output = case.run(&["tty1"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "script-stdout\n");
    assert_eq!(stderr(&output), "script-stderr\n");
    let logfile = log_file(&case, "tty1");
    assert_eq!(
        case.argv_log(),
        format!(
            "{expected}tail\n  -c\n  204800\n  {logfile}\n\
             mv\n  {logfile}.tmp\n  {logfile}\n\
             script\n  -f\n  {logfile}\n",
            expected = expected_mkdir(&case),
            logfile = logfile.display()
        )
    );
}

#[test]
fn joins_the_command_like_dollar_star() {
    let case = fixture("command");
    let output = case.run(&["build", "nix", "build", ".#foo"]);
    assert_eq!(exited(&output), 0);
    let logfile = log_file(&case, "build");
    assert!(
        case.argv_log().ends_with(&format!(
            "script\n  -f\n  -c\n  nix build .#foo\n  {}\n",
            logfile.display()
        )),
        "argv: {}",
        case.argv_log()
    );
}

#[test]
fn empty_command_argument_survives_joining() {
    let case = fixture("empty-command");
    let output = case.run(&["name", ""]);
    assert_eq!(exited(&output), 0);
    let logfile = log_file(&case, "name");
    assert!(case.argv_log().ends_with(&format!(
        "script\n  -f\n  -c\n  \n  {}\n",
        logfile.display()
    )));
}

#[test]
fn rotation_output_lands_in_the_temporary_file() {
    let case = fixture("rotation");
    let output = case
        .command()
        .env("FAKE_TAIL_OUT", "kept-bytes")
        .args(["name"])
        .output()
        .expect("run tty-log");
    assert_eq!(exited(&output), 0);
    let temporary = log_dir(&case).join("name.log.tmp");
    assert_eq!(
        std::fs::read_to_string(&temporary).expect("tail wrote the temporary file"),
        "kept-bytes"
    );
}

#[test]
fn failed_tail_skips_the_move_but_still_starts_script() {
    let case = fixture("tail-failure");
    let output = case
        .command()
        .env("FAKE_TAIL_CODE", "1")
        .args(["name"])
        .output()
        .expect("run tty-log");
    assert_eq!(exited(&output), 0);
    let log = case.argv_log();
    assert!(log.contains("tail\n"));
    assert!(!log.contains("mv\n"), "argv: {log}");
    assert!(log.contains("script\n  -f\n"));
}

#[test]
fn unopenable_rotation_file_is_silently_ignored() {
    let case = fixture("rotation-failure");
    let temporary = log_dir(&case).join("name.log.tmp");
    std::fs::create_dir_all(&temporary).expect("create a directory where the file should be");
    let output = case.run(&["name"]);
    assert_eq!(exited(&output), 0);
    // `2>/dev/null` is applied before the failing stdout redirection, so even
    // bash's "Is a directory" diagnostic is discarded.
    assert_eq!(stderr(&output), "script-stderr\n");
    let log = case.argv_log();
    assert!(!log.contains("tail\n"), "argv: {log}");
    assert!(log.contains("script\n  -f\n"));
}

#[test]
fn missing_mv_is_reported_but_not_fatal() {
    let case = fixture("missing-mv");
    case.remove_fake("mv");
    let output = case.run(&["name"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        format!(
            "{prog}: line 16: mv: command not found\nscript-stderr\n",
            prog = case.program().display()
        )
    );
    assert!(case.argv_log().contains("script\n  -f\n"));
}

#[test]
fn missing_tail_is_silently_ignored() {
    let case = fixture("missing-tail");
    case.remove_fake("tail");
    let output = case.run(&["name"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "script-stderr\n");
    let log = case.argv_log();
    assert!(!log.contains("mv\n"), "argv: {log}");
    assert!(log.contains("script\n  -f\n"));
}

#[test]
fn missing_home_is_an_unbound_variable() {
    let case = fixture("no-home");
    let output = case
        .command()
        .env_remove("HOME")
        .arg("name")
        .output()
        .expect("run tty-log");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "{}: line 11: HOME: unbound variable\n",
            case.program().display()
        )
    );
}

#[test]
fn mkdir_failure_aborts() {
    let case = fixture("mkdir-failure");
    let output = case
        .command()
        .env("FAKE_MKDIR_CODE", "5")
        .args(["name"])
        .output()
        .expect("run tty-log");
    assert_eq!(exited(&output), 5);
    assert_eq!(case.argv_log(), expected_mkdir(&case));
}

#[test]
fn script_status_and_missing_script_are_preserved() {
    let case = fixture("script-status");
    let output = case
        .command()
        .env("FAKE_SCRIPT_CODE", "9")
        .args(["name"])
        .output()
        .expect("run tty-log");
    assert_eq!(exited(&output), 9);

    let case = fixture("missing-script");
    case.remove_fake("script");
    let output = case.run(&["name"]);
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        format!(
            "{}: line 21: exec: script: not found\n",
            case.program().display()
        )
    );
}
