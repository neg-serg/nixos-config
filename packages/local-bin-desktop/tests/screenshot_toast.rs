//! Hermetic tests for the `screenshot-toast` port.

mod support;

use std::path::PathBuf;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_screenshot-toast");
const IEND: &[u8] = b"IEND\xaeB`\x82";

fn shots(sandbox: &Sandbox) -> PathBuf {
    let directory = sandbox.case.join("shots");
    std::fs::create_dir_all(&directory).expect("create shots");
    directory
}

fn complete_png(sandbox: &Sandbox, directory: &PathBuf, name: &str, mtime: u64) -> PathBuf {
    let path = directory.join(name);
    sandbox.write(&path, IEND);
    sandbox.set_mtime(&path, mtime);
    path
}

fn envs<'a>(directory: &'a PathBuf, date: &'a str) -> Vec<(&'a str, &'a str)> {
    vec![
        ("PIC_INFO_DIR", directory.to_str().unwrap()),
        ("FAKE_DATE_OUT", date),
    ]
}

#[test]
fn explicit_file_forwards_to_pic_info() {
    let sandbox = Sandbox::new("st-explicit");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-info"),
        vec![call("pic-info", &[path.to_str().unwrap()])]
    );
    assert!(sandbox.calls("date").is_empty(), "unconditional path");
}

#[test]
fn pic_info_exit_status_is_the_toast_status() {
    let sandbox = Sandbox::new("st-status");
    sandbox.install_default_fakes();
    sandbox.fake("pic-info", "exit 5\n");
    let directory = shots(&sandbox);
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 5);
}

#[test]
fn newest_complete_png_is_announced() {
    let sandbox = Sandbox::new("st-newest");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let older = complete_png(&sandbox, &directory, "old.png", 1_767_000_000);
    let newer = complete_png(&sandbox, &directory, "new.png", 1_767_000_005);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-info"),
        vec![call("pic-info", &[newer.to_str().unwrap()])]
    );
    assert!(sandbox.calls("sleep").is_empty(), "IEND settles at once");
    assert_ne!(older, newer);
}

#[test]
fn incomplete_png_waits_all_forty_steps() {
    let sandbox = Sandbox::new("st-incomplete");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let path = directory.join("a.png");
    sandbox.write(&path, b"PNGDATA");
    sandbox.set_mtime(&path, 1_767_000_000);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.calls("sleep").len(), 40);
    assert_eq!(
        sandbox.calls("pic-info"),
        vec![call("pic-info", &[path.to_str().unwrap()])]
    );
}

#[test]
fn non_png_settles_on_two_matching_size_samples() {
    let sandbox = Sandbox::new("st-jpeg");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let path = directory.join("a.jpg");
    sandbox.write(&path, b"JPEGDATA");
    sandbox.set_mtime(&path, 1_767_000_000);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.calls("sleep").len(), 1);
    assert_eq!(
        sandbox.calls("pic-info"),
        vec![call("pic-info", &[path.to_str().unwrap()])]
    );
}

#[test]
fn already_announced_file_is_skipped() {
    let sandbox = Sandbox::new("st-stamp");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let key = format!("{} 1767000000 8", path.display());
    sandbox.write(
        &sandbox.run_dir.join("screenshot-toast-last"),
        key.as_bytes(),
    );
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("pic-info").is_empty());
}

#[test]
fn stale_file_is_skipped() {
    let sandbox = Sandbox::new("st-stale");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767001000"));
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("pic-info").is_empty());
    assert_eq!(sandbox.calls("date"), vec![call("date", &["+%s"])]);
}

#[test]
fn new_event_stamp_is_written() {
    let sandbox = Sandbox::new("st-write-stamp");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    let stamp = str_of(&sandbox.read(&sandbox.run_dir.join("screenshot-toast-last")));
    assert_eq!(stamp, format!("{} 1767000000 8", path.display()));
}

#[test]
fn missing_explicit_file_exits_0() {
    let sandbox = Sandbox::new("st-missing");
    sandbox.install_default_fakes();
    let path = sandbox.case.join("gone.png");
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log().is_empty());
}

#[test]
fn empty_directory_exits_0() {
    let sandbox = Sandbox::new("st-empty");
    sandbox.install_default_fakes();
    let directory = shots(&sandbox);
    let outcome = sandbox.run_env(BIN, &[], &envs(&directory, "1767000010"));
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log().is_empty());
}

#[test]
fn default_directory_is_pictures_shots() {
    let sandbox = Sandbox::new("st-default");
    sandbox.install_default_fakes();
    let pictures = sandbox.home.join("pic");
    let directory = pictures.join("shots");
    std::fs::create_dir_all(&directory).expect("create shots");
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("XDG_PICTURES_DIR", pictures.to_str().unwrap()),
            ("FAKE_DATE_OUT", "1767000010"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("pic-info"),
        vec![call("pic-info", &[path.to_str().unwrap()])]
    );
}

#[test]
fn missing_pic_info_fails_the_exec() {
    let sandbox = Sandbox::new("st-nohelper");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("pic-info")).expect("drop fake pic-info");
    let directory = shots(&sandbox);
    let path = complete_png(&sandbox, &directory, "a.png", 1_767_000_000);
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 127);
    let stderr = str_of(&outcome.stderr);
    assert!(
        stderr.contains(": line 86: exec: pic-info: not found\n"),
        "{stderr}"
    );
}
