//! Hermetic tests for the `vol` port.
//!
//! The only external tool is a fake `wpctl`; no PipeWire connection is made.

mod support;

use support::{exited, expected_argv, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_vol");
const USAGE: &str = "\
vol: adjust PipeWire default sink volume via wpctl
Usage: vol [+DELTA|-DELTA]
  Example: vol +0.05 (increase), vol -0.05 (decrease)
";

const WPCTL: &str = r#"#!/bin/sh
{ printf 'wpctl\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/wpctl.argv"
case "$1" in
  get-volume)
    printf '%s' "${FAKE_WPCTL_VOLUME-}"
    exit "${FAKE_WPCTL_GET_CODE:-0}"
    ;;
  set-volume)
    printf '%s' "${FAKE_WPCTL_OUT-}"
    printf '%s' "${FAKE_WPCTL_ERR-}" >&2
    exit "${FAKE_WPCTL_SET_CODE:-0}"
    ;;
esac
exit 0
"#;

fn case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("wpctl", WPCTL);
    case
}

#[test]
fn help_is_printed_for_no_arguments_and_both_flags() {
    let case = case("vol-help");
    for arguments in [&[][..], &["-h"][..], &["--help"][..]] {
        let output = case.run(arguments);
        assert_eq!(exited(&output), 0, "{arguments:?}");
        assert_eq!(stdout(&output), USAGE, "{arguments:?}");
        assert_eq!(stderr(&output), "", "{arguments:?}");
        assert_eq!(case.argv("wpctl"), "", "{arguments:?}");
    }
}

#[test]
fn positive_delta_reads_then_sets_the_sum() {
    let case = case("vol-up");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: 0.50\n")
        .arg("+0.05")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    let mut expected = expected_argv("wpctl", &["get-volume", "@DEFAULT_SINK@"]);
    expected.push_str(&expected_argv(
        "wpctl",
        &["set-volume", "@DEFAULT_SINK@", "0.55"],
    ));
    assert_eq!(case.argv("wpctl"), expected);
}

#[test]
fn increasing_clamps_at_one_the_way_awk_prints_it() {
    let case = case("vol-clamp-one");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: 0.98\n")
        .arg("+0.05")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("wpctl"),
        format!(
            "{}{}",
            expected_argv("wpctl", &["get-volume", "@DEFAULT_SINK@"]),
            expected_argv("wpctl", &["set-volume", "@DEFAULT_SINK@", "1"])
        )
    );
}

#[test]
fn a_negative_sum_clamps_to_zero() {
    let case = case("vol-clamp-zero");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: -0.5\n")
        .arg("+0")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("wpctl"),
        format!(
            "{}{}",
            expected_argv("wpctl", &["get-volume", "@DEFAULT_SINK@"]),
            expected_argv("wpctl", &["set-volume", "@DEFAULT_SINK@", "0"])
        )
    );
}

#[test]
fn the_muted_suffix_and_whitespace_are_ignored() {
    let case = case("vol-muted");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume:  0.25 [MUTED]\n")
        .arg("+0.05")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("wpctl"),
        format!(
            "{}{}",
            expected_argv("wpctl", &["get-volume", "@DEFAULT_SINK@"]),
            expected_argv("wpctl", &["set-volume", "@DEFAULT_SINK@", "0.3"])
        )
    );
}

#[test]
fn a_failed_get_volume_still_uses_the_zero_based_delta() {
    let case = case("vol-get-fails");
    let output = case
        .command()
        .env("FAKE_WPCTL_GET_CODE", "1")
        .arg("+0.05")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.argv("wpctl"),
        format!(
            "{}{}",
            expected_argv("wpctl", &["get-volume", "@DEFAULT_SINK@"]),
            expected_argv("wpctl", &["set-volume", "@DEFAULT_SINK@", "0.05"])
        )
    );
}

#[test]
fn scientific_formatting_matches_awk_g6() {
    let case = case("vol-scientific");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: 0.00001\n")
        .arg("+0")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert!(
        case.argv("wpctl").ends_with("ARG 1e-05\n"),
        "{}",
        case.argv("wpctl")
    );
}

#[test]
fn the_set_status_is_the_exit_status() {
    let case = case("vol-set-fails");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: 0.50\n")
        .env("FAKE_WPCTL_SET_CODE", "3")
        .arg("+0.05")
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 3);
}

#[test]
fn negative_and_unsigned_deltas_are_rejected() {
    let case = case("vol-sign");
    for argument in ["-0.05", "0.05", "--weird"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 2, "{argument}");
        assert_eq!(
            stderr(&output),
            "vol: expected +DELTA or -DELTA\n",
            "{argument}"
        );
        assert_eq!(stdout(&output), "", "{argument}");
        assert_eq!(case.argv("wpctl"), "", "{argument}");
    }
}

#[test]
fn a_missing_wpctl_warns_and_fails_the_spawns() {
    let case = case("vol-missing");
    case.remove_fake("wpctl");
    let output = case.run(&["+0.05"]);
    assert_eq!(exited(&output), 127);
    let error = stderr(&output);
    assert!(error.starts_with("vol: wpctl not found\n"), "{error}");
    assert!(
        error.contains("get_volume_: command not found: wpctl"),
        "{error}"
    );
    assert!(
        error.contains("set_volume: command not found: wpctl"),
        "{error}"
    );
    assert_eq!(stdout(&output), "");
}

#[test]
fn extra_arguments_are_ignored() {
    let case = case("vol-extra");
    let output = case
        .command()
        .env("FAKE_WPCTL_VOLUME", "Volume: 0.50\n")
        .args(["+0.05", "junk", "more"])
        .output()
        .expect("run vol");
    assert_eq!(exited(&output), 0);
    assert!(case.argv("wpctl").ends_with("ARG 0.55\n"));
}
