//! Hermetic tests for the `wl-restore` port.

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
fn stale_state_falls_back_to_a_random_pick() {
    let sandbox = Sandbox::new("wl-stale");
    sandbox.install_default_fakes();
    state(&sandbox, "/nonexistent/wall.png");
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    let expected = format!("{}/pic/wl", sandbox.home.display());
    assert_eq!(
        sandbox.wl_calls(),
        vec![call("wl", &["query"]), call("wl", &["random", &expected]),]
    );
}

#[test]
fn stale_state_prefers_the_producer_cache_over_a_random_pick() {
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
fn missing_state_falls_back_to_a_random_pick() {
    let sandbox = Sandbox::new("wl-nostate");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    let expected = format!("{}/pic/wl", sandbox.home.display());
    assert_eq!(
        sandbox.wl_calls(),
        vec![call("wl", &["query"]), call("wl", &["random", &expected]),]
    );
}

#[test]
fn failing_restore_falls_back_to_a_random_pick() {
    let sandbox = Sandbox::new("wl-restorefail");
    sandbox.install_default_fakes();
    let image = wallpaper(&sandbox);
    state(&sandbox, image.to_str().unwrap());
    let expected = format!("{}/pic/wl", sandbox.home.display());
    let outcome = sandbox.run_env(BIN, &[], &[("FAKE_WL_RESTORE_EXIT", "1")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.wl_calls(),
        vec![
            call("wl", &["query"]),
            call("wl", &["restore"]),
            call("wl", &["random", &expected]),
        ]
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
fn failing_wl_random_is_fatal_under_set_e() {
    let sandbox = Sandbox::new("wl-randomfail");
    sandbox.install_default_fakes();
    sandbox.fake(
        "wl",
        "case \"$1\" in\n  query) exit 0 ;;\n  random) exit 9 ;;\nesac\nexit 0\n",
    );
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 9);
}

#[test]
fn state_without_outputs_falls_back() {
    let sandbox = Sandbox::new("wl-badstate");
    sandbox.install_default_fakes();
    let file = sandbox.home.join(".local/state/wl/state.json");
    sandbox.write(&file, b"{}");
    let outcome = sandbox.run(BIN, &[]);
    assert_eq!(outcome.code, 0);
    let expected = format!("{}/pic/wl", sandbox.home.display());
    assert_eq!(
        sandbox.wl_calls(),
        vec![call("wl", &["query"]), call("wl", &["random", &expected]),]
    );
}

