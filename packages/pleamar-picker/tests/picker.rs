//! End-to-end tests for `pleamar-picker`.
//!
//! fake `pleamar` and `systemctl` log every call; a fake `sleep` makes the
//! 0.1 s loops instant and counts the steps. The deck's `get open` answer is a
//! state file, so open/closed stories are scripted rather than timed.

mod support;

use std::fs;

use support::PipeThrough as _;
use support::{stderr, stdout, Case, PLEAMAR, SLEEP, SYSTEMCTL};

fn picker_case(label: &str) -> Case {
    let case = Case::picker(label);
    case.fake("pleamar", PLEAMAR);
    case.fake("systemctl", SYSTEMCTL);
    case.fake("sleep", SLEEP);
    case
}

fn calls(case: &Case) -> Vec<String> {
    case.log().lines().map(str::to_string).collect()
}

fn count(case: &Case, prefix: &str) -> usize {
    calls(case)
        .iter()
        .filter(|line| line.starts_with(prefix))
        .count()
}

#[test]
fn toggle_closes_an_open_deck_and_stops_the_unit() {
    let case = picker_case("toggle-close");
    let output = case.run_with(&[("FAKE_TOGGLE_CLOSES", "1")], &[]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        calls(&case),
        vec![
            "pleamar [--say] [picker] [get open]",
            "pleamar [--say] [picker] [emit toggle_picker]",
            "pleamar [--say] [picker] [get open]",
            "systemctl [--user] [stop] [pleamar-picker.service]",
        ]
    );
}

