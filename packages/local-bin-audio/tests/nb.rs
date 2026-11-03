//! Hermetic tests for the `nb` port: help on stderr, the git argv sequence, the
//! line-count commit gate, the `music/list` redirect and the tolerated
//! failures.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_nb");

const GIT: &str = r#"case "$*" in
  *" pull"*) exit "${FAKE_GIT_PULL_CODE:-0}" ;;
  *" status --short -b"*) printf '%s' "${FAKE_GIT_STATUS:-}"; exit "${FAKE_GIT_STATUS_CODE:-0}" ;;
  *" add ."*) exit 0 ;;
  *" commit "*) exit 0 ;;
  *" push"*) exit "${FAKE_GIT_PUSH_CODE:-0}" ;;
esac
exit 0
"#;
const DATE: &str = "printf '01-02-2024 03:04:05\\n'\n";
const FIND: &str = "printf '%s\\n' \"$HOME/music\" \"$HOME/music/alpha\"\n";
const SORT: &str = "printf 'sorted-music-line\\n'\n";
const MKDIR: &str = "exit \"${FAKE_MKDIR_CODE:-0}\"\n";
const ZK: &str = "exit 0\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("git", GIT);
    sandbox.fake("date", DATE);
    sandbox.fake("find", FIND);
    sandbox.fake("sort", SORT);
    sandbox.fake("mkdir", MKDIR);
    sandbox
}

fn ready(sandbox: &Sandbox) {
    sandbox.write_home("notes/music/.keep", b"");
}

#[test]
fn help_goes_to_stderr_and_exits_zero() {
    let sandbox = fixture("help");
    for flag in ["-h", "--help"] {
        let outcome = sandbox.run(&[flag]);
        assert_eq!(outcome.code, 0);
        assert_eq!(outcome.stdout, b"");
        assert_eq!(
            text(&outcome.stderr),
            "nb: update notes and push if changed\n"
        );
    }
    assert_eq!(sandbox.log(), "");
}

#[test]
fn a_clean_repository_only_refreshes_the_list() {
    let sandbox = fixture("clean");
    ready(&sandbox);
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS", "## main...origin/main\n")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");
    assert_eq!(
        sandbox.log_lines_for("git"),
        vec![
            format!("git\t-C\t{}/notes\tpull", sandbox.home.display()),
            format!(
                "git\t-C\t{}/notes\tstatus\t--short\t-b",
                sandbox.home.display()
            ),
        ]
    );
    assert_eq!(
        sandbox.log_lines_for("mkdir"),
        vec![format!("mkdir\t-p\t{}/notes/music", sandbox.home.display())]
    );
    assert_eq!(
        sandbox.log_lines_for("find"),
        vec![format!(
            "find\t{}/music\t-maxdepth\t1\t-type\td",
            sandbox.home.display()
        )]
    );
    assert_eq!(sandbox.log_lines_for("sort"), vec!["sort"]);
    assert_eq!(
        text(&sandbox.read_home("notes/music/list")),
        "sorted-music-line\n"
    );
    assert!(sandbox.log_lines_for("date").is_empty());
}

#[test]
fn changed_lines_trigger_add_commit_and_push() {
    let sandbox = fixture("dirty");
    ready(&sandbox);
    sandbox.fake("zk", ZK);
    let status = "## main...origin/main\n M a.md\n?? b.md\n";
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS", status)]);
    assert_eq!(outcome.code, 0);
    let git = sandbox.log_lines_for("git");
    let repo = format!("{}/notes", sandbox.home.display());
    assert_eq!(
        git,
        vec![
            format!("git\t-C\t{repo}\tpull"),
            format!("git\t-C\t{repo}\tstatus\t--short\t-b"),
            format!("git\t-C\t{repo}\tadd\t."),
            format!("git\t-C\t{repo}\tcommit\t-am\tupdate notes 01-02-2024 03:04:05"),
            format!("git\t-C\t{repo}\tpush"),
        ]
    );
    assert_eq!(
        sandbox.log_lines_for("zk"),
        vec![format!("zk\t-W\t{repo}\tindex")]
    );
}

#[test]
fn a_single_status_line_does_not_commit() {
    let sandbox = fixture("branch-only");
    ready(&sandbox);
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS", "## main...origin/main\n")]);
    assert_eq!(outcome.code, 0);
    assert!(!sandbox.log().contains("\tcommit\t"));
    assert!(!sandbox.log().contains("\tadd\t"));
}

#[test]
fn zk_is_skipped_when_missing() {
    let sandbox = fixture("no-zk");
    ready(&sandbox);
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS", "## x\n M a.md\n")]);
    assert_eq!(outcome.code, 0);
    assert!(!sandbox.log().contains("zk\t"));
}

#[test]
fn a_missing_git_is_not_fatal() {
    let sandbox = fixture("no-git");
    ready(&sandbox);
    sandbox.remove_fake("git");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let stderr = text(&outcome.stderr);
    assert!(stderr.starts_with("nb: missing git\n"), "{stderr}");
    assert!(
        stderr.contains(&format!(
            "{}: line 20: git: command not found\n",
            sandbox.program().display()
        )),
        "{stderr}"
    );
    assert!(
        stderr.contains(&format!(
            "{}: line 24: git: command not found\n",
            sandbox.program().display()
        )),
        "{stderr}"
    );
    assert_eq!(sandbox.log_lines_for("find").len(), 1);
    assert_eq!(sandbox.log_lines_for("sort").len(), 1);
}

#[test]
fn pull_and_push_failures_are_tolerated() {
    let sandbox = fixture("remote-fail");
    ready(&sandbox);
    let outcome = sandbox.run_env(
        &[],
        &[
            ("FAKE_GIT_STATUS", "## x\n M a.md\n"),
            ("FAKE_GIT_PULL_CODE", "3"),
            ("FAKE_GIT_PUSH_CODE", "4"),
        ],
    );
    assert_eq!(outcome.code, 0);
}

#[test]
fn a_failing_status_pipeline_counts_zero_lines() {
    let sandbox = fixture("status-fail");
    ready(&sandbox);
    // No output and a failing status: the pipeline still produces `0` lines.
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS_CODE", "1")]);
    assert_eq!(outcome.code, 0);
    assert!(!sandbox.log().contains("\tcommit\t"));
}

#[test]
fn a_missing_date_leaves_the_commit_message_short() {
    let sandbox = fixture("no-date");
    ready(&sandbox);
    sandbox.remove_fake("date");
    let outcome = sandbox.run_env(&[], &[("FAKE_GIT_STATUS", "## x\n M a.md\n")]);
    assert_eq!(outcome.code, 0);
    let stderr = text(&outcome.stderr);
    assert!(
        stderr.contains(&format!(
            "{}: line 30: date: command not found\n",
            sandbox.program().display()
        )),
        "{stderr}"
    );
    assert!(
        sandbox.log().contains("\tcommit\t-am\tupdate notes \n"),
        "{}",
        sandbox.log()
    );
}

#[test]
fn an_unopenable_list_skips_the_pipeline_but_runs_find() {
    let sandbox = fixture("blocked-list");
    sandbox.write_home("notes", b"not a directory\n");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let stderr = text(&outcome.stderr);
    assert!(
        stderr.contains(&format!(
            "{}: line 22: {}/notes/music/list: Not a directory\n",
            sandbox.program().display(),
            sandbox.home.display()
        )),
        "{stderr}"
    );
    // bash forks the producer before the failed redirection is noticed.
    assert_eq!(sandbox.log_lines_for("find").len(), 1);
    assert!(sandbox.log_lines_for("sort").is_empty());
}
