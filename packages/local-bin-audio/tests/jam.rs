//! Hermetic tests for the `jam` port: the start/stop/status flows, the
//! `systemctl`/`sleep`/`sleep 2` argv, the background scene spawn and the
//! `set -e` behaviour.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_jam");

const PWLINK: &str = r#"case "$1" in
  -o) if [ -f "$HOME/sc.state" ]; then printf 'SuperCollider:out_1\nSuperCollider:out_2\n'; fi ;;
esac
"#;
const ACONNECT: &str = "printf '%s' \"${FAKE_ACONNECT:-}\"\n";
const PGREP: &str = "[ -f \"$HOME/vital.state\" ] && exit 0 || exit 1\n";
const SYSTEMCTL: &str = r#"case "$*" in
  *"start vital-standalone"*) : > "$HOME/vital.state" ;;
  *"stop vital-standalone"*) rm -f "$HOME/vital.state" ;;
esac
exit "${FAKE_SYSTEMCTL_CODE:-0}"
"#;
const SLEEP: &str = "exit 0\n";
const MIDI_BRIDGE: &str = "exit \"${FAKE_BRIDGE_CODE:-0}\"\n";

fn helper_fake(name: &str, body: &str) -> String {
    format!(
        "#!{}\nline=\"{name}\"\nfor arg in \"$@\"; do line=\"$line\t$arg\"; done\n\
         printf '%s\\n' \"$line\" >> \"$FAKE_LOG\"\n{body}",
        std::env::var("LOCAL_BIN_AUDIO_TEST_SHELL").unwrap_or_else(|_| "/bin/sh".into())
    )
}

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("pw-link", PWLINK);
    sandbox.fake("aconnect", ACONNECT);
    sandbox.fake("pgrep", PGREP);
    sandbox.fake("systemctl", SYSTEMCTL);
    sandbox.fake("sleep", SLEEP);
    let scene = sandbox.write_home(
        ".local/bin/sc-live",
        helper_fake("sc-live", ": > \"$HOME/sc.state\"\n").as_bytes(),
    );
    support::mode(&scene, 0o755);
    let bridge = sandbox.write_home(
        ".local/bin/midi-bridge",
        helper_fake("midi-bridge", MIDI_BRIDGE).as_bytes(),
    );
    support::mode(&bridge, 0o755);
    sandbox
}

fn up(sandbox: &Sandbox) {
    std::fs::write(sandbox.home.join("vital.state"), b"").expect("vital state");
    std::fs::write(sandbox.home.join("sc.state"), b"").expect("scene state");
}

#[test]
fn a_cold_start_brings_vital_and_the_scene_up() {
    let sandbox = fixture("cold");
    let outcome = sandbox.run(&["start"]);
    assert_eq!(outcome.code, 0, "{}", text(&outcome.stderr));
    assert_eq!(
        text(&outcome.stdout),
        "▶ Starting Vital...\n\
         ✓ Vital is ready\n\
         ▶ Opening the SuperCollider live scene (scnvim; s.boot inside)...\n\
         \u{20}\u{20}→ in nvim press <leader>sc (start sclang) and <leader>sb (boot + patterns)\n\
         \u{20}\u{20}(the engine comes up once s.boot runs in live.scd)\n\
         ✓ MIDI: SuperCollider → Midi Through → Vital\n\
         \n\
         Done. Patterns live in live.scd (nvim):  Pbind / Ndef / SynthDef — send <leader>sb\n"
    );
    let log = sandbox.wait_log("sc-live");
    assert!(log.contains(&format!("systemctl\t--user\tstart\tvital-standalone")));
    assert!(log.contains("sleep\t2"));
    assert!(log.contains("sc-live"));
    assert_eq!(sandbox.log_lines_for("midi-bridge"), vec!["midi-bridge"]);
}

