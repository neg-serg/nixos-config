//! End-to-end tests for the `pleamar-journal` binary.
//!
//! Every case runs the real binary against fake `journalctl`/`systemctl`
//! programs and a per-case temporary directory. The expected snapshot bytes
//! were produced by `files/pleamar/scripts/helpers/journal.sh` with the same
//! fakes (see tests/parity.sh, which repeats that comparison against the
//! shell directly).

mod support;

use std::io::Write;
use std::os::unix::process::ExitStatusExt;
use std::process::{Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::Value;

use support::{stderr, stdout, Case};

/// Entries covering the filter's edges: a real timestamp, a missing one, an
/// array MESSAGE, a numeric MESSAGE, an object MESSAGE (key order matters), a
/// numeric service, a falsy service fallback, an array join and non-ASCII text.
const WARN_EDGE: &str = r#"{"__REALTIME_TIMESTAMP":"1730000000123456","_SYSTEMD_UNIT":"x.service","MESSAGE":"hello"}
{"__REALTIME_TIMESTAMP":"0","SYSLOG_IDENTIFIER":"ident","MESSAGE":["line one","line two"]}
{"MESSAGE":"héllo\tnaïve\nsecond"}
{"__REALTIME_TIMESTAMP":"bogus","MESSAGE":42}
{"__REALTIME_TIMESTAMP":"1700000000000000","SYSLOG_IDENTIFIER":false,"MESSAGE":{"b":1,"a":2}}
{"_SYSTEMD_UNIT":5,"MESSAGE":true}
{"MESSAGE":["a",1,null,true,1.50,"b"]}
"#;

/// The exact line the shell's jq program wrote for `WARN_EDGE` under TZ=UTC.
const SNAPSHOT_EDGE: &str = r#"{"ok":true,"worker":"journal","version":1,"data":{"logs":2,"errors":1,"services":2,"entries":[{"time":"03:33","service":"x.service","msg":"hello"},{"time":"00:00","service":"ident","msg":"line one line two"},{"time":"00:00","service":"journal","msg":"héllo\tnaïve\nsecond"},{"time":"00:00","service":"journal","msg":"42"},{"time":"22:13","service":"journal","msg":"{\"b\":1,\"a\":2}"},{"time":"00:00","service":5,"msg":"true"},{"time":"00:00","service":"journal","msg":"a 1  true 1.50 b"}]}}
"#;

const EMPTY_SNAPSHOT: &str = "{\"ok\":true,\"worker\":\"journal\",\"version\":1,\"data\":{\"logs\":0,\"errors\":0,\"services\":0,\"entries\":[]}}\n";

/// jq 1.8.2's message for the `--argjson` value the failed pipeline produced.
/// The shell leaked it, so the port does too.
const ENTRIES_FAILURE: &str = "jq: invalid JSON text passed to --argjson\nUse jq --help for help with command-line options,\nor see the jq manpage, or online docs at https://jqlang.org\n";

fn run_with(case: &Case, variables: &[(&str, &str)], arguments: &[&str]) -> Output {
    let mut command = case.command();
    for (name, value) in variables {
        command.env(name, value);
    }
    command
        .args(arguments)
        .output()
        .expect("run pleamar-journal")
}

fn json(output: &Output) -> Value {
    serde_json::from_str(&stdout(output)).expect("one JSON object")
}

#[test]
fn help_is_the_shell_header_verbatim() {
    let case = Case::new("help");
    let output = case.run(&["--help"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(stdout(&output), include_str!("../src/usage.txt"));
    assert_eq!(stdout(&output).lines().count(), 19);
    assert!(stdout(&output).starts_with("# journal.sh - journal snapshot worker"));
    assert!(stdout(&output).ends_with("systemctl is missing.\n\n"));
}

#[test]
fn help_wins_only_before_an_unknown_argument() {
    let case = Case::new("help-order");
    let first = case.run(&["--help", "--bogus"]);
    assert_eq!(first.status.code(), Some(0));
    assert_eq!(stdout(&first), include_str!("../src/usage.txt"));

    let second = case.run(&["--bogus", "--help"]);
    assert_eq!(second.status.code(), Some(2));
    assert_eq!(stdout(&second), "");
    assert_eq!(stderr(&second), "journal: unknown argument '--bogus'\n");
}

#[test]
fn unknown_arguments_are_exit_2_with_the_shell_text() {
    let case = Case::new("unknown");
    for argument in ["--bogus", "positional", "-x"] {
        let output = case.run(&[argument]);
        assert_eq!(output.status.code(), Some(2), "argument {argument}");
        assert_eq!(stdout(&output), "", "argument {argument}");
        assert_eq!(
            stderr(&output),
            format!("journal: unknown argument '{argument}'\n"),
            "argument {argument}"
        );
    }
}

#[test]
fn an_option_without_its_value_is_silent_exit_1() {
    let case = Case::new("missing-value");
    for arguments in [
        vec!["--since"],
        vec!["--entries"],
        vec!["--entries", "3", "--since"],
    ] {
        let output = case.run(&arguments);
        assert_eq!(output.status.code(), Some(1), "arguments {arguments:?}");
        assert_eq!(stdout(&output), "", "arguments {arguments:?}");
        assert_eq!(stderr(&output), "", "arguments {arguments:?}");
    }
}

#[test]
fn the_argv_of_every_command_is_the_shell_argv() {
    let case = Case::new("argv");
    let output = run_with(&case, &[], &["--since", "-1h", "--entries", "3"]);
    assert_eq!(output.status.code(), Some(0));
    let argv_log = case.argv_log();
    assert_eq!(
        argv_log,
        concat!(
            "journalctl --user --since -1h --no-pager -o cat\n",
            "journalctl --user --since -1h -p err --no-pager -o cat\n",
            "systemctl --user list-units --type=service --state=running --no-legend\n",
            "journalctl --user --since -1h -p warning --no-pager -o json ",
            "--output-fields=__REALTIME_TIMESTAMP,_SYSTEMD_UNIT,SYSLOG_IDENTIFIER,MESSAGE -n 3\n",
        )
    );
}

#[test]
fn the_snapshot_is_one_line_with_the_shell_bytes() {
    let case = Case::new("snapshot");
    let output = run_with(
        &case,
        &[
            ("FAKE_LOG_OUT", "one\ntwo\n"),
            ("FAKE_ERR_OUT", "bad\n"),
            (
                "FAKE_SVC_OUT",
                "a.service loaded active running A\nb.service loaded active running B\n",
            ),
            ("FAKE_WARN_OUT", WARN_EDGE),
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(stdout(&output), SNAPSHOT_EDGE);
    assert_eq!(
        output.stdout.iter().filter(|byte| **byte == b'\n').count(),
        1,
        "the scene decodes one line"
    );
}

#[test]
fn counts_are_newline_bytes_of_a_successful_command() {
    let case = Case::new("counts");
    let output = run_with(
        &case,
        &[
            ("FAKE_LOG_OUT", "no trailing newline"),
            ("FAKE_ERR_OUT", "a\n\n"),
            ("FAKE_SVC_OUT", ""),
            ("FAKE_WARN_OUT", ""),
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    let snapshot = json(&output);
    assert_eq!(snapshot["data"]["logs"], 0);
    assert_eq!(snapshot["data"]["errors"], 2);
    assert_eq!(snapshot["data"]["services"], 0);
    assert_eq!(snapshot["data"]["entries"], serde_json::json!([]));
}

#[test]
fn a_failed_count_command_becomes_zero_and_the_snapshot_survives() {
    let case = Case::new("count-failures");
    let output = run_with(
        &case,
        &[
            ("FAKE_LOG_OUT", "x\n"),
            ("FAKE_LOG_CODE", "1"),
            ("FAKE_ERR_OUT", "y\n"),
            ("FAKE_ERR_CODE", "1"),
            ("FAKE_SVC_OUT", "z\n"),
            ("FAKE_SVC_CODE", "1"),
            ("FAKE_WARN_OUT", ""),
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), EMPTY_SNAPSHOT);
}

#[test]
fn a_failed_entries_command_reproduces_the_shell_pipefail_failure() {
    let case = Case::new("entries-failure");
    let output = run_with(
        &case,
        &[
            ("FAKE_WARN_OUT", "{\"MESSAGE\":\"x\"}\n"),
            ("FAKE_WARN_CODE", "1"),
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), ENTRIES_FAILURE);
}

#[test]
fn an_unparsable_entries_stream_is_an_empty_list_not_a_failure() {
    let case = Case::new("entries-garbage");
    for warn_code in ["0", "1"] {
        let output = run_with(
            &case,
            &[
                ("FAKE_WARN_OUT", "not json\n"),
                ("FAKE_WARN_CODE", warn_code),
                ("FAKE_LOG_OUT", ""),
            ],
            &[],
        );
        assert_eq!(output.status.code(), Some(0), "status {warn_code}");
        assert_eq!(stdout(&output), EMPTY_SNAPSHOT, "status {warn_code}");
    }
}

#[test]
fn an_empty_failed_entries_stream_is_still_the_pipefail_failure() {
    let case = Case::new("entries-empty-failure");
    let output = run_with(
        &case,
        &[("FAKE_WARN_OUT", ""), ("FAKE_WARN_CODE", "1")],
        &[],
    );
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), ENTRIES_FAILURE);
}

#[test]
fn jq_filter_failures_become_an_empty_list() {
    let case = Case::new("jq-failures");
    for entries in [
        "1\n",                                    // not an object
        "\"text\"\n",                             // not an object
        "{\"MESSAGE\":[[\"a\"],{\"b\":1}]}\n",    // nested join
        "{\"__REALTIME_TIMESTAMP\":\"1e300\"}\n", // localtime out of range
    ] {
        let output = run_with(&case, &[("FAKE_WARN_OUT", entries)], &[]);
        assert_eq!(output.status.code(), Some(0), "entries {entries:?}");
        assert_eq!(stdout(&output), EMPTY_SNAPSHOT, "entries {entries:?}");
    }
}

#[test]
fn missing_fields_get_the_filters_defaults() {
    let case = Case::new("defaults");
    let output = run_with(
        &case,
        &[("FAKE_WARN_OUT", "{\"__REALTIME_TIMESTAMP\":\"0\"}\n")],
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    let snapshot = json(&output);
    assert_eq!(
        snapshot["data"]["entries"],
        serde_json::json!([{"time": "00:00", "service": "journal", "msg": ""}])
    );
}

#[test]
fn time_is_formatted_in_the_host_timezone() {
    let case = Case::new("timezone");
    let entries = "{\"__REALTIME_TIMESTAMP\":\"1730000000123456\",\"MESSAGE\":\"x\"}\n";
    let utc = run_with(&case, &[("FAKE_WARN_OUT", entries)], &[]);
    assert_eq!(
        json(&utc)["data"]["entries"][0]["time"],
        serde_json::json!("03:33")
    );

    // A POSIX TZ string keeps the test independent of tzdata; `UTC-5` means
    // UTC+5, the same string jq's localtime_r reads.
    let mut command = case.command();
    command
        .env("TZ", "UTC-5")
        .env("FAKE_WARN_OUT", entries)
        .env("FAKE_ARGV_LOG", case.dir.join("argv-utc5.log"));
    let output = command.output().expect("run with TZ");
    assert_eq!(
        json(&output)["data"]["entries"][0]["time"],
        serde_json::json!("08:33")
    );
}

#[test]
fn a_missing_journalctl_is_the_shell_start_error() {
    let case = Case::new("no-journalctl");
    case.remove_fake("journalctl");
    let mut command = case.command();
    command.env("PATH", case.isolated_path());
    let output = command.output().expect("run without journalctl");
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "journal: journalctl not found\n");
}

#[test]
fn a_non_executable_journalctl_is_found_like_command_v() {
    // bash's `command -v` finds a regular file even without the execute bit;
    // the pipeline then fails at spawn time, which here is the entries
    // pipeline's duplicated-[] failure (exit 2), not the start error.
    let case = Case::new("non-executable-journalctl");
    case.set_mode("journalctl", 0o644);
    let mut command = case.command();
    command.env("PATH", case.isolated_path());
    let output = command.output().expect("run with a non-executable fake");
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), ENTRIES_FAILURE);
}

#[test]
fn neither_jq_nor_wc_is_needed() {
    let case = Case::new("no-jq");
    let mut command = case.command();
    command
        .env("PATH", case.isolated_path())
        .env("FAKE_WARN_OUT", "")
        .env("FAKE_ARGV_LOG", case.dir.join("argv-isolated.log"));
    let output = command.output().expect("run without jq");
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), EMPTY_SNAPSHOT);
}

#[test]
fn a_missing_systemctl_counts_zero_services() {
    let case = Case::new("no-systemctl");
    case.remove_fake("systemctl");
    // An isolated PATH keeps the host's real systemctl (and its 55 user
    // units) out of the result.
    let mut command = case.command();
    command.env("PATH", case.isolated_path());
    let output = command.output().expect("run without systemctl");
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(json(&output)["data"]["services"], 0);
}

#[test]
fn a_closed_stdin_still_produces_the_snapshot() {
    let case = Case::new("closed-stdin");
    let output = run_with(&case, &[], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), EMPTY_SNAPSHOT);
}

