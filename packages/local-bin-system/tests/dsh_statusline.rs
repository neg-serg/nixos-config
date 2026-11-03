//! Hermetic tests for the `dsh-statusline` port: the protocol subset the
//! flake guard (`scripts/dev/check-dsh-statusline.sh`) pins, the git segment,
//! `DSH_STATUSLINE_PARTS`, the worktree naming and the non-protocol modes.
//!
//! `git` is a fake that logs its argv and serves canned branch/status output,
//! so the test asserts exactly which `git -C …` calls the line costs.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_dsh-statusline");

const GIT: &str = r#"#!/bin/sh
printf 'git %s\n' "$*" >> "$FAKE_ARGV_LOG"
case " $* " in
  *" rev-parse --is-inside-work-tree "*)
    [ "${FAKE_INSIDE:-0}" = 1 ] && exit 0 || exit 1
    ;;
  *" rev-parse --abbrev-ref HEAD "*)
    printf '%s\n' "${FAKE_BRANCH-main}"
    exit "${FAKE_BRANCH_CODE:-0}"
    ;;
  *" status --porcelain=v1 "*)
    printf '%s' "${FAKE_STATUS-}"
    ;;
esac
exit 0
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("git", GIT);
    case
}

fn payload(_case: &Case, directory: &str, extra: &str) -> String {
    format!(
        "{{\"session_id\":\"s1\",\"turn\":7,\"workspace\":{{\"current_dir\":\"{}\"}}{extra}}}",
        directory
    )
}

fn protocol(case: &Case, directory: &str, extra: &str) -> std::process::Output {
    case.run_stdin(&[], payload(case, directory, extra).as_bytes())
}

fn line(case: &Case, directory: &str, extra: &str) -> String {
    stdout(&protocol(case, directory, extra))
}

#[test]
fn help_matches_the_header() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let text = stdout(&output);
    assert!(text.starts_with("dsh-statusline: one status line for a dsh session.\n"));
    assert!(text.contains("  dsh-statusline --git [DIR]"));
    assert!(
        text.contains("                         place,state,context,turn,cost (default: all)\n")
    );
    // The original prints header lines 2..30, which include the `set -eu`
    // after the comment block — an artifact the port reproduces.
    assert!(text.ends_with("\n\nset -eu\n"));
}

#[test]
fn unknown_option_is_an_error() {
    let case = fixture("unknown");
    let output = case.run(&["--nope"]);
    assert_eq!(exited(&output), 2);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "dsh-statusline: unknown option '--nope' (use --git, --demo, --help)\n"
    );
}

