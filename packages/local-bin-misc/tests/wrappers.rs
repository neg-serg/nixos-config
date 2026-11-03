//! Hermetic tests for the two exec wrappers: fake `pw-jack`/`renoise` log the
//! argv and the environment the originals build, and their exit status must
//! become the wrapper's status.

mod support;

use support::{exited, stderr, stdout, Case};

const SCLANG: &str = env!("CARGO_BIN_EXE_sclang-pwj");
const RENOISE: &str = env!("CARGO_BIN_EXE_renoise-pwj");

const PWJACK: &str = r#"#!/bin/sh
printf 'pw-jack\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'ld=[%s] set=%s\n' "${LD_LIBRARY_PATH-}" "${LD_LIBRARY_PATH+set}" >> "$FAKE_ENV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf 'stdin=[%s]\n' "$line" >> "$FAKE_ENV_LOG"; done
printf '%s' "${FAKE_OUT:-}"
printf '%s' "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
"#;

const RENOISE_FAKE: &str = r#"#!/bin/sh
printf 'renoise\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
printf 'ld=[%s] set=%s\n' "${LD_LIBRARY_PATH-}" "${LD_LIBRARY_PATH+set}" >> "$FAKE_ENV_LOG"
while IFS= read -r line || [ -n "$line" ]; do printf 'stdin=[%s]\n' "$line" >> "$FAKE_ENV_LOG"; done
printf '%s' "${FAKE_OUT:-}"
printf '%s' "${FAKE_ERR:-}" >&2
exit "${FAKE_CODE:-0}"
"#;

fn sclang_fixture(label: &str) -> Case {
    let case = Case::new(label, SCLANG);
    case.write_fake("pw-jack", PWJACK);
    case
}

fn renoise_fixture(label: &str) -> Case {
    let case = Case::new(label, RENOISE);
    case.write_fake("renoise", RENOISE_FAKE);
    case
}

const BASE_LIB: &str = "/run/current-system/sw/lib";

#[test]
fn sclang_pwj_forwards_argv_and_propagates_status_and_streams() {
    let case = sclang_fixture("sclang-pwj");
    let output = case
        .command()
        .args(["-x", "--help", "a b"])
        .env("FAKE_OUT", "editor-out\n")
        .env("FAKE_ERR", "editor-err\n")
        .env("FAKE_CODE", "7")
        .output()
        .expect("run sclang-pwj");
    assert_eq!(exited(&output), 7);
    assert_eq!(stdout(&output), "editor-out\n");
    assert_eq!(stderr(&output), "editor-err\n");
    assert_eq!(
        case.argv_log(),
        "pw-jack\n  sclang\n  -x\n  --help\n  a b\n"
    );
    assert_eq!(case.env_log(), format!("ld=[{BASE_LIB}] set=set\n"));
}

#[test]
fn sclang_pwj_composes_ld_library_path_like_the_shell_parameter_expansion() {
    // Unset inherited value.
    let case = sclang_fixture("sclang-pwj-unset");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.env_log(), format!("ld=[{BASE_LIB}] set=set\n"));

    // Empty inherited value: no separator, no duplicate entry.
    let case = sclang_fixture("sclang-pwj-empty");
    let output = case
        .command()
        .env("LD_LIBRARY_PATH", "")
        .output()
        .expect("run");
    assert_eq!(exited(&output), 0);
    assert_eq!(case.env_log(), format!("ld=[{BASE_LIB}] set=set\n"));

    // Non-empty inherited value is appended after a colon.
    let case = sclang_fixture("sclang-pwj-set");
    let output = case
        .command()
        .env("LD_LIBRARY_PATH", "/custom/lib")
        .output()
        .expect("run");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.env_log(),
        format!("ld=[{BASE_LIB}:/custom/lib] set=set\n")
    );
}

#[test]
fn sclang_pwj_forwards_stdin() {
    let case = sclang_fixture("sclang-pwj-stdin");
    let output = case.run_with_stdin(&[], b"line-a\nline-b\n");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.env_log(),
        format!("ld=[{BASE_LIB}] set=set\nstdin=[line-a]\nstdin=[line-b]\n")
    );
}

#[test]
fn a_missing_pw_jack_is_an_exec_failure_with_status_127() {
    let case = Case::new("sclang-pwj-missing", SCLANG);
    let output = case.run(&["-x"]);
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("{SCLANG}: line 8: exec: pw-jack: not found\n")
    );
}

#[test]
fn renoise_pwj_forwards_argv_and_propagates_status_and_streams() {
    let case = renoise_fixture("renoise-pwj");
    let output = case
        .command()
        .args(["-h", "song.xrns"])
        .env("FAKE_OUT", "renoise-out\n")
        .env("FAKE_ERR", "renoise-err\n")
        .env("FAKE_CODE", "3")
        .output()
        .expect("run renoise-pwj");
    assert_eq!(exited(&output), 3);
    assert_eq!(stdout(&output), "renoise-out\n");
    assert_eq!(stderr(&output), "renoise-err\n");
    assert_eq!(case.argv_log(), "renoise\n  -h\n  song.xrns\n");
    // renoise-pwj changes no environment of its own.
    assert_eq!(case.env_log(), "ld=[] set=\n");
}

#[test]
fn renoise_pwj_forwards_stdin_and_keeps_the_inherited_library_path() {
    use std::io::Write;
    use std::process::Stdio;

    let case = renoise_fixture("renoise-pwj-stdin");
    let mut child = case
        .command()
        .env("LD_LIBRARY_PATH", "/keep/me")
        .stdin(Stdio::piped())
        .spawn()
        .expect("spawn renoise-pwj");
    child
        .stdin
        .take()
        .expect("piped stdin")
        .write_all(b"payload\n")
        .expect("write stdin");
    let output = child.wait_with_output().expect("collect output");
    assert_eq!(exited(&output), 0);
    // The helper replaced the process; its environment is the wrapper's.
    assert!(case.env_log().contains("ld=[/keep/me] set=set"));
    assert!(case.env_log().contains("stdin=[payload]"));
}

#[test]
fn a_missing_renoise_is_an_exec_failure_with_status_127() {
    let case = Case::new("renoise-pwj-missing", RENOISE);
    let output = case.run(&[]);
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("{RENOISE}: line 7: exec: renoise: not found\n")
    );
}
