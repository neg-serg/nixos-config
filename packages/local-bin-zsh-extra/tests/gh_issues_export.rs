//! Hermetic tests for the `gh-issues-export` port.
//!
//! `gh` is a fake that serves fixture JSON; there is no network and no GitHub
//! token. Output directories and metadata live under the per-case temporary
//! tree.

mod support;

use std::path::Path;

use serde_json::Value;

use support::{exited, expected_argv, stderr, stdout, Case, MKDIR};

const BIN: &str = env!("CARGO_BIN_EXE_gh-issues-export");
const USAGE: &str = include_str!("../src/gh_issues_export_usage.txt");

const GH: &str = r#"#!/bin/sh
{ printf 'gh\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/gh.argv"
case "$1" in
  auth) exit "${FAKE_GH_AUTH_CODE:-0}" ;;
  api)
    case "$2" in
      --paginate)
        case "$3" in
          */comments*) printf '%s' "${FAKE_GH_COMMENTS-}"; exit "${FAKE_GH_COMMENTS_CODE:-0}" ;;
          *) printf '%s' "${FAKE_GH_ISSUES-}"; exit "${FAKE_GH_ISSUES_CODE:-0}" ;;
        esac
        ;;
      /rate_limit) printf '%s' "${FAKE_GH_RATE-}"; exit "${FAKE_GH_RATE_CODE:-0}" ;;
      *) exit "${FAKE_GH_REPO_CODE:-0}" ;;
    esac
    ;;
esac
exit 0
"#;

const SLEEP: &str = r#"#!/bin/sh
{ printf 'sleep\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/sleep.argv"
exit "${FAKE_SLEEP_CODE:-0}"
"#;

const ISSUE: &str = r#"[
  {
    "number": 7,
    "title": "A \"quoted\" title",
    "state": "open",
    "user": {"login": "alice"},
    "labels": [{"name": "bug"}, {"name": "help wanted"}],
    "assignees": [{"login": "bob"}],
    "milestone": {"title": "v1"},
    "created_at": "2026-01-02T03:04:05Z",
    "updated_at": "2026-01-03T04:05:06Z",
    "closed_at": null,
    "html_url": "https://github.com/o/r/issues/7",
    "comments": 0,
    "body": "Intro\n<!-- hidden -->\nOutro"
  }
]
"#;

const ISSUE_MARKDOWN: &str = "\
---
number: 7
title: \"A \\\"quoted\\\" title\"
state: open
author: alice
labels: [\"bug\", \"help wanted\"]
assignees: [\"bob\"]
milestone: \"v1\"
created_at: \"2026-01-02T03:04:05Z\"
updated_at: \"2026-01-03T04:05:06Z\"
url: \"https://github.com/o/r/issues/7\"
comments_count: 0
---

Intro

Outro
";

fn case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("gh", GH);
    case.write_fake("mkdir", MKDIR);
    case
}

fn read(case: &Case, path: &str) -> String {
    case.read_at(&case.path(path))
}

fn run_with_issues(case: &Case, args: &[&str], issues: &str) -> std::process::Output {
    let mut command = case.command();
    command.env("FAKE_GH_ISSUES", issues);
    command.args(args);
    command.output().expect("run gh-issues-export")
}

#[test]
fn help_is_printed_without_touching_gh() {
    let case = case("gh-help");
    for argument in ["--help", "-h"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0);
        assert_eq!(stdout(&output), USAGE);
        assert_eq!(stderr(&output), "");
        assert_eq!(case.argv("gh"), "");
    }
}

#[test]
fn argument_errors_keep_the_original_messages() {
    let case = case("gh-args");
    for (arguments, expected) in [
        (
            vec!["--output"],
            "error: --output requires a directory argument\n",
        ),
        (vec!["--state"], "error: --state requires open|closed|all\n"),
        (
            vec!["--state", "bogus", "o/r"],
            "error: --state must be open, closed, or all\n",
        ),
        (vec!["--wat"], "error: unknown option --wat\n"),
        (
            vec!["o/r", "other/r"],
            "error: unexpected argument 'other/r'\n",
        ),
    ] {
        let output = case.run(&arguments);
        assert_eq!(exited(&output), 1, "{arguments:?}");
        assert!(
            stderr(&output).starts_with(expected),
            "{arguments:?}: {:?}",
            stderr(&output)
        );
    }
    let output = case.run(&[]);
    assert_eq!(exited(&output), 1);
    assert!(stderr(&output).starts_with("error: repository argument required\n"));
    assert!(stderr(&output).contains(USAGE));
    assert_eq!(case.argv("gh"), "");
}