#[test]
fn stdin_commands_are_not_part_of_this_workers_protocol() {
    let case = Case::new("stdin-commands");
    let mut child = case
        .command()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn worker");
    {
        let stdin = child.stdin.as_mut().expect("stdin is piped");
        stdin
            .write_all(b"{\"cmd\":\"subscribe\",\"topic\":\"journal\",\"interval_ms\":100}\n{\"cmd\":\"stop\"}\n")
            .expect("write commands");
    }
    let output = child.wait_with_output().expect("wait for worker");
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), EMPTY_SNAPSHOT);
    assert_eq!(stderr(&output), "");
}

#[test]
fn sigterm_and_sigint_reap_the_child_and_die_by_the_signal() {
    for (name, signal) in [
        ("TERM", signal_hook::consts::SIGTERM),
        ("INT", signal_hook::consts::SIGINT),
    ] {
        let case = Case::new(&format!("signal-{name}"));
        let survived = case.dir.join("child-survived");
        let mut command = case.command();
        command
            .env("FAKE_SIGNAL_PARENT", "1")
            .env("FAKE_SIGNAL", name)
            .env("FAKE_SURVIVED", &survived);
        let mut child = command.spawn().expect("spawn worker");

        let started = Instant::now();
        let status = loop {
            if let Some(status) = child.try_wait().expect("try_wait") {
                break status;
            }
            assert!(
                started.elapsed() < Duration::from_secs(3),
                "the worker did not react to SIG{name}"
            );
            thread::sleep(Duration::from_millis(10));
        };

        assert_eq!(status.signal(), Some(signal), "status for SIG{name}");
        assert_eq!(status.code(), None, "status for SIG{name}");

        // The fake journalctl writes the marker one second after signalling
        // its parent; a reaped child never gets there.
        thread::sleep(Duration::from_millis(1300));
        assert!(
            !survived.exists(),
            "the journalctl child outlived the worker after SIG{name}"
        );
    }
}
