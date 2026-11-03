//! Hermetic tests for the `pic-info` port.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::PIC_INFO_USAGE;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pic-info");

fn shots(sandbox: &Sandbox) -> PathBuf {
    let directory = sandbox.case.join("shots");
    std::fs::create_dir_all(&directory).expect("create shots");
    directory
}

#[test]
fn help_prints_the_usage() {
    let sandbox = Sandbox::new("pi-help");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["-h"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, PIC_INFO_USAGE.as_bytes());
    assert!(sandbox.log().is_empty());
}

#[test]
fn help_without_pic_notify_fails_first() {
    let sandbox = Sandbox::new("pi-nohelper");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("pic-notify")).expect("drop fake");
    let outcome = sandbox.run(BIN, &["--help"]);
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"pic-info: pic-notify not found in PATH\n");
}

#[test]
fn newest_file_is_forwarded() {
    let sandbox = Sandbox::new("pi-newest");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let older = directory.join("a.png");
    let newer = directory.join("b.png");
    sandbox.write(&older, b"a");
    sandbox.write(&newer, b"b");
    sandbox.set_mtime(&older, 1_767_000_000);
    sandbox.set_mtime(&newer, 1_767_000_100);
    let outcome = sandbox.run_env(BIN, &[], &[("PIC_INFO_DIR", directory.to_str().unwrap())]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-notify"),
        vec![call("pic-notify", &[newer.to_str().unwrap()])]
    );
}

#[test]
fn empty_directory_is_an_error() {
    let sandbox = Sandbox::new("pi-empty");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let outcome = sandbox.run_env(BIN, &[], &[("PIC_INFO_DIR", directory.to_str().unwrap())]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        outcome.stderr,
        format!(
            "pic-info: no screenshots found in {}\n",
            directory.display()
        )
        .into_bytes()
    );
}

#[test]
fn missing_files_are_skipped_and_the_loop_continues() {
    let sandbox = Sandbox::new("pi-skip");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let present = directory.join("a.png");
    sandbox.write(&present, b"a");
    let missing = directory.join("gone.png");
    let outcome = sandbox.run(BIN, &[missing.to_str().unwrap(), present.to_str().unwrap()]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        outcome.stderr,
        format!("pic-info: skip missing {}\n", missing.display()).into_bytes()
    );
    assert_eq!(
        sandbox.calls("pic-notify"),
        vec![call("pic-notify", &[present.to_str().unwrap()])]
    );
}

#[test]
fn last_pic_notify_status_is_the_exit_status() {
    let sandbox = Sandbox::new("pi-status");
    sandbox.install_default_fakes();
    sandbox.fake("pic-notify", "exit \"${FAKE_PIC_NOTIFY_EXIT:-0}\"\n");
    let directory = shots(&sandbox);
    let file = directory.join("a.png");
    sandbox.write(&file, b"a");
    let outcome = sandbox.run_env(
        BIN,
        &[file.to_str().unwrap()],
        &[("FAKE_PIC_NOTIFY_EXIT", "3")],
    );
    assert_eq!(outcome.code, 3);
}

#[test]
fn tilde_expansion_reproduces_the_shell_quirk() {
    // `printf '%s/%s' "$HOME" "${1#~/}"` tilde-expands the pattern to $HOME/,
    // so a literal `~/x` never matches and reaches pic-notify as $HOME/~/x.
    let sandbox = Sandbox::new("pi-tilde");
    sandbox.install_default_fakes();
    sandbox.write(&sandbox.home.join("shot.png"), b"x");
    let outcome = sandbox.run(BIN, &["~/shot.png"]);
    assert_eq!(outcome.code, 0);
    let expected = format!("{}/~/shot.png", sandbox.home.display());
    assert!(sandbox.calls("pic-notify").is_empty());
    assert_eq!(
        outcome.stderr,
        format!("pic-info: skip missing {expected}\n").into_bytes()
    );
}

#[test]
fn default_directory_uses_pictures_shots() {
    let sandbox = Sandbox::new("pi-defaults");
    sandbox.install_default_fakes();
    let pictures = sandbox.home.join("pic");
    let directory = pictures.join("shots");
    std::fs::create_dir_all(&directory).expect("create shots");
    let file = directory.join("newest.png");
    sandbox.write(&file, b"a");
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[("XDG_PICTURES_DIR", pictures.to_str().unwrap())],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-notify"),
        vec![call("pic-notify", &[file.to_str().unwrap()])]
    );
}

#[test]
fn grim_default_dir_wins_over_pictures() {
    let sandbox = Sandbox::new("pi-grimdir");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let file = directory.join("a.png");
    sandbox.write(&file, b"a");
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("GRIM_DEFAULT_DIR", directory.to_str().unwrap()),
            (
                "XDG_PICTURES_DIR",
                sandbox.case.join("ignored").to_str().unwrap(),
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-notify"),
        vec![call("pic-notify", &[file.to_str().unwrap()])]
    );
}