#[test]
fn invalid_repository_formats_are_rejected() {
    let case = case("gh-repo-format");
    for repository in ["owner", "a/b/c", "a b/c", "https://example.com/o/r"] {
        let output = case.run(&[repository]);
        assert_eq!(exited(&output), 1, "{repository}");
        assert_eq!(
            stderr(&output),
            format!("error: invalid repository format '{repository}' (expected owner/repo)\n"),
            "{repository}"
        );
    }
    assert_eq!(case.argv("gh"), "");
}

#[test]
fn a_missing_gh_exits_two() {
    let case = case("gh-missing");
    case.remove_fake("gh");
    let output = case.run(&["o/r"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(
        stderr(&output),
        "error: gh CLI not found (add to environment.systemPackages: pkgs.gh)\n"
    );
}

#[test]
fn unauthenticated_gh_exits_two() {
    let case = case("gh-auth");
    let output = case
        .command()
        .env("FAKE_GH_AUTH_CODE", "1")
        .arg("o/r")
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 2);
    assert_eq!(
        stderr(&output),
        "error: gh CLI not authenticated (run: gh auth login)\n"
    );
}

#[test]
fn an_unreachable_repository_exits_three() {
    let case = case("gh-repo");
    let output = case
        .command()
        .env("FAKE_GH_REPO_CODE", "1")
        .arg("o/r")
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 3);
    assert_eq!(
        stderr(&output),
        "error: repository 'o/r' not found or access denied\n"
    );
}

#[test]
fn one_issue_without_comments_is_written_exactly() {
    let case = case("gh-one");
    let output = run_with_issues(&case, &["--output", "out", "o/r"], ISSUE);
    assert_eq!(exited(&output), 1, "{}", stderr(&output));
    assert_eq!(
        stdout(&output),
        "Fetching issues from o/r (state=all)...\n\
         Found 1 issues. Exporting...\n\
         [1/1] Exporting issue #7: A \"quoted\" title\n\
         \n\
         Export complete: 1/1 issues exported to out\n"
    );
    assert_eq!(read(&case, "out/7.md"), ISSUE_MARKDOWN);
    assert_eq!(case.argv("gh"), {
        let mut expected = expected_argv("gh", &["auth", "token"]);
        expected.push_str(&expected_argv("gh", &["api", "repos/o/r", "--silent"]));
        expected.push_str(&expected_argv(
            "gh",
            &[
                "api",
                "--paginate",
                "/repos/o/r/issues?state=all&per_page=100&sort=created&direction=asc",
            ],
        ));
        expected
    });
    let meta = read(&case, "out/.export-meta.json");
    let meta: Value = serde_json::from_str(&meta).expect("meta is JSON");
    assert_eq!(meta["repo"], "o/r");
    assert_eq!(meta["total_issues"], 1);
    assert_eq!(meta["export_version"], 1);
    let timestamp = meta["last_export_iso"].as_str().expect("timestamp");
    assert_eq!(timestamp.len(), 20, "{timestamp}");
    assert!(timestamp.ends_with('Z'), "{timestamp}");
}

#[test]
fn comments_and_the_rate_limit_probe_are_exported_in_order() {
    let case = case("gh-comments");
    let issue = r#"[
      {
        "number": 7,
        "title": "T",
        "state": "open",
        "user": {"login": "alice"},
        "labels": [],
        "assignees": [],
        "created_at": "2026-01-02T03:04:05Z",
        "updated_at": "2026-01-03T04:05:06Z",
        "html_url": "https://github.com/o/r/issues/7",
        "comments": 1,
        "body": "Body"
      }
    ]"#;
    let comments = r#"[{"user":{"login":"carol"},"created_at":"2026-01-04T05:06:07Z","body":"Thanks!\n<!-- x -->\nDone"}]"#;
    let output = case
        .command()
        .env("FAKE_GH_ISSUES", issue)
        .env("FAKE_GH_COMMENTS", comments)
        .env(
            "FAKE_GH_RATE",
            r#"{"resources":{"core":{"remaining":5000,"reset":0}}}"#,
        )
        .args(["--output", "out", "o/r"])
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 1, "{}", stderr(&output));
    let markdown = read(&case, "out/7.md");
    assert!(
        markdown.ends_with(
            "\nBody\n\n## Comment by carol on 2026-01-04T05:06:07Z\n\nThanks!\n<!-- x -->\nDone\n"
        ),
        "{markdown}"
    );
    let calls = case.argv("gh");
    let rate = calls.find("ARG /rate_limit").expect("rate probe");
    let comments_call = calls
        .find("ARG /repos/o/r/issues/7/comments")
        .expect("comments");
    assert!(rate < comments_call, "{calls}");
}

