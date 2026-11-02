//! Hermetic tests for the `punzip` port: fake `mkdir` and `unzip` log their
//! argv, so the exact argument handling of the shell original is checked.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_punzip");

const MKDIR: &str = r#"#!/bin/sh
printf 'mkdir %s\n' "$*" >> "$FAKE_ARGV_LOG"
exit "${FAKE_MKDIR_CODE:-0}"
"#;

const UNZIP: &str = r#"#!/bin/sh
printf 'unzip %s\n' "$*" >> "$FAKE_ARGV_LOG"
printf 'unzip-stdout\n'
printf 'unzip-stderr\n' >&2
exit "${FAKE_UNZIP_CODE:-0}"
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("mkdir", MKDIR);
    case.write_fake("unzip", UNZIP);
    case
}

#[test]
fn missing_file_is_usage_error() {
    let case = fixture("missing-file");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "punzip: missing FILE.zip\n");
    assert_eq!(case.argv_log(), "");

    let output = case.run(&["-d", "out"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "punzip: missing FILE.zip\n");
}

#[test]
fn missing_destination_is_usage_error() {
    let case = fixture("missing-dest");
    let output = case.run(&["-d"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "punzip: missing DIR for -d\n");

    let output = case.run(&["-d", "", "a.zip"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "punzip: missing DIR for -d\n");
}

#[test]
fn non_zip_names_are_rejected() {
    let case = fixture("not-zip");
    let output = case.run(&["a.tar.gz"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stderr(&output), "punzip: not a zip: a.tar.gz\n");
    assert_eq!(case.argv_log(), "");
}

#[test]
fn extracts_in_place() {
    let case = fixture("in-place");
    let output = case.run(&["archive.zip"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "unzip-stdout\n");
    assert_eq!(stderr(&output), "unzip-stderr\n");
    assert_eq!(case.argv_log(), "unzip -o archive.zip\n");
}

#[test]
fn extracts_into_directory() {
    let case = fixture("into-directory");
    let output = case.run(&["-d", "out dir", "archive.ZIP"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv_log(),
        "mkdir -p -- out dir\nunzip -o archive.ZIP -d out dir\n"
    );
}

#[test]
fn extra_arguments_are_ignored() {
    let case = fixture("extra-arguments");
    let output = case.run(&["a.zip", "b.zip"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), "unzip -o a.zip\n");

    let case = fixture("extra-directory-arguments");
    let output = case.run(&["-d", "out", "a.zip", "extra"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), "mkdir -p -- out\nunzip -o a.zip -d out\n");
}

#[test]
fn unzip_status_is_propagated() {
    let case = fixture("unzip-status");
    let output = case
        .command()
        .env("FAKE_UNZIP_CODE", "7")
        .args(["a.zip"])
        .output()
        .expect("run punzip");
    assert_eq!(exited(&output), 7);
}

#[test]
fn mkdir_failure_stops_before_unzip() {
    let case = fixture("mkdir-failure");
    let output = case
        .command()
        .env("FAKE_MKDIR_CODE", "4")
        .args(["-d", "out", "a.zip"])
        .output()
        .expect("run punzip");
    assert_eq!(exited(&output), 4);
    assert_eq!(case.argv_log(), "mkdir -p -- out\n");
}

#[test]
fn dash_d_after_the_archive_is_a_plain_argument() {
    let case = fixture("dash-d-late");
    let output = case.run(&["a.zip", "-d"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), "unzip -o a.zip\n");
}
