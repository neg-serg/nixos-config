//! Hermetic tests for the `qe` port: newest-mtime selection, `.git*`
//! exclusion, tie-breaking, the logical `$PWD` and the failure fallbacks.

mod support;

use std::fs::{self, File, FileTimes};
use std::os::unix::fs::symlink;
use std::time::{Duration, SystemTime};

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_qe");

fn fixture(label: &str) -> Sandbox {
    Sandbox::new(label, BIN)
}

fn set_mtime(path: &std::path::Path, nanos: u64) {
    let file = File::open(path).expect("open fixture for set_times");
    let times = FileTimes::new().set_modified(SystemTime::UNIX_EPOCH + Duration::from_nanos(nanos));
    file.set_times(times).expect("set fixture mtime");
}

fn dirs(sandbox: &Sandbox, names: &[&str]) {
    for name in names {
        fs::create_dir_all(sandbox.case.join(name)).expect("create fixture directory");
    }
}

#[test]
fn newest_subdirectory_wins() {
    let sandbox = fixture("newest");
    dirs(&sandbox, &["old", "new"]);
    set_mtime(&sandbox.case.join("old"), 1_000_000_000);
    set_mtime(&sandbox.case.join("new"), 2_000_000_000);
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("new").display())
    );
}

#[test]
fn nanosecond_mtimes_break_second_ties() {
    let sandbox = fixture("nanos");
    dirs(&sandbox, &["slower", "faster"]);
    set_mtime(&sandbox.case.join("slower"), 1_000_000_000);
    set_mtime(&sandbox.case.join("faster"), 1_000_000_001);
    let outcome = sandbox.run(&[]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("faster").display())
    );
}

#[test]
fn identical_mtimes_fall_back_to_the_greatest_name() {
    let sandbox = fixture("ties");
    dirs(&sandbox, &["alpha", "beta"]);
    set_mtime(&sandbox.case.join("alpha"), 5_000_000_000);
    set_mtime(&sandbox.case.join("beta"), 5_000_000_000);
    let outcome = sandbox.run(&[]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("beta").display())
    );
}

#[test]
fn git_directories_are_excluded_but_other_dot_directories_are_not() {
    let sandbox = fixture("dotdirs");
    dirs(&sandbox, &[".git", ".gitignore", ".hidden"]);
    set_mtime(&sandbox.case.join(".git"), 9_000_000_000);
    set_mtime(&sandbox.case.join(".gitignore"), 9_000_000_000);
    set_mtime(&sandbox.case.join(".hidden"), 1_000_000_000);
    let outcome = sandbox.run(&[]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join(".hidden").display())
    );
}

#[test]
fn symlinked_directories_are_not_candidates() {
    let sandbox = fixture("symlink");
    dirs(&sandbox, &["plain"]);
    fs::create_dir_all(sandbox.path("outside")).expect("create target directory");
    set_mtime(&sandbox.path("outside"), 9_000_000_000);
    symlink("../outside", sandbox.case.join("link")).expect("create symlink");
    set_mtime(&sandbox.case.join("plain"), 1_000_000_000);
    let outcome = sandbox.run(&[]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("plain").display())
    );
}

#[test]
fn a_missing_start_is_printed_verbatim() {
    let sandbox = fixture("missing");
    let outcome = sandbox.run(&["does-not-exist"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "does-not-exist\n");
    assert_eq!(outcome.stderr, b"");
}

#[test]
fn a_file_start_is_printed_verbatim() {
    let sandbox = fixture("file-start");
    sandbox.write("file.txt", b"x");
    let outcome = sandbox.run(&["file.txt"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "file.txt\n");
}

#[test]
fn an_empty_directory_falls_back_to_the_start_directory() {
    let sandbox = fixture("empty");
    for argument in [None, Some(".")] {
        let args: Vec<&str> = argument.into_iter().collect();
        let outcome = sandbox.run(&args);
        assert_eq!(outcome.code, 0);
        assert_eq!(
            text(&outcome.stdout),
            format!("{}\n", sandbox.case.display())
        );
    }
}

#[test]
fn an_empty_argument_means_dot() {
    let sandbox = fixture("empty-arg");
    let outcome = sandbox.run(&[""]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.display())
    );
}

#[test]
fn a_relative_start_is_resolved_against_pwd() {
    let sandbox = fixture("relative");
    dirs(&sandbox, &["tree/young", "tree/old"]);
    set_mtime(&sandbox.case.join("tree/young"), 2_000_000_000);
    set_mtime(&sandbox.case.join("tree/old"), 1_000_000_000);
    let outcome = sandbox.run(&["tree"]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("tree/young").display())
    );
}

#[test]
fn a_relative_start_with_dotdot_is_canonicalised_logically() {
    let sandbox = fixture("dotdot");
    dirs(&sandbox, &["deep/work/one", "deep/work/two"]);
    set_mtime(&sandbox.case.join("deep/work/one"), 1_000_000_000);
    set_mtime(&sandbox.case.join("deep/work/two"), 2_000_000_000);
    let outcome = sandbox.run(&["deep/work/.."]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("deep/work").display())
    );
}

#[test]
fn pwd_is_honoured_when_it_names_the_working_directory() {
    let sandbox = fixture("logical-pwd");
    dirs(&sandbox, &["newest"]);
    symlink(".", sandbox.case.join("alias")).expect("create alias");
    set_mtime(&sandbox.case.join("newest"), 2_000_000_000);
    let alias = sandbox.case.join("alias").to_string_lossy().to_string();
    let outcome = sandbox.run_env(&[], &[("PWD", &alias)]);
    assert_eq!(
        text(&outcome.stdout),
        format!("{}\n", sandbox.case.join("alias/newest").display())
    );
}