#[test]
fn pull_requests_are_filtered_out() {
    let case = case("gh-filter-pr");
    let issues = r#"[
      {"number": 1, "title": "PR", "pull_request": {"url": "x"}},
      {"number": 2, "title": "Issue", "pull_request": null},
      {"number": 3, "title": "No key"}
    ]"#;
    let output = run_with_issues(&case, &["--output", "out", "o/r"], issues);
    assert_eq!(exited(&output), 1, "{}", stderr(&output));
    assert!(!case.path("out/1.md").exists());
    assert!(case.path("out/2.md").exists());
    assert!(case.path("out/3.md").exists());
}

#[test]
fn concatenated_pages_are_parsed() {
    let case = case("gh-pages");
    let issues = r#"[{"number": 1, "title": "One"}]
[{"number": 2, "title": "Two"}]"#;
    let output = run_with_issues(&case, &["--output", "out", "o/r"], issues);
    assert_eq!(exited(&output), 1, "{}", stderr(&output));
    assert!(case.path("out/1.md").exists());
    assert!(case.path("out/2.md").exists());
}

#[test]
fn no_issues_still_writes_metadata() {
    let case = case("gh-empty");
    let output = run_with_issues(&case, &["--output", "out", "o/r"], "[]");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "Fetching issues from o/r (state=all)...\nNo issues found.\n"
    );
    let meta: Value =
        serde_json::from_str(&read(&case, "out/.export-meta.json")).expect("meta is JSON");
    assert_eq!(meta["total_issues"], 0);
}

#[test]
fn a_fetch_failure_exits_four() {
    let case = case("gh-fetch-fail");
    let output = case
        .command()
        .env("FAKE_GH_ISSUES_CODE", "1")
        .args(["--output", "out", "o/r"])
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 4);
    assert_eq!(stderr(&output), "error: failed to fetch issues from o/r\n");
}

#[test]
fn an_export_write_failure_is_counted_and_exits_zero() {
    // `mkdir -p out` fails because `out` is a regular file, so the issue write
    // fails. The shell then takes the `failed > 0` branch, whose final print
    // makes the script exit 0 (the opposite of the no-failure path).
    let case = case("gh-write-fail");
    case.write(&case.path("out"), "not a directory\n");
    let output = run_with_issues(&case, &["--output", "out", "o/r"], ISSUE);
    assert_eq!(exited(&output), 0);
    assert!(stderr(&output).contains("export_issue:12: not a directory: out/7.md\n"));
    assert!(stderr(&output).contains("  warning: failed to export issue #7, skipping\n"));
    assert!(
        stderr(&output).contains("write_export_meta:6: not a directory: out/.export-meta.json\n")
    );
    assert!(stdout(&output).contains("Export complete: 0/1 issues exported to out\n"));
    assert!(stdout(&output).contains("  (1 issues failed — re-run to retry)\n"));
}

#[test]
fn a_comment_failure_is_a_warning_and_keeps_the_export() {
    let case = case("gh-comments-fail");
    let issue = r#"[{"number": 7, "title": "T", "state": "open", "user": {"login": "a"},
      "labels": [], "assignees": [], "created_at": "x", "updated_at": "y",
      "html_url": "z", "comments": 1, "body": "B"}]"#;
    let output = case
        .command()
        .env("FAKE_GH_ISSUES", issue)
        .env("FAKE_GH_COMMENTS_CODE", "1")
        .env(
            "FAKE_GH_RATE",
            r#"{"resources":{"core":{"remaining":5000,"reset":0}}}"#,
        )
        .args(["--output", "out", "o/r"])
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "  warning: failed to fetch comments for issue #7\n"
    );
    assert!(!read(&case, "out/7.md").contains("## Comment"));
}

