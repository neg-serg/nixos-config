//! Hermetic tests for the `journal-clean.sh` port: a fake `journalctl`
//! dispatches on its argv and logs every call; the Hyprland runtime log lives
//! in the per-case temporary directory.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_journal-clean");

const JOURNALCTL: &str = r#"#!/bin/sh
printf 'journalctl\n' >> "$FAKE_ARGV_LOG"
for arg in "$@"; do printf '  %s\n' "$arg" >> "$FAKE_ARGV_LOG"; done
case " $* " in
  *" --disk-usage "*)
    printf '%s' "${FAKE_USAGE:-}"
    exit "${FAKE_USAGE_CODE:-0}"
    ;;
  *" --vacuum-time="*)
    exit "${FAKE_VACUUM_CODE:-0}"
    ;;
esac
exit 0
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("journalctl", JOURNALCTL);
    case
}

fn expected_calls(keep: &str) -> String {
    format!(
        "journalctl\n  --user\n  --disk-usage\n\
         journalctl\n  --user\n  --vacuum-time={keep}\n\
         journalctl\n  --user\n  --disk-usage\n"
    )
}

#[test]
fn vacuums_the_user_journal_and_reports_before_and_after() {
    let case = fixture("vacuum");
    let output = case
        .command()
        .env("FAKE_USAGE", "user journal usage\n")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "== journalctl --user disk usage (before) ==\n\
         user journal usage\n\
         Vacuumed user journal to keep 1d\n\
         == journalctl --user disk usage (after) ==\n\
         user journal usage\n\
         Done.\n"
    );
    assert_eq!(stderr(&output), "");
    assert_eq!(case.argv_log(), expected_calls("1d"));
}

#[test]
fn custom_keep_window_is_passed_through() {
    let case = fixture("keep-window");
    let output = case.run(&["7d"]);
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).contains("Vacuumed user journal to keep 7d\n"));
    assert_eq!(case.argv_log(), expected_calls("7d"));
}

#[test]
fn empty_argument_falls_back_to_the_default_window() {
    let case = fixture("empty-window");
    let output = case.run(&[""]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.argv_log(), expected_calls("1d"));
}

#[test]
fn refused_vacuum_is_reported_on_stderr() {
    let case = fixture("vacuum-denied");
    let output = case
        .command()
        .env("FAKE_VACUUM_CODE", "1")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "Skipping vacuum: insufficient permission to remove system journal files (needs root)\n"
    );
    assert!(stdout(&output).contains("== journalctl --user disk usage (after) ==\n"));
}

#[test]
fn disk_usage_errors_are_ignored() {
    let case = fixture("usage-failure");
    let output = case
        .command()
        .env("FAKE_USAGE_CODE", "3")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).ends_with("Done.\n"));
    assert_eq!(case.argv_log(), expected_calls("1d"));
}

#[test]
fn missing_journalctl_skips_the_vacuum() {
    let case = fixture("no-journalctl");
    case.remove_fake("journalctl");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "journalctl not available; skipping journal vacuum\n"
    );
    assert_eq!(stdout(&output), "Done.\n");
}

#[test]
fn truncates_the_hyprland_runtime_log() {
    let case = fixture("hyprland-log");
    let runtime = case.root.join("runtime");
    let signature = "instance";
    let hypr_log = runtime.join("hypr").join(signature).join("hyprland.log");
    case.write(&hypr_log, "lots of compositor output\n");
    let output = case
        .command()
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("HYPRLAND_INSTANCE_SIGNATURE", signature)
        .env("FAKE_USAGE", "")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!(
            "== journalctl --user disk usage (before) ==\n\
             Vacuumed user journal to keep 1d\n\
             == journalctl --user disk usage (after) ==\n\
             Truncated Hyprland log: {}\n\
             Done.\n",
            hypr_log.display()
        )
    );
    assert_eq!(
        std::fs::read_to_string(&hypr_log).expect("hyprland log"),
        ""
    );
}

#[test]
fn unwritable_hyprland_log_aborts_with_a_redirection_diagnostic() {
    // /proc/version is a regular file that cannot be opened for writing even
    // by root; a symlink to it stands in for a read-only hyprland.log.
    if !std::path::Path::new("/proc/version").is_file() {
        return;
    }
    let case = fixture("unwritable-log");
    let runtime = case.root.join("runtime");
    let hypr_log = runtime.join("hypr").join("sig").join("hyprland.log");
    std::fs::create_dir_all(hypr_log.parent().expect("parent")).expect("create runtime tree");
    std::os::unix::fs::symlink("/proc/version", &hypr_log).expect("symlink hyprland log");
    let output = case
        .command()
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("HYPRLAND_INSTANCE_SIGNATURE", "sig")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        format!(
            "{}: line 29: {}: Permission denied\n",
            case.program().display(),
            hypr_log.display()
        )
    );
}

#[test]
fn hyprland_truncation_needs_both_variables_and_the_file() {
    let case = fixture("hyprland-variables");
    let runtime = case.root.join("runtime");
    let hypr_log = runtime.join("hypr").join("sig").join("hyprland.log");
    case.write(&hypr_log, "content\n");

    let output = case
        .command()
        .env("XDG_RUNTIME_DIR", &runtime)
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert!(!stdout(&output).contains("Truncated Hyprland log"));
    assert_eq!(
        std::fs::read_to_string(&hypr_log).expect("untouched hyprland log"),
        "content\n"
    );

    // Both variables set, but no file: nothing is reported either.
    let output = case
        .command()
        .env("XDG_RUNTIME_DIR", &runtime)
        .env("HYPRLAND_INSTANCE_SIGNATURE", "other")
        .output()
        .expect("run journal-clean");
    assert_eq!(exited(&output), 0);
    assert!(!stdout(&output).contains("Truncated Hyprland log"));
}
