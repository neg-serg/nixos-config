//! End-to-end tests for `pleamar-rig`: the copy, the autostart, saying to the
//! rig, sync after an edit, and stop taking the copy away.

mod support;

use std::fs;
use std::os::unix::net::UnixListener;

use support::{stderr, stdout, Case};

/// The pleamar the rig talks through: it records the socket directory it was
/// handed, which is what `--say` needs to find a scene in another session.
const SAY_PLEAMAR: &str = r#"#!/bin/sh
printf '%s\n' "argv: $*" >> "$FAKE_LOG"
printf 'sockets: %s\n' "${PLEAMAR_SOCKETS:-}" >> "$FAKE_STATE/say.env"
echo "fake describe: ok"
"#;

/// A headless compositor that stays up (the fixture `pleamar-wm` exits at once
/// because its `sleep` is a fake), recording what the rig handed it.
const LONG_WM: &str = r#"#!/bin/sh
line='pleamar-wm'
for a in "$@"; do line="$line [$a]"; done
printf '%s\n' "$line" >> "$FAKE_LOG"
env | sort > "$FAKE_STATE/wm.env"
cat "$PLEAMAR_WM_AUTOSTART" > "$FAKE_STATE/wm.autostart"
perl -e 'sleep 30'
"#;

fn rig_case(label: &str) -> Case {
    let case = Case::rig(label);
    case.fake("pleamar-wm", LONG_WM);
    case.fake("pleamar", SAY_PLEAMAR);
    case
}

fn root(case: &Case) -> String {
    case.dir.join("rig").display().to_string()
}

/// The fake compositor writes its record a moment after `start` returns.
fn wait_for(path: &std::path::Path) {
    for _ in 0..300 {
        if let Ok(metadata) = fs::metadata(path) {
            if metadata.len() > 0 {
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    panic!("{} was not written", path.display());
}

#[test]
fn starts_a_copy_with_its_own_environment_and_stops_it() {
    let case = rig_case("start");
    let rig = root(&case);
    let output = case.run_with(
        &["start", "--scene", "bar", "--seconds", "30"],
        &[("RIG", rig.as_str())],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(out.contains("rig: the rig is up"), "{out}");
    assert!(out.contains("scene 'bar'"), "{out}");

    let copy = case.dir.join("rig/conf/pleamar/shells/bar/bar.plm");
    assert!(copy.is_file(), "the scene was copied");

    let autostart = fs::read_to_string(case.dir.join("rig/autostart")).expect("autostart");
    assert!(autostart.contains("--scene"), "{autostart}");
    assert!(autostart.contains("--no-hud"), "{autostart}");
    assert!(
        autostart.contains("conf/pleamar/shells/bar/bar.plm"),
        "{autostart}"
    );

    let pid = fs::read_to_string(case.dir.join("rig/pid")).expect("pid file");
    assert!(!pid.trim().is_empty());

    // Its own HOME and XDG folders reach the compositor, and the live display
    // does not.
    wait_for(&case.state.join("wm.env"));
    let env = fs::read_to_string(case.state.join("wm.env")).expect("wm env");
    assert!(
        env.contains(&format!("HOME={}/rig/home", case.dir.display())),
        "{env}"
    );
    assert!(
        env.contains(&format!("XDG_CONFIG_HOME={}/rig/conf", case.dir.display())),
        "{env}"
    );
    assert!(!env.contains("WAYLAND_DISPLAY="), "{env}");

    // The rig sees the copy, not the project.
    wait_for(&case.state.join("wm.autostart"));
    let seen = fs::read_to_string(case.state.join("wm.autostart")).expect("autostart seen");
    assert!(seen.contains("/rig/conf/pleamar"), "{seen}");

    // The compositor names its session, so the rig finds the scene's socket
    // directory instead of deriving it (`PLEAMAR_SOCKETS`).
    let socket_dir = case.dir.join("rig/run/pleamar-test");
    fs::create_dir_all(&socket_dir).expect("the rig's runtime directory");
    let _socket = UnixListener::bind(socket_dir.join("bar.sock")).expect("a scene socket");

    // Talking to it goes through the rig's socket.
    let output = case.run_with(&["say", "bar", "describe"], &[("RIG", rig.as_str())]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let calls = case.calls().join("\n");
    assert!(calls.contains("argv: --say bar describe"), "{calls}");
    wait_for(&case.state.join("say.env"));
    let said = fs::read_to_string(case.state.join("say.env")).expect("the say record");
    assert!(
        said.contains(&format!("sockets: {}", socket_dir.display())),
        "{said}"
    );

    // An edit comes back with `sync`.
    fs::remove_file(&copy).expect("remove the copied scene");
    let output = case.run_with(&["sync"], &[("RIG", rig.as_str())]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(copy.is_file(), "sync copied the tree again");

    let output = case.run_with(&["stop"], &[("RIG", rig.as_str())]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(!case.dir.join("rig").exists(), "stop removed the copy");
}

#[test]
fn says_that_there_is_no_rig() {
    let case = rig_case("no-rig");
    let rig = root(&case);
    for command in ["sync", "say"] {
        let mut args = vec![command];
        if command == "say" {
            args.extend(["bar", "describe"]);
        }
        let output = case.run_with(&args, &[("RIG", rig.as_str())]);
        assert_eq!(
            output.status.code(),
            Some(1),
            "{command}: {}",
            stdout(&output)
        );
        assert!(
            stderr(&output).contains("the rig is not running"),
            "{command}: {}",
            stderr(&output)
        );
    }
}

#[test]
fn refuses_a_scene_the_tree_does_not_have() {
    let case = rig_case("no-scene");
    let rig = root(&case);
    let output = case.run_with(&["start", "--scene", "tests"], &[("RIG", rig.as_str())]);
    assert_eq!(output.status.code(), Some(2), "stderr: {}", stderr(&output));
    assert!(
        stderr(&output).contains("no scene 'tests'"),
        "{}",
        stderr(&output)
    );
    assert!(!case.dir.join("rig/pid").exists());
}