#[test]
fn a_low_rate_limit_prints_the_wait_into_the_issue_file() {
    let case = case("gh-rate");
    case.write_fake("sleep", SLEEP);
    let issue = r#"[{"number": 7, "title": "T", "state": "open", "user": {"login": "a"},
      "labels": [], "assignees": [], "created_at": "x", "updated_at": "y",
      "html_url": "z", "comments": 1, "body": "B"}]"#;
    let output = case
        .command()
        .env("FAKE_GH_ISSUES", issue)
        .env("FAKE_GH_COMMENTS", "[]")
        .env(
            "FAKE_GH_RATE",
            r#"{"resources":{"core":{"remaining":10,"reset":9999999999}}}"#,
        )
        .args(["--output", "out", "o/r"])
        .output()
        .expect("run gh-issues-export");
    assert_eq!(exited(&output), 1);
    let markdown = read(&case, "out/7.md");
    assert!(
        markdown.contains("\nB\nRate limit low (10 remaining). Waiting "),
        "{markdown}"
    );
    assert!(
        case.argv("sleep").starts_with("sleep\nARG "),
        "{}",
        case.argv("sleep")
    );
}

#[test]
fn incremental_mode_reads_the_metadata_timestamp() {
    let case = case("gh-incremental");
    case.write(
        &case.path("out/.export-meta.json"),
        "{\"last_export_iso\":\"2026-01-01T00:00:00Z\"}\n",
    );
    let output = run_with_issues(&case, &["--output", "out", "o/r"], "[]");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "Incremental export: fetching issues updated since 2026-01-01T00:00:00Z\n\
         Fetching issues from o/r (state=all)...\nNo issues found.\n"
    );
    assert!(
        case.argv("gh").contains("&since=2026-01-01T00:00:00Z"),
        "{}",
        case.argv("gh")
    );
}

#[test]
fn full_mode_ignores_the_metadata_timestamp() {
    let case = case("gh-full");
    case.write(
        &case.path("out/.export-meta.json"),
        "{\"last_export_iso\":\"2026-01-01T00:00:00Z\"}\n",
    );
    let output = run_with_issues(&case, &["--full", "--output", "out", "o/r"], "[]");
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "Full export mode (--full)\nFetching issues from o/r (state=all)...\nNo issues found.\n"
    );
    assert!(!case.argv("gh").contains("since="));
}

#[test]
fn state_and_the_default_output_directory_are_honoured() {
    let case = case("gh-default-dir");
    let work = case.path("work");
    let mut command = case.command_in(&work);
    command.env("FAKE_GH_ISSUES", ISSUE);
    command.args(["--state", "closed", "https://github.com/o/r.git"]);
    let output = command.output().expect("run gh-issues-export");
    assert_eq!(exited(&output), 1, "{}", stderr(&output));
    assert!(
        stdout(&output).ends_with("exported to ./gh-issues/o-r\n"),
        "{:?}",
        stdout(&output)
    );
    assert!(work.join("gh-issues/o-r/7.md").exists());
    assert!(case.argv("gh").contains("state=closed"));
}

#[test]
fn an_empty_body_leaves_the_original_blank_lines() {
    let case = case("gh-empty-body");
    let issue = r#"[{"number": 1, "title": "T", "state": "open", "user": {"login": "a"},
      "labels": [], "assignees": [], "created_at": "x", "updated_at": "y",
      "html_url": "z", "comments": 0}]"#;
    let output = run_with_issues(&case, &["--output", "out", "o/r"], issue);
    assert_eq!(exited(&output), 1);
    let markdown = read(&case, "out/1.md");
    assert!(
        markdown.ends_with("comments_count: 0\n---\n\n\n"),
        "{markdown:?}"
    );
}

#[test]
fn unknown_repository_arguments_do_not_create_the_output_directory() {
    let case = case("gh-no-output");
    let output = case.run(&["--output", "out", "bad"]);
    assert_eq!(exited(&output), 1);
    assert!(!Path::new(&case.path("out")).exists());
}
