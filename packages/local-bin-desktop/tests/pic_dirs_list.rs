//! Hermetic tests for the `pic-dirs-list` port.

mod support;

use std::path::PathBuf;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pic-dirs-list");

fn tree(sandbox: &Sandbox) -> PathBuf {
    let root = sandbox.case.join("pic");
    for relative in ["a/b/c", ".git/x", "z"] {
        std::fs::create_dir_all(root.join(relative)).expect("create tree");
    }
    root
}

fn pictures(sandbox: &Sandbox, root: &PathBuf) -> Vec<Vec<String>> {
    sandbox
        .calls("zoxide")
        .into_iter()
        .filter(|call| call.len() == 4 && call[1] == "add" && call[2] == "--")
        .filter(|call| call[3].starts_with(root.to_str().unwrap()))
        .collect()
}

#[test]
fn help_prints_the_single_usage_line() {
    let sandbox = Sandbox::new("pdl-help");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["-h"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"Usage: pic-dirs-list\n");
    assert_eq!(outcome.stderr, b"");
}

#[test]
fn missing_pictures_dir_exits_0() {
    let sandbox = Sandbox::new("pdl-noxdg");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log().is_empty());
}

#[test]
fn missing_inotifywait_exits_0() {
    let sandbox = Sandbox::new("pdl-noinotify");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("inotifywait")).expect("drop fake");
    let root = tree(&sandbox);
    let outcome = sandbox.run_env(BIN, &[], &[("XDG_PICTURES_DIR", root.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log().is_empty());
}

#[test]
fn index_walks_three_levels_and_skips_git() {
    let sandbox = Sandbox::new("pdl-index");
    sandbox.install_default_fakes();
    let root = tree(&sandbox);
    sandbox.write(
        &sandbox.inotify,
        format!("{} CREATE\n", root.display()).as_bytes(),
    );
    let outcome = sandbox.run_env(BIN, &[], &[("XDG_PICTURES_DIR", root.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    let indexed: Vec<String> = pictures(&sandbox, &root)
        .into_iter()
        .map(|call| call[3].clone())
        .collect();
    let mut expected: Vec<String> = ["", "/a", "/a/b", "/a/b/c", "/z"]
        .iter()
        .map(|suffix| format!("{}{suffix}", root.display()))
        .collect();
    // Directory order comes from the filesystem; the set is what matters.
    let mut indexed = indexed;
    indexed.sort();
    expected.sort();
    assert_eq!(indexed, expected);
    assert_eq!(
        sandbox.calls("inotifywait"),
        vec![call(
            "inotifywait",
            &[
                "-q",
                "-m",
                "-e",
                "create",
                "-e",
                "delete",
                root.to_str().unwrap()
            ]
        )]
    );
}

#[test]
fn trailing_slash_is_stripped() {
    let sandbox = Sandbox::new("pdl-slash");
    sandbox.install_default_fakes();
    let root = tree(&sandbox);
    sandbox.write(&sandbox.inotify, b"");
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[("XDG_PICTURES_DIR", &format!("{}/", root.display()))],
    );
    assert_eq!(outcome.code, 0);
    let calls = sandbox.calls("inotifywait");
    assert_eq!(calls[0][7], root.to_str().unwrap());
}

#[test]
fn isdir_event_reindexes_and_other_events_do_not() {
    let sandbox = Sandbox::new("pdl-events");
    sandbox.install_default_fakes();
    let root = tree(&sandbox);

    sandbox.write(
        &sandbox.inotify,
        format!("{} CREATE,ISDIR\n", root.display()).as_bytes(),
    );
    let outcome = sandbox.run_env(BIN, &[], &[("XDG_PICTURES_DIR", root.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    assert_eq!(pictures(&sandbox, &root).len(), 10, "index twice");

    sandbox.reset();
    sandbox.install_default_fakes();
    let root = tree(&sandbox);
    sandbox.write(
        &sandbox.inotify,
        format!("{} CREATE\n", root.display()).as_bytes(),
    );
    let outcome = sandbox.run_env(BIN, &[], &[("XDG_PICTURES_DIR", root.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    assert_eq!(pictures(&sandbox, &root).len(), 5, "index once");
}

#[test]
fn inotifywait_failure_ends_the_watch_silently() {
    let sandbox = Sandbox::new("pdl-inotifyfail");
    sandbox.install_default_fakes();
    sandbox.fake("inotifywait", "printf 'Watch out\\n' >&2\nexit 1\n");
    let root = tree(&sandbox);
    let outcome = sandbox.run_env(BIN, &[], &[("XDG_PICTURES_DIR", root.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stderr, b"Watch out\n");
}
