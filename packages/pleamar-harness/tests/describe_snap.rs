//! End-to-end tests for `pleamar-describe-snap`.

mod support;

use std::fs;

use support::{stderr, stdout, Case};

fn case(label: &str) -> Case {
    Case::describe_snap(label)
}

#[test]
fn update_writes_a_json_snapshot_and_verify_matches_it() {
    let case = case("update");
    let output = case.run(&["--update", "bar"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(
        out.contains("describe-snap: starting the scene in pleamar-wm headless"),
        "{out}"
    );
    assert!(
        out.contains(&format!(
            "describe-snap: wrote {}/tests/bar.describe.txt",
            case.project.display()
        )),
        "{out}"
    );
    assert_eq!(stderr(&output), "");
    let snapshot = case.read("tests/bar.describe.txt");
    assert_eq!(snapshot, "{\n  \"bar\": 1,\n  \"clock\": \"HH:MM\"\n}\n");
    assert!(case
        .calls_of("pleamar")
        .iter()
        .any(|line| line.contains("[--say] [bar] [quit]")));

    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        stdout(&output).contains("describe-snap: snapshot matches: "),
        "{}",
        stdout(&output)
    );
}

#[test]
fn update_without_changes_says_unchanged() {
    let case = case("unchanged");
    assert_eq!(case.run(&["--update", "bar"]).status.code(), Some(0));
    let output = case.run(&["--update", "bar"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        stdout(&output).contains("describe-snap: snapshot unchanged: "),
        "{}",
        stdout(&output)
    );
    assert!(
        case.calls_of("diff").is_empty(),
        "no diff on an unchanged snapshot"
    );
}

#[test]
fn a_missing_snapshot_is_a_failure() {
    let case = case("missing-snapshot");
    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        stderr(&output),
        format!(
            "describe-snap: no committed snapshot at {}/tests/bar.describe.txt; run: describe-snap.sh --update bar\n",
            case.project.display()
        )
    );
}

#[test]
fn plain_text_is_normalised_and_masked() {
    let case = case("plain");
    let plain = case.dir.join("plain.txt");
    fs::write(
        &plain,
        "tree   \nclock 09:51\n«Media: Track at 0,0 100×50»\n«Weather +5 °C»\nvolume \"-50 dB\"\n",
    )
    .unwrap();
    let output = case.run_with(
        &["--update", "bar"],
        &[
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_DESCRIBE_PLAIN_FILE", plain.to_str().unwrap()),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert_eq!(
        case.read("tests/bar.describe.txt"),
        "tree\nclock HH:MM\n«Media: …»\n«Weather …»\nvolume \"-NN dB\"\n"
    );
}

#[test]
fn media_geometry_is_masked_after_the_media_text() {
    let case = case("geometry");
    let plain = case.dir.join("plain.txt");
    fs::write(&plain, "«Media: Track» at 12,34 567×890\n").unwrap();
    let output = case.run_with(
        &["--update", "bar"],
        &[
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_DESCRIBE_PLAIN_FILE", plain.to_str().unwrap()),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert_eq!(
        case.read("tests/bar.describe.txt"),
        "«Media: …» at …,NN …×NN\n"
    );
}

#[test]
fn json_drift_names_the_top_level_keys_and_changed_lines() {
    let case = case("json-drift");
    case.snapshot("bar", "{\n  \"bar\": 1,\n  \"clock\": \"HH:MM\"\n}\n");
    let json = case.dir.join("new.json");
    fs::write(&json, "{\"bar\":2,\"baz\":3,\"clock\":\"10:00\"}\n").unwrap();
    let output = case.run_with(
        &["bar"],
        &[("FAKE_DESCRIBE_JSON_FILE", json.to_str().unwrap())],
    );
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(out.contains("describe-snap: drift: +"), "{out}");
    assert!(
        out.contains("describe-snap:   + top-level key added: baz"),
        "{out}"
    );
    assert!(
        out.contains("describe-snap:   ~ top-level key changed: bar"),
        "{out}"
    );
    assert!(
        out.contains("describe-snap:   first changed lines:"),
        "{out}"
    );
    let err = stderr(&output);
    assert!(
        err.contains("describe-snap: describe tree drifted from ")
            && err.contains("(review the drift above; --update rewrites it)"),
        "{err}"
    );
}

#[test]
fn a_plain_drift_is_summarised_and_update_rewrites_it() {
    let case = case("plain-drift");
    case.snapshot("bar", "one\ntwo\n");
    let plain = case.dir.join("plain.txt");
    fs::write(&plain, "one\nthree\n").unwrap();
    let extra = &[
        ("FAKE_DESCRIBE_JSON_CODE", "1"),
        ("FAKE_DESCRIBE_PLAIN_FILE", plain.to_str().unwrap()),
    ];
    let output = case.run_with(&["bar"], extra);
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(out.contains("describe-snap: drift: +1/-1 lines"), "{out}");
    assert!(
        out.contains("describe-snap:   first changed lines:"),
        "{out}"
    );
    assert!(!out.contains("top-level key"), "{out}");

    let output = case.run_with(&["--update", "bar"], extra);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("describe-snap: drift: +1/-1 lines"));
    assert_eq!(case.read("tests/bar.describe.txt"), "one\nthree\n");
}

#[test]
fn the_tree_is_read_until_two_reads_agree() {
    let case = case("settle");
    let sequence = case.dir.join("sequence");
    fs::create_dir_all(&sequence).unwrap();
    fs::write(sequence.join("1.txt"), "{\"a\":1}\n").unwrap();
    fs::write(sequence.join("2.txt"), "{\"a\":2}\n").unwrap();
    fs::write(sequence.join("last.txt"), "{\"a\":2}\n").unwrap();
    let output = case.run_with(
        &["--update", "bar"],
        &[("FAKE_DESCRIBE_SEQUENCE", sequence.to_str().unwrap())],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert_eq!(case.read("tests/bar.describe.txt"), "{\n  \"a\": 2\n}\n");
    let describes = case
        .calls_of("pleamar")
        .iter()
        .filter(|line| line.contains("[describe] [json]"))
        .count();
    assert_eq!(describes, 3);
    assert_eq!(
        case.calls_of("sleep")
            .iter()
            .filter(|line| line.contains("[0.5]"))
            .count(),
        1
    );
}

#[test]
fn ten_moving_reads_are_reported_and_the_last_one_is_used() {
    let case = case("moving");
    let sequence = case.dir.join("sequence");
    fs::create_dir_all(&sequence).unwrap();
    for number in 1..=11 {
        fs::write(
            sequence.join(format!("{number}.txt")),
            format!("{{\"a\":{number}}}\n"),
        )
        .unwrap();
    }
    fs::write(sequence.join("last.txt"), "{\"a\":11}\n").unwrap();
    let output = case.run_with(
        &["--update", "bar"],
        &[("FAKE_DESCRIBE_SEQUENCE", sequence.to_str().unwrap())],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stdout(&output)
        .contains("describe-snap: the tree was still moving after 10 reads; using the last one"));
    assert_eq!(case.read("tests/bar.describe.txt"), "{\n  \"a\": 11\n}\n");
}

#[test]
fn an_empty_tree_is_not_a_snapshot() {
    let case = case("empty");
    let empty = case.dir.join("empty.txt");
    fs::write(&empty, "").unwrap();
    let output = case.run_with(
        &["--update", "bar"],
        &[
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_DESCRIBE_PLAIN_FILE", empty.to_str().unwrap()),
        ],
    );
    assert_eq!(
        output.status.code(),
        Some(2),
        "stdout: {}\nstderr: {}",
        stdout(&output),
        stderr(&output)
    );
    let err = stderr(&output);
    assert!(
        err.contains("describe-snap: error: the agent tree could not be normalised:"),
        "{err}"
    );
    assert_eq!(
        err.lines().last(),
        Some("describe-snap: error: cannot snapshot the agent tree (--keep-tmp keeps the raw output)")
    );
}

#[test]
fn a_capture_failure_is_exit_two_with_the_first_error_lines_and_log_tail() {
    let case = case("capture-fail");
    let output = case.run_with(
        &["--update", "bar"],
        &[
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_PLAIN_DESC_FAIL_AFTER", "1"),
        ],
    );
    assert_eq!(
        output.status.code(),
        Some(2),
        "stdout:\n{}\nstderr:\n{}",
        stdout(&output),
        stderr(&output)
    );
    let err = stderr(&output);
    assert!(
        err.contains("describe-snap: error: describe failed:"),
        "{err}"
    );
    assert!(err.contains("describe-snap: last lines of "), "{err}");
    assert!(
        err.contains("describe-snap: error: could not capture the agent tree"),
        "{err}"
    );
}

#[test]
fn a_runner_that_exits_early_is_exit_two() {
    let case = case("runner-dead");
    let output = case.run_with(
        &["bar"],
        &[
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_DESCRIBE_PLAIN", "0"),
        ],
    );
    assert_eq!(
        output.status.code(),
        Some(2),
        "stdout:\n{}\nstderr:\n{}",
        stdout(&output),
        stderr(&output)
    );
    let out = stdout(&output);
    assert!(
        out.contains("describe-snap: the runner exited before the scene answered"),
        "{out}"
    );
    let err = stderr(&output);
    assert!(
        err.contains("describe-snap: error: scene 'bar' never came up (see log above; --keep-tmp keeps the sandbox)"),
        "{err}"
    );
}

#[test]
fn a_scene_that_never_answers_times_out_as_exit_one() {
    let case = case("timeout");
    let hold = case.dir.join("hold");
    support::write_executable(&hold, "#!/bin/sh\nperl -e 'sleep 100'\n");
    let output = case.run_with(
        &["bar", "--timeout", "1"],
        &[
            ("PLEAMAR_WM_BIN", hold.to_str().unwrap()),
            ("FAKE_DESCRIBE_JSON_CODE", "1"),
            ("FAKE_DESCRIBE_PLAIN", "0"),
        ],
    );
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(
        out.contains("describe-snap: the scene did not answer 'describe' within 1s"),
        "{out}"
    );
    assert!(
        stderr(&output).contains("describe-snap: scene 'bar' never answered (see log above; --keep-tmp keeps the sandbox)"),
        "{}",
        stderr(&output)
    );
}

#[test]
fn systemd_mode_hands_the_hermetic_environment_to_systemd_run() {
    let case = case("systemd");
    let output = case.run_with(
        &["bar", "--systemd", "--update"],
        &[("WAYLAND_DISPLAY", "wayland-1")],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(
        out.contains(&format!(
            "describe-snap: hermetic files, the live compositor ({}/wayland-1), run through systemd-run",
            case.runtime.display()
        )),
        "{out}"
    );
    assert!(
        out.contains("describe-snap: starting the scene as pleamar-snap-bar-"),
        "{out}"
    );
    let calls = case.calls_of("systemd-run");
    assert_eq!(calls.len(), 1);
    let call = &calls[0];
    assert!(call.contains("[--user]"), "{call}");
    assert!(call.contains("[--collect]"), "{call}");
    assert!(call.contains("[--quiet]"), "{call}");
    assert!(
        call.contains(&format!(
            "[--setenv=WAYLAND_DISPLAY={}/wayland-1]",
            case.runtime.display()
        )),
        "{call}"
    );
    assert!(call.contains("[--setenv=XDG_RUNTIME_DIR="), "{call}");
    assert!(call.contains("[--scene] ["), "{call}");
    let stops = case
        .calls_of("systemctl")
        .into_iter()
        .filter(|line| line.contains("[--user] [stop]"))
        .count();
    assert_eq!(stops, 1);
}

#[test]
fn live_mode_starts_pleamar_in_the_ambient_session() {
    let case = case("live");
    let output = case.run_with(
        &["bar", "--live", "--update"],
        &[("WAYLAND_DISPLAY", "wayland-1")],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        stderr(&output).contains("describe-snap: warning: using the ambient environment (--live)")
    );
    let setsid = case.calls_of("setsid");
    assert_eq!(setsid.len(), 1);
    assert!(setsid[0].contains("[--scene] ["), "{}", setsid[0]);
}

#[test]
fn no_runner_and_bad_usage_are_tool_errors() {
    let mut case = case("no-runner");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "describe-snap: error: no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='/nonexistent/pleamar-wm'); pass --live to start the scene in the current session, or install pleamar-wm\n"
    );

    let case = Case::describe_snap("flags");
    let output = case.run(&["--timeout", "0"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "describe-snap: error: --timeout must be at least 1\n"
    );
    let output = case.run(&["--bogus"]);
    assert_eq!(
        stderr(&output),
        "describe-snap: error: unknown option: --bogus (try --help)\n"
    );
}

#[test]
fn a_broken_committed_snapshot_is_reported() {
    let case = case("broken-snapshot");
    case.snapshot("bar", "{\"bar\": 1,}");
    let output = case.run(&["--update", "bar"]);
    assert_eq!(output.status.code(), Some(1));
    let err = stderr(&output);
    assert!(
        err.contains("does not parse as its own format; fix it by hand or delete it and re-run with --update"),
        "{err}"
    );
}

#[test]
fn part_files_are_not_scenes() {
    let case = case("part-file");
    case.raw_scene("shells/bar/part.plm", "part shared\n");
    let output = case.run(&["--update", "bar"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
}

#[test]
fn the_scene_socket_directory_is_discovered_and_exported() {
    use std::os::unix::net::UnixListener;
    let case = case("socket");
    let directory = case.runtime.join("pleamar-1");
    fs::create_dir_all(&directory).unwrap();
    let _listener = UnixListener::bind(directory.join("bar.sock")).unwrap();
    let output = case.run(&["bar", "--live", "--update"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let recorded = fs::read_to_string(case.state.join("sockets")).unwrap_or_default();
    let lines: Vec<&str> = recorded.lines().collect();
    assert!(!lines.is_empty());
    assert!(lines
        .iter()
        .all(|line| *line == directory.display().to_string()));
}

#[test]
fn keep_tmp_keeps_the_describe_sandbox() {
    let case = case("keep-tmp");
    let output = case.run(&["bar", "--update", "--keep-tmp"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let line = stdout(&output)
        .lines()
        .find(|line| line.starts_with("describe-snap: hermetic environment under "))
        .unwrap()
        .to_string();
    let name = line.rsplit('/').next().unwrap().to_string();
    assert!(case.tmp.join(name).is_dir());
}
