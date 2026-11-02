//! Repository-root resolution: the shell scripts found `files/pleamar` from
//! their own path, the binaries use `PLEAMAR_ROOT` or the flake.

mod support;

use std::fs;

use support::{stderr, stdout, Case};

fn repo_fixture(case: &Case) -> std::path::PathBuf {
    let repo = case.dir.join("repo");
    let project = repo.join("files/pleamar");
    fs::create_dir_all(project.join("shells/bar")).unwrap();
    fs::create_dir_all(project.join("tests")).unwrap();
    fs::write(repo.join("flake.nix"), "{}\n").unwrap();
    fs::write(project.join("shells/bar/bar.plm"), "zone bar\n").unwrap();
    repo
}

#[test]
fn walks_up_to_the_flake_and_uses_files_pleamar() {
    let case = Case::measure("walk-up");
    let repo = repo_fixture(&case);
    let nested = repo.join("files/pleamar/shells/bar");
    let output = case.run_at(&nested, &["bar", "--seconds", "1"], &[], true);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        case.dir
            .join("repo/files/pleamar/tests/evidence/2026-01-02-bar.tsv")
            .is_file(),
        "{}",
        stdout(&output)
    );
}

#[test]
fn pleamar_root_accepts_the_tree_and_the_repository() {
    let case = Case::measure("root-tree");
    let repo = repo_fixture(&case);
    let mut case = case;
    case.set("PLEAMAR_ROOT", repo.join("files/pleamar").to_str().unwrap());
    let output = case.run(&["bar", "--seconds", "1"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));

    let case = Case::measure("root-repo");
    let repo = repo_fixture(&case);
    let mut case = case;
    case.set("PLEAMAR_ROOT", repo.to_str().unwrap());
    let output = case.run(&["bar", "--seconds", "1"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(repo
        .join("files/pleamar/tests/evidence/2026-01-02-bar.tsv")
        .is_file());
}

#[test]
fn a_bad_root_and_a_missing_flake_are_tool_errors() {
    let case = Case::measure("bad-root");
    let mut case = case;
    case.set("PLEAMAR_ROOT", "/nonexistent/pleamar");
    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert!(
        stderr(&output).contains("measure: error: PLEAMAR_ROOT='/nonexistent/pleamar' does not look like the pleamar tree"),
        "{}",
        stderr(&output)
    );

    let case = Case::measure("no-flake");
    let elsewhere = case.dir.join("elsewhere");
    fs::create_dir_all(&elsewhere).unwrap();
    let output = case.run_at(&elsewhere, &["bar"], &[], true);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).contains("measure: error: cannot locate the pleamar tree from "),
        "{}",
        stderr(&output)
    );
}

#[test]
fn help_needs_no_repository() {
    let case = Case::measure("help-no-root");
    let elsewhere = case.dir.join("elsewhere");
    fs::create_dir_all(&elsewhere).unwrap();
    let output = case.run_at(&elsewhere, &["--help"], &[], true);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stdout(&output).starts_with("measure.sh - run one scene"));
}
