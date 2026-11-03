//! Hermetic tests for the `sc-live` port: the status report, the scene lookup,
//! the `exec` of the editor wrapper and its diagnostics.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_sc-live");

const PGREP: &str = "exit \"${FAKE_PGREP_CODE:-1}\"\n";
const PWLINK: &str = "printf '%s' \"${FAKE_PWLINK_OUT:-}\"\n";

const LINKED: &str = "SuperCollider:out_1\nSuperCollider:out_2\n";

fn editor_fake() -> String {
    format!(
        "#!{}\nline=\"v\"\nfor arg in \"$@\"; do line=\"$line\t$arg\"; done\n\
         printf '%s\\n' \"$line\" >> \"$FAKE_LOG\"\nprintf 'v-stdout\\n'\nexit \"${{FAKE_V_CODE:-0}}\"\n",
        std::env::var("LOCAL_BIN_AUDIO_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into())
    )
}

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("pgrep", PGREP);
    sandbox.fake("pw-link", PWLINK);
    let editor = sandbox.write_home(".local/bin/v", editor_fake().as_bytes());
    support::mode(&editor, 0o755);
    sandbox.write_home("notes/music/supercollider/live.scd", b"// scene\n");
    sandbox
}

#[test]
fn status_reports_a_running_engine() {
    let sandbox = fixture("status-up");
    let outcome = sandbox.run_env(
        &["status"],
        &[("FAKE_PGREP_CODE", "0"), ("FAKE_PWLINK_OUT", LINKED)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "=== SuperCollider engine ===\n\
         \u{20}\u{20}scsynth: running (port 57110)\n\
         \u{20}\u{20}sclang:  running (scnvim session)\n\
         === PipeWire links ===\n\
         \u{20}\u{20}SuperCollider:out_1/2 -> present (linked by supercollider-link)\n"
    );
    assert_eq!(
        sandbox.log_lines_for("pgrep"),
        vec!["pgrep\t-f\tscsynth -u 57110", "pgrep\t-f\tsclang-pwj"]
    );
}

#[test]
fn status_reports_an_idle_engine() {
    let sandbox = fixture("status-down");
    let outcome = sandbox.run(&["status"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "=== SuperCollider engine ===\n\
         \u{20}\u{20}scsynth: NOT running — start via <leader>sc + <leader>sb in live.scd\n\
         \u{20}\u{20}sclang:  not running\n\
         === PipeWire links ===\n\
         \u{20}\u{20}SuperCollider:out_1/2 -> NOT linked (engine off or link service down)\n"
    );
}

#[test]
fn opening_uses_the_default_scene() {
    let sandbox = fixture("open-default");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "v-stdout\n");
    let log = sandbox.log();
    assert!(
        log.contains(&format!(
            "v\t{}/notes/music/supercollider/live.scd\n",
            sandbox.home.display()
        )),
        "{log}"
    );
}

#[test]
fn an_argument_replaces_the_scene_path() {
    let sandbox = fixture("open-arg");
    let outcome = sandbox.run(&["other.scd"]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log().contains("v\tother.scd\n"));
}

#[test]
fn an_empty_argument_falls_back_to_the_scene() {
    let sandbox = fixture("open-empty");
    let outcome = sandbox.run(&[""]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox
        .log()
        .contains("/notes/music/supercollider/live.scd\n"));
}

#[test]
fn the_editor_exit_status_is_propagated() {
    let sandbox = fixture("editor-status");
    let outcome = sandbox.run_env(&[], &[("FAKE_V_CODE", "7")]);
    assert_eq!(outcome.code, 7);
}

#[test]
fn a_missing_scene_is_reported() {
    let sandbox = fixture("missing-scene");
    std::fs::remove_file(sandbox.home.join("notes/music/supercollider/live.scd"))
        .expect("remove scene");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "live scene not found: {}/notes/music/supercollider/live.scd\n",
            sandbox.home.display()
        )
    );
    assert_eq!(sandbox.log(), "");
}

#[test]
fn a_missing_editor_reports_127() {
    let sandbox = fixture("no-editor");
    std::fs::remove_file(sandbox.home.join(".local/bin/v")).expect("remove editor");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 127);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "{}: line 40: {}/.local/bin/v: No such file or directory\n",
            sandbox.program().display(),
            sandbox.home.display()
        )
    );
}

#[test]
fn a_non_executable_editor_reports_126() {
    let sandbox = fixture("not-executable");
    let editor = sandbox.home.join(".local/bin/v");
    support::mode(&editor, 0o644);
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 126);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "{}: line 40: {}/.local/bin/v: Permission denied\n",
            sandbox.program().display(),
            sandbox.home.display()
        )
    );
}

#[test]
fn status_without_the_probes_degrades_to_idle() {
    let sandbox = fixture("no-probes");
    sandbox.remove_fake("pgrep");
    sandbox.remove_fake("pw-link");
    let outcome = sandbox.run(&["status"]);
    assert_eq!(outcome.code, 0);
    let stdout = text(&outcome.stdout);
    assert!(stdout.contains("scsynth: NOT running"));
    assert!(stdout.contains("SuperCollider:out_1/2 -> NOT linked"));
}
