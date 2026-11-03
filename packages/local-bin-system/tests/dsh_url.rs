//! Hermetic tests for the `dsh-url` port: the journal read, the loopback/LAN
//! extraction (including the sibling "opening the default browser" notice),
//! the mode dispatch and the clipboard argv/stdin.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_dsh-url");

const JOURNALCTL: &str = r#"#!/bin/sh
printf 'cmd journalctl\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_JOURNAL:-}"
"#;

const COPY_RAW: &str = r#"#!/bin/sh
printf 'cmd %s\n' "${0##*/}" >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r -N 1 character; do printf '%s' "$character" >> "$FAKE_CLIP"; done
exit "${FAKE_COPY_CODE:-0}"
"#;

const OPEN: &str = r#"#!/bin/sh
printf 'cmd xdg-open\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_OPEN_CODE:-0}"
"#;

const JOURNAL: &str = "2024-01-01 10:00:00 dsh web: opening the default browser\n2024-01-01 10:00:01 dsh web: http://127.0.0.1:3000/?token=abc (LAN: http://192.168.1.5:3000/?token=abc)\n";

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("journalctl", JOURNALCTL);
    case.write_fake("wl-copy", COPY_RAW);
    case.write_fake("xclip", COPY_RAW);
    case.write_fake("xdg-open", OPEN);
    case
}

fn journal_env<'a>() -> Vec<(&'a str, &'a str)> {
    vec![("FAKE_JOURNAL", JOURNAL)]
}

#[test]
fn help_prints_the_header() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        concat!(
            "dsh-url: print the URL the dsh web UI is serving right now.\n",
            "Usage: dsh-url [--lan|--open|--copy]\n",
            "  The ?token= value is a per-process launch token, so it changes on every dsh\n",
            "  restart. A browser that has exchanged it holds a signed cookie that does\n",
            "  survive restarts, so this is only needed for a fresh browser/profile, a\n",
            "  cleared cookie jar, or a different authority than the one that minted the\n",
            "  cookie.\n",
        )
    );
    // Help returns before the journal is read.
    assert_eq!(case.argv_log(), "");
}

#[test]
fn the_loopback_url_is_extracted_from_the_last_matching_line() {
    let case = fixture("loopback");
    let output = case.run_env(&[], &journal_env());
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "http://127.0.0.1:3000/?token=abc\n");
    assert_eq!(
        case.argv_log(),
        "cmd journalctl\n  --user\n  -u\n  dsh.service\n  --no-pager\n"
    );
}

#[test]
fn a_missing_journal_line_is_fatal() {
    let case = fixture("no-line");
    let output = case.run_env(&[], &[("FAKE_JOURNAL", "")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "dsh-url: no 'dsh web:' line in the dsh.service journal — is the service running?\n"
    );
    assert_eq!(stdout(&output), "");
}

#[test]
fn lan_requires_the_log_to_carry_it() {
    let case = fixture("lan");
    let output = case.run_env(&["--lan"], &journal_env());
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "http://192.168.1.5:3000/?token=abc\n");

    let loopback_only = fixture("lan-missing");
    let output = loopback_only.run_env(
        &["--lan"],
        &[(
            "FAKE_JOURNAL",
            "dsh web: http://127.0.0.1:3000/?token=abc\n",
        )],
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "dsh-url: the log carries no LAN URL (loopback-only bind)\n"
    );
}

#[test]
fn unknown_options_are_usage_errors() {
    let case = fixture("unknown");
    let output = case.run_env(&["--bogus"], &journal_env());
    assert_eq!(exited(&output), 2);
    assert_eq!(
        stderr(&output),
        "dsh-url: unknown option '--bogus' (use --lan, --open, --copy, --help)\n"
    );
    assert_eq!(stdout(&output), "");
}

#[test]
fn copy_writes_the_url_without_a_trailing_newline() {
    let case = fixture("copy");
    let output = case.run_env(&["--copy"], &journal_env());
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "http://127.0.0.1:3000/?token=abc\n");
    assert_eq!(case.clip_log(), "http://127.0.0.1:3000/?token=abc");
    assert_eq!(case.argv_log().matches("cmd wl-copy").count(), 1);
}

#[test]
fn copy_falls_back_to_xclip() {
    let case = fixture("xclip");
    case.remove_fake("wl-copy");
    let output = case.run_env(&["--copy"], &journal_env());
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "http://127.0.0.1:3000/?token=abc");
    assert!(case
        .argv_log()
        .contains("cmd xclip\n  -selection\n  clipboard\n"));
}

#[test]
fn copy_without_a_clipboard_tool_is_fatal() {
    let case = fixture("no-clip");
    case.remove_fake("wl-copy");
    case.remove_fake("xclip");
    let output = case.run_env(&["--copy"], &journal_env());
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "dsh-url: neither wl-copy nor xclip is available\n"
    );
}

#[test]
fn open_runs_xdg_open_and_propagates_its_status() {
    let case = fixture("open");
    let output = case.run_env(&["--open"], &journal_env());
    assert_eq!(exited(&output), 0);
    assert!(case
        .argv_log()
        .contains("cmd xdg-open\n  http://127.0.0.1:3000/?token=abc\n"));

    let failing = fixture("open-fail");
    let output = failing.run_env(
        &["--open"],
        &[("FAKE_JOURNAL", JOURNAL), ("FAKE_OPEN_CODE", "5")],
    );
    assert_eq!(exited(&output), 5);
}

#[test]
fn copy_status_is_propagated() {
    let case = fixture("copy-status");
    let output = case.run_env(
        &["--copy"],
        &[("FAKE_JOURNAL", JOURNAL), ("FAKE_COPY_CODE", "4")],
    );
    assert_eq!(exited(&output), 4);
}

#[test]
fn the_first_url_on_the_line_wins() {
    let case = fixture("first-url");
    let output = case.run_env(
        &[],
        &[(
            "FAKE_JOURNAL",
            "dsh web: http (https://one.example/a and http://two.example/b)\n",
        )],
    );
    assert_eq!(stdout(&output), "https://one.example/a\n");
}

#[test]
fn a_matching_line_without_a_url_prints_an_empty_url() {
    let case = fixture("no-url");
    let output = case.run_env(&[], &[("FAKE_JOURNAL", "dsh web: http not a url\n")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "\n");
}

#[test]
fn help_is_only_recognized_as_the_first_argument() {
    let case = fixture("help-late");
    let output = case.run_env(&["--lan", "--help"], &[("FAKE_JOURNAL", "")]);
    assert_eq!(exited(&output), 1);
    assert!(stderr(&output).contains("no 'dsh web:' line"));
}
