//! Hermetic tests for the `wl-restore` port.
//!
//! The port must never pick a wallpaper of its own: a compositor crash used to
//! end in `wl random ~/pic/wl` and replace the user's picture. Every scenario
//! below asserts the exact `wl` argv, which is how "no random" is pinned.

mod support;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_wl-restore");

fn state(sandbox: &Sandbox, path: &str) -> std::path::PathBuf {
    let file = sandbox.home.join(".local/state/wl/state.json");
    let contents = format!(r#"{{"outputs":{{"eDP-1":{{"wallpaper_path":"{path}"}}}}}}"#);
    sandbox.write(&file, contents.as_bytes());
    file
}

fn wallpaper(sandbox: &Sandbox) -> std::path::PathBuf {
    let path = sandbox.home.join("wall.png");
    sandbox.write(&path, b"wall");
    path
}

fn last_good(sandbox: &Sandbox, path: &std::path::Path) {
    sandbox.write(
        &sandbox.home.join(".local/state/wl/last-good"),
        format!("{}\n", path.display()).as_bytes(),
    );
}

#[test]
fn valid_state_restores_without_a_fallback() {
    let sandbox = Sandbox::new("wl-valid");
    sandbox.install_default_fakes();
    let image = wallpaper(&sandbox);
    state(&sandbox, image.to_str().unwrap());
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.calls("systemctl"),
        vec![call("systemctl", &["--user", "start", "wl-daemon.service"])]
    );
    assert_eq!(
        sandbox.wl_calls(),
        vec![call("wl", &["query"]), call("wl", &["restore"]),]
    );
}

#[test]
fn stale_state_without_a_candidate_paints_nothing() {
    let sandbox = Sandbox::new("wl-stale");
    sandbox.install_default_fakes();
    state(&sandbox, "/nonexistent/wall.png");
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.wl_calls(), vec![call("wl", &["query"])]);
}

#[test]
fn stale_state_uses_the_producer_cache() {
    let sandbox = Sandbox::new("wl-stale-cache");
    sandbox.install_default_fakes();
    let image = wallpaper(&sandbox);
    state(&sandbox, "/nonexistent/wall.png");
    // The path the theme pipeline and the login layer read (INTERFACES §1.2).
    sandbox.write(
        &sandbox.home.join(".cache/pleamar/wallpaper-path"),
        format!("{}\n", image.display()).as_bytes(),
    );
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.wl_calls(),
        vec![
            call("wl", &["query"]),
            call("wl", &["img", image.to_str().unwrap()]),
        ]
    );
}

#[test]
fn missing_state_paints_nothing() {
    let sandbox = Sandbox::new("wl-nostate");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.wl_calls(), vec![call("wl", &["query"])]);
}

#[test]
fn failed_restore_repaints_the_saved_file() {
    let sandbox = Sandbox::new("wl-restorefail");
    sandbox.install_default_fakes();
    let image = wallpaper(&sandbox);
    state(&sandbox, image.to_str().unwrap());
    let outcome = sandbox.run_env(BIN, &[], &[("FAKE_WL_RESTORE_EXIT", "1")]);
    assert_eq!(outcome.code, 0);
    let mut expected = vec![call("wl", &["query"])];
    for _ in 0..5 {
        expected.push(call("wl", &["restore"]));
    }
    expected.push(call("wl", &["img", image.to_str().unwrap()]));
    assert_eq!(sandbox.wl_calls(), expected);
    assert_eq!(
        sandbox
            .calls("sleep")
            .into_iter()
            .filter(|call| call.len() == 2 && call[1] == "0.3")
            .count(),
        5,
        "every refused restore waits before the next attempt"
    );
}

#[test]
fn waits_for_the_daemon_socket() {
    let sandbox = Sandbox::new("wl-wait");
    sandbox.install_default_fakes();
    sandbox.write(&sandbox.wl_counter, b"3");
    let image = wallpaper(&sandbox);
    state(&sandbox, image.to_str().unwrap());
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.wl_calls().len(), 5, "4 queries and the restore");
    assert_eq!(
        sandbox
            .calls("sleep")
            .into_iter()
            .filter(|call| call.len() == 2 && call[1] == "0.5")
            .count(),
        3
    );
}

#[test]
fn a_failing_paint_exits_with_its_code_and_never_randomises() {
    let sandbox = Sandbox::new("wl-imgfail");
    sandbox.install_default_fakes();
    let image = wallpaper(&sandbox);
    state(&sandbox, "/nonexistent/wall.png");
    last_good(&sandbox, &image);
    sandbox.fake(
        "wl",
        "case \"$1\" in\n  query) exit 0 ;;\n  img) exit 9 ;;\nesac\nexit 0\n",
    );
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 9);
    assert_eq!(
        sandbox.wl_calls(),
        vec![
            call("wl", &["query"]),
            call("wl", &["img", image.to_str().unwrap()]),
        ]
    );
}

#[test]
fn state_without_outputs_paints_nothing() {
    let sandbox = Sandbox::new("wl-badstate");
    sandbox.install_default_fakes();
    let file = sandbox.home.join(".local/state/wl/state.json");
    sandbox.write(&file, b"{}");
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.wl_calls(), vec![call("wl", &["query"])]);
}