#[test]
fn an_already_running_session_skips_the_starts() {
    let sandbox = fixture("warm");
    up(&sandbox);
    let outcome = sandbox.run(&["start"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "✓ Vital is already running\n\
         ✓ The SC engine is already running (scsynth on the bus)\n\
         ✓ MIDI: SuperCollider → Midi Through → Vital\n\
         \n\
         Done. Patterns live in live.scd (nvim):  Pbind / Ndef / SynthDef — send <leader>sb\n"
    );
    assert!(!sandbox.log().contains("systemctl\t"));
    assert!(!sandbox.log().contains("sleep\t2"));
}

#[test]
fn status_reports_all_three_components() {
    let sandbox = fixture("status");
    up(&sandbox);
    let outcome = sandbox.run_env(
        &["status"],
        &[(
            "FAKE_ACONNECT",
            "client 14: 'Midi Through'\n\tConnecting To: 14:0\n",
        )],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "=== Vital ===\n  running\n\
         === SC engine ===\n  scsynth is running (SuperCollider:out_1/2 visible)\n\
         === MIDI ===\n  the bridge is connected\n"
    );
}

#[test]
fn status_reports_an_idle_session() {
    let sandbox = fixture("idle");
    let outcome = sandbox.run(&["status"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "=== Vital ===\n  not running (jam or systemctl --user start vital-standalone)\n\
         === SC engine ===\n  not running (jam → live.scd → <leader>sc, <leader>sb)\n\
         === MIDI ===\n  the bridge is NOT connected (jam)\n"
    );
}

#[test]
fn stop_uses_the_user_service() {
    let sandbox = fixture("stop");
    up(&sandbox);
    let outcome = sandbox.run(&["stop"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "▶ Stopping Vital...\n✓ Stopped (close the SC session in nvim: <leader>sx)\n"
    );
    assert_eq!(
        sandbox.log_lines_for("systemctl"),
        vec!["systemctl\t--user\tstop\tvital-standalone"]
    );
}

#[test]
fn an_unknown_command_is_a_usage_error() {
    let sandbox = fixture("usage");
    let outcome = sandbox.run(&["frobnicate"]);
    assert_eq!(outcome.code, 2);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(text(&outcome.stderr), "usage: jam [start|stop|status]\n");
}

#[test]
fn a_failing_bridge_start_only_warns() {
    let sandbox = fixture("bridge");
    up(&sandbox);
    let outcome = sandbox.run_env(&["start"], &[("FAKE_BRIDGE_CODE", "1")]);
    assert_eq!(outcome.code, 0);
    assert!(text(&outcome.stdout)
        .contains("⚠ The MIDI bridge did not come up — check that the engine is running\n"));
}

#[test]
fn a_failing_systemctl_start_stops_the_script() {
    let sandbox = fixture("systemctl-fail");
    let outcome = sandbox.run_env(&["start"], &[("FAKE_SYSTEMCTL_CODE", "5")]);
    assert_eq!(outcome.code, 5);
    assert!(text(&outcome.stdout).starts_with("▶ Starting Vital...\n"));
}

#[test]
fn a_missing_sleep_aborts_after_the_scene_spawn() {
    let sandbox = fixture("no-sleep");
    sandbox.remove_fake("sleep");
    let outcome = sandbox.run(&["start"]);
    assert_eq!(outcome.code, 127);
    let stderr = text(&outcome.stderr);
    assert!(
        stderr.contains(&format!(
            "{}: line 46: sleep: command not found\n",
            sandbox.program().display()
        )),
        "{stderr}"
    );
}

#[test]
fn a_missing_scene_helper_reports_the_spawn_but_continues() {
    let sandbox = fixture("no-scene");
    std::fs::remove_file(sandbox.home.join(".local/bin/sc-live")).expect("remove scene helper");
    let outcome = sandbox.run(&["start"]);
    assert_eq!(outcome.code, 0);
    let stderr = text(&outcome.stderr);
    assert!(
        stderr.contains(&format!(
            "{}: line 45: {}/.local/bin/sc-live: No such file or directory\n",
            sandbox.program().display(),
            sandbox.home.display()
        )),
        "{stderr}"
    );
    assert!(!sandbox.log().contains("sc-live"));
    assert!(sandbox.log().contains("sleep\t2"));
}