#[test]
fn protocol_renders_branch_state_context_turn_and_cost() {
    let case = fixture("protocol-full");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let status = " M tracked.txt\nM  staged.txt\n?? untracked.txt\n";
    let output = case.run_stdin_env(
        &[],
        payload(
            &case,
            &repo.to_string_lossy(),
            ",\"context\":{\"ratio\":0.42},\"cost\":{\"total_yuan\":0.1234}",
        )
        .as_bytes(),
        &[
            ("FAKE_INSIDE", "1"),
            ("FAKE_STATUS", status),
            ("FAKE_BRANCH", "main"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "⎇ main · ◆1 ✚1 ?1 · ctx 42% · turn 7 · ¥0.123\n"
    );
    assert_eq!(stderr(&output), "");
    let argv = case.argv_log();
    assert!(argv.contains("git -C "));
    assert!(argv.contains("rev-parse --is-inside-work-tree"));
    assert!(argv.contains("status --porcelain=v1"));
    assert!(argv.contains("rev-parse --abbrev-ref HEAD"));
}

#[test]
fn context_falls_back_to_tokens_and_to_tokens_per_max() {
    let case = fixture("context-tokens");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let tokens_only = line(
        &case,
        &repo.to_string_lossy(),
        ",\"context\":{\"estimated_tokens\":54000}",
    );
    assert!(tokens_only.contains("54k tok"), "{tokens_only}");

    let with_max = line(
        &case,
        &repo.to_string_lossy(),
        ",\"context\":{\"estimated_tokens\":54000,\"max_tokens\":128000}",
    );
    assert!(with_max.contains("ctx 42%"), "{with_max}");

    // ratio wins even when tokens/max are present.
    let ratio_wins = line(
        &case,
        &repo.to_string_lossy(),
        ",\"context\":{\"ratio\":0.5,\"estimated_tokens\":1,\"max_tokens\":100}",
    );
    assert!(ratio_wins.contains("ctx 50%"), "{ratio_wins}");
}

#[test]
fn turn_skips_minus_one_and_keeps_zero() {
    let case = fixture("turn");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let skipped = case.run_stdin(
        &[],
        format!(
            "{{\"turn\":-1,\"workspace\":{{\"current_dir\":\"{}\"}}}}",
            repo.to_string_lossy()
        )
        .as_bytes(),
    );
    assert!(!stdout(&skipped).contains("turn"), "{}", stdout(&skipped));
    let zero = case.run_stdin(
        &[],
        format!(
            "{{\"turn\":0,\"workspace\":{{\"current_dir\":\"{}\"}}}}",
            repo.to_string_lossy()
        )
        .as_bytes(),
    );
    assert!(stdout(&zero).contains("turn 0"), "{}", stdout(&zero));
}

#[test]
fn cost_is_hidden_when_zero_or_negative() {
    let case = fixture("cost");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    for cost in ["0", "0.0", "-2"] {
        let text = line(
            &case,
            &repo.to_string_lossy(),
            &format!(",\"cost\":{{\"total_yuan\":{cost}}}"),
        );
        assert!(!text.contains('¥'), "{cost}: {text}");
    }
}

#[test]
fn parts_filter_narrows_the_line() {
    let case = fixture("parts");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let output = case.run_stdin_env(
        &[],
        payload(&case, &repo.to_string_lossy(), "").as_bytes(),
        &[("DSH_STATUSLINE_PARTS", "turn")],
    );
    assert_eq!(stdout(&output), "turn 7\n");
    assert_eq!(stderr(&output), "");

    // No segment at all still prints exactly one non-empty line.
    let nothing = case.run_stdin_env(
        &[],
        payload(&case, &repo.to_string_lossy(), "").as_bytes(),
        &[("DSH_STATUSLINE_PARTS", "nope")],
    );
    assert_eq!(stdout(&nothing), "dsh\n");
}

#[test]
fn a_payload_with_nothing_usable_still_prints_one_line() {
    let case = fixture("empty-payload");
    let output = case.run_stdin(&[], b"{}");
    assert_eq!(exited(&output), 0);
    let text = stdout(&output);
    assert_eq!(text.lines().count(), 1);
    assert!(!text.trim().is_empty());
}

#[test]
fn malformed_json_degrades_instead_of_failing() {
    let case = fixture("malformed");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let output = case.run_in(&repo, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output).lines().count(), 1);
    assert!(!stdout(&output).trim().is_empty());

    let garbage = case.run_stdin(&[], b"not json");
    assert_eq!(exited(&garbage), 0);
    assert!(!stdout(&garbage).trim().is_empty());
}

#[test]
fn worktree_directories_are_named_by_their_last_component() {
    let case = fixture("worktree");
    let root = case.path("trees");
    let worktree = root.join("repo-abc12345/task-1");
    std::fs::create_dir_all(&worktree).expect("create worktree");

    let outside = stdout(&case.run_stdin_env(
        &[],
        payload(&case, &worktree.to_string_lossy(), "").as_bytes(),
        &[("FAKE_BRANCH", "")],
    ));
    assert!(outside.contains("task-1"), "{outside}");

    let output = case.run_stdin_env(
        &[],
        payload(&case, &worktree.to_string_lossy(), "").as_bytes(),
        &[
            ("DSH_WORKTREE_ROOT", &root.to_string_lossy()),
            ("FAKE_BRANCH", ""),
        ],
    );
    assert!(stdout(&output).contains("wt:task-1"), "{}", stdout(&output));
}

#[test]
fn git_only_prints_place_and_state() {
    let case = fixture("git-only");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let output = case.run_in_env(
        &repo,
        &["--git", &repo.to_string_lossy()],
        &[
            ("FAKE_INSIDE", "1"),
            ("FAKE_STATUS", " M a\n"),
            ("FAKE_BRANCH", "main"),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "⎇ main ✚1\n");

    // A directory argument that does not exist falls back to $PWD.
    let fallback = case.run_in_env(
        &repo,
        &["--git", "/definitely/not/here"],
        &[
            ("FAKE_INSIDE", "1"),
            ("FAKE_STATUS", ""),
            ("FAKE_BRANCH", "main"),
        ],
    );
    assert_eq!(stdout(&fallback), "⎇ main\n");
}

#[test]
fn demo_runs_the_protocol_against_a_canned_payload() {
    let case = fixture("demo");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let output = case.run_in_env(
        &repo,
        &["--demo"],
        &[("FAKE_INSIDE", "1"), ("FAKE_STATUS", " M a\n")],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "⎇ main · ✚1 · ctx 42% · turn 7 · ¥0.123\n");
}

#[test]
fn stdin_alias_and_clean_repository() {
    let case = fixture("stdin-alias");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let output = case.run_stdin_env(
        &["--stdin"],
        payload(&case, &repo.to_string_lossy(), "").as_bytes(),
        &[("FAKE_INSIDE", "1"), ("FAKE_BRANCH", "main")],
    );
    assert_eq!(stdout(&output), "⎇ main · turn 7\n");
}

#[test]
fn missing_git_degrades_to_the_directory_name() {
    let case = Case::new("no-git", BIN);
    let directory = case.path("plain");
    std::fs::create_dir_all(&directory).expect("create directory");
    let output = case.run_in_env(&directory, &[], &[]);
    // No fake git on PATH: no branch, no state, just the basename.
    assert_eq!(stdout(&output), "plain\n");
}

#[test]
fn a_directory_outside_a_work_tree_has_no_state() {
    let case = fixture("outside");
    let directory = case.path("plain");
    std::fs::create_dir_all(&directory).expect("create directory");
    let output = case.run_stdin_env(
        &[],
        payload(&case, &directory.to_string_lossy(), "").as_bytes(),
        &[("FAKE_INSIDE", "0"), ("FAKE_BRANCH", "main")],
    );
    let text = stdout(&output);
    assert!(text.contains("⎇ main"), "{text}");
    assert!(
        !text.contains('◆') && !text.contains('✚') && !text.contains('?'),
        "{text}"
    );
}

#[test]
fn context_percent_rounds_like_awk() {
    let case = fixture("rounding");
    let repo = case.path("repo");
    std::fs::create_dir_all(&repo).expect("create repo");
    let text = line(
        &case,
        &repo.to_string_lossy(),
        ",\"context\":{\"ratio\":0.425}",
    );
    assert!(text.contains("ctx 43%"), "{text}");
}