#[test]
fn toggle_opens_a_closed_deck_without_stopping_the_unit() {
    let case = picker_case("toggle-open");
    case.set_deck_open("false");
    let output = case.run_with(&[("FAKE_TOGGLE_OPENS", "1")], &[]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(count(&case, "pleamar [--say] [picker] [get open]"), 2);
    assert_eq!(
        calls(&case)[1],
        "pleamar [--say] [picker] [emit toggle_picker]"
    );
    assert_eq!(count(&case, "systemctl"), 0);
    assert_eq!(count(&case, "sleep"), 0);
}

#[test]
fn a_swallowed_toggle_waits_twenty_steps_and_keeps_the_unit() {
    let case = picker_case("toggle-swallowed");
    let output = case.run(&[]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    // One answer before the toggle, then the 20-step poll.
    assert_eq!(count(&case, "pleamar [--say] [picker] [get open]"), 21);
    assert_eq!(count(&case, "sleep [0.1]"), 20);
    assert_eq!(count(&case, "systemctl"), 0);
}

#[test]
fn toggle_starts_a_dead_deck_and_waits_for_the_socket() {
    let case = picker_case("toggle-start");
    let output = case.run_with(&[("FAKE_TOGGLE_CODE", "1"), ("FAKE_OPEN_AFTER", "3")], &[]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    let lines = calls(&case);
    // get open, the failed toggle, then the unit start and three attempts.
    assert_eq!(lines[0], "pleamar [--say] [picker] [get open]");
    assert_eq!(lines[1], "pleamar [--say] [picker] [emit toggle_picker]");
    assert_eq!(
        lines[2],
        "systemctl [--user] [start] [pleamar-picker.service]"
    );
    assert_eq!(
        count(&case, "pleamar [--say] [picker] [emit open_picker]"),
        3
    );
    assert_eq!(count(&case, "sleep [0.1]"), 2);
}

#[test]
fn the_start_loop_times_out_after_thirty_steps() {
    let case = picker_case("start-timeout");
    let output = case.run_with(
        &[
            ("FAKE_TOGGLE_CODE", "1"),
            ("FAKE_OPEN_AFTER", "999"),
            ("FAKE_OPEN_FAIL_CODE", "1"),
        ],
        &[],
    );

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "pleamar-picker: the wallpaper deck did not come up\n"
    );
    assert_eq!(
        count(&case, "pleamar [--say] [picker] [emit open_picker]"),
        30
    );
    assert_eq!(count(&case, "sleep [0.1]"), 30);
    assert_eq!(count(&case, "systemctl [--user] [start]"), 1);
}

#[test]
fn open_starts_the_unit_and_opens_immediately() {
    let case = picker_case("open");
    let output = case.run(&["open"]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        calls(&case),
        vec![
            "systemctl [--user] [start] [pleamar-picker.service]",
            "pleamar [--say] [picker] [emit open_picker]",
        ]
    );
}

#[test]
fn open_exits_1_when_the_unit_does_not_start() {
    let case = picker_case("open-start-fails");
    let output = case.run_with(&[("FAKE_START_CODE", "3")], &["open"]);

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(count(&case, "pleamar"), 0);
    assert_eq!(count(&case, "sleep"), 0);
}

#[test]
fn close_says_close_and_stops_the_unit_even_when_the_say_fails() {
    let case = picker_case("close");
    let output = case.run_with(&[("FAKE_CLOSE_CODE", "1")], &["close"]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(
        calls(&case),
        vec![
            "pleamar [--say] [picker] [emit close_picker]",
            "systemctl [--user] [stop] [pleamar-picker.service]",
        ]
    );
}

#[test]
fn reload_only_says_reload() {
    let case = picker_case("reload");
    let output = case.run(&["reload"]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    assert_eq!(calls(&case), vec!["pleamar [--say] [picker] [emit reload]"]);
}

#[test]
fn current_prints_the_theme_pipeline_file() {
    let case = picker_case("current");
    let path = case.cache_path();
    fs::create_dir_all(path.parent().expect("cache parent")).expect("cache dir");
    fs::write(&path, b"/w/last.png\n").expect("write cache");
    let output = case.run(&["current"]);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "/w/last.png\n");
    assert_eq!(stderr(&output), "");
    assert_eq!(case.log(), "");
}

#[test]
fn current_prints_a_file_without_a_trailing_newline_verbatim() {
    let case = picker_case("current-no-newline");
    case.write(&case.cache_path(), b"/w/last.png");
    let output = case.run(&["current"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "/w/last.png");
}

#[test]
fn current_with_a_missing_file_is_empty_and_zero() {
    let case = picker_case("current-missing");
    let output = case.run(&["current"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
}

#[test]
fn current_honours_xdg_cache_home_and_the_home_default() {
    let case = picker_case("current-env");
    let from_home = case.home.join(".cache/pleamar/wallpaper-path");
    case.write(&from_home, b"/w/home.png\n");

    let output = case
        .command()
        .env_remove("XDG_CACHE_HOME")
        .args(["current"])
        .pipe_through(support::output);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "/w/home.png\n");

    let under_xdg = case.cache_path();
    case.write(&under_xdg, b"/w/xdg.png\n");
    let output = case.run(&["current"]);
    assert_eq!(stdout(&output), "/w/xdg.png\n");
}

#[test]
fn current_without_home_or_xdg_cache_home_exits_1() {
    let case = picker_case("current-no-home");
    let output = case
        .command()
        .env_remove("HOME")
        .env_remove("XDG_CACHE_HOME")
        .args(["current"])
        .output()
        .expect("run without HOME");
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
}

#[test]
fn an_unknown_verb_is_usage_exit_2() {
    let case = picker_case("unknown");
    let output = case.run(&["bogus"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "usage: pleamar-picker [toggle|open|close|reload|current]\n"
    );
    assert_eq!(case.log(), "");
}

#[test]
fn an_empty_verb_is_the_toggle() {
    let case = picker_case("empty-verb");
    let output = case.run_with(&[("FAKE_TOGGLE_CLOSES", "1")], &[""]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(count(&case, "systemctl [--user] [stop]"), 1);
}

#[test]
fn extra_arguments_are_ignored() {
    let case = picker_case("extra-args");
    let output = case.run(&["reload", "ignored"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(calls(&case), vec!["pleamar [--say] [picker] [emit reload]"]);
}

#[test]
fn the_environment_overrides_the_programs() {
    let case = picker_case("env-overrides");
    let alt = case.dir.join("alt");
    fs::create_dir_all(&alt).expect("alt dir");
    for name in ["pleamar", "systemctl"] {
        let source = case.bin.join(name);
        let target = alt.join(name);
        fs::copy(&source, &target).expect("copy fake");
        let mut permissions = fs::metadata(&target).expect("stat fake").permissions();
        use std::os::unix::fs::PermissionsExt;
        permissions.set_mode(0o755);
        fs::set_permissions(&target, permissions).expect("chmod fake");
    }

    let output = case.run_with(
        &[
            ("PLEAMAR", alt.join("pleamar").to_str().expect("UTF-8 path")),
            (
                "SYSTEMCTL",
                alt.join("systemctl").to_str().expect("UTF-8 path"),
            ),
        ],
        &["close"],
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        calls(&case),
        vec![
            "pleamar [--say] [picker] [emit close_picker]",
            "systemctl [--user] [stop] [pleamar-picker.service]",
        ]
    );
}

#[test]
fn a_missing_pleamar_times_out_with_only_the_final_error() {
    let case = picker_case("missing-pleamar");
    let output = case.run_with(&[("PLEAMAR", "/nonexistent/pleamar")], &[]);

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "pleamar-picker: the wallpaper deck did not come up\n"
    );
    assert_eq!(count(&case, "pleamar"), 0);
    assert_eq!(count(&case, "sleep [0.1]"), 30);
    assert_eq!(count(&case, "systemctl [--user] [start]"), 1);
}

#[test]
fn a_missing_systemctl_exits_1_on_open() {
    let case = picker_case("missing-systemctl");
    let output = case.run_with(&[("SYSTEMCTL", "/nonexistent/systemctl")], &["open"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(count(&case, "pleamar"), 0);
}

#[test]
fn a_failing_stop_is_ignored_by_close() {
    let case = picker_case("stop-fails");
    let output = case.run_with(&[("FAKE_STOP_CODE", "4")], &["close"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(count(&case, "systemctl [--user] [stop]"), 1);
}

#[test]
fn tail_keeps_only_the_last_line_of_the_deck_answer() {
    let case = picker_case("deck-multiline");
    let script = r#"#!/bin/sh
printf 'pleamar' >> "$FAKE_LOG"
for arg; do printf ' [%s]' "$arg" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
case "$*" in
  "--say picker get open")
    if [ -f "$FAKE_DECK_FILE" ]; then read -r open < "$FAKE_DECK_FILE"; else open=true; fi
    printf 'noise\n%s\n' "$open"
    ;;
  "--say picker emit toggle_picker") printf 'false' > "$FAKE_DECK_FILE"; exit 0 ;;
  *) exit 0 ;;
esac
"#;
    case.fake("pleamar", script);
    let output = case.run(&[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(count(&case, "systemctl [--user] [stop]"), 1);
    assert_eq!(count(&case, "sleep"), 0);
}
