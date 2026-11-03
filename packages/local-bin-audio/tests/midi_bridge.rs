//! Hermetic tests for the `midi-bridge` port: the awk-style `aconnect -l`
//! parsing, the exact call sequence and the connect diagnostics.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_midi-bridge");

const ACONNECT: &str = r#"case "$1" in
  -l) printf '%s' "${FAKE_ACONNECT_LIST:-}"; exit "${FAKE_ACONNECT_LIST_CODE:-0}" ;;
  *)
    if [ "${FAKE_ACONNECT_FAIL:-0}" = 1 ]; then
      printf 'cannot connect\n' >&2
      exit 1
    fi
    ;;
esac
"#;

const FULL: &str = "client 0: 'System' [type=kernel]\n    0 'Timer           '\n\
client 14: 'Midi Through' [type=kernel]\n    0 'Midi Through Port-0'\n\
client 128: 'SuperCollider' [type=user,pid=100]\n    0 'SuperCollider MIDI In'\n    1 'out0'\n\
client 129: 'Renoise' [type=user,pid=200]\n    0 'midi in'\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("aconnect", ACONNECT);
    sandbox
}

#[test]
fn both_targets_are_connected_with_the_resolved_ports() {
    let sandbox = fixture("full");
    let outcome = sandbox.run_env(&[], &[("FAKE_ACONNECT_LIST", FULL)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "midi-bridge: connected SC MIDI -> Renoise\n\
         midi-bridge: connected SC MIDI -> Vital (Midi Through)\n"
    );
    assert_eq!(outcome.stderr, b"");
    assert_eq!(
        sandbox.log_lines_for("aconnect"),
        vec![
            "aconnect\t-l",
            "aconnect\t-l",
            "aconnect\t-l",
            "aconnect\t-l",
            "aconnect\t128:1\t129:0",
            "aconnect\t-l",
            "aconnect\t-l",
            "aconnect\t-l",
            "aconnect\t128:1\t14:0",
        ]
    );
}

#[test]
fn a_missing_supercollider_client_is_fatal() {
    let sandbox = fixture("no-sc");
    let outcome = sandbox.run_env(
        &[],
        &[(
            "FAKE_ACONNECT_LIST",
            "client 129: 'Renoise' [type=user,pid=200]\n    0 'midi in'\n",
        )],
    );
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(
        text(&outcome.stderr),
        "midi-bridge: no SuperCollider MIDI client (engine not started?)\n"
    );
    assert_eq!(sandbox.log_lines_for("aconnect"), vec!["aconnect\t-l"]);
}

#[test]
fn a_missing_renoise_is_reported_and_skipped() {
    let sandbox = fixture("no-renoise");
    let listing = "client 14: 'Midi Through' [type=kernel]\n    0 'Midi Through Port-0'\n\
client 128: 'SuperCollider' [type=user,pid=100]\n    1 'out0'\n";
    let outcome = sandbox.run_env(&[], &[("FAKE_ACONNECT_LIST", listing)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "midi-bridge: Renoise not running — SC MIDI -> Renoise skipped\n\
         midi-bridge: connected SC MIDI -> Vital (Midi Through)\n"
    );
}

#[test]
fn missing_ports_are_reported_with_their_values() {
    let sandbox = fixture("no-out");
    let listing = "client 14: 'Midi Through' [type=kernel]\n    0 'Midi Through Port-0'\n\
client 128: 'SuperCollider' [type=user,pid=100]\n    0 'SuperCollider MIDI In'\n";
    let outcome = sandbox.run_env(&[], &[("FAKE_ACONNECT_LIST", listing)]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "midi-bridge: Renoise not running — SC MIDI -> Renoise skipped\n\
         midi-bridge: Vital (Midi Through) skipped (ports not found: SC out0=[], Vital (Midi Through) in=[0])\n"
    );
}

#[test]
fn a_failed_connection_prints_the_tool_error() {
    let sandbox = fixture("connect-fail");
    let outcome = sandbox.run_env(
        &[],
        &[("FAKE_ACONNECT_LIST", FULL), ("FAKE_ACONNECT_FAIL", "1")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stderr),
        "midi-bridge: failed to connect SC MIDI -> Renoise: cannot connect\n\
         midi-bridge: failed to connect SC MIDI -> Vital (Midi Through): cannot connect\n"
    );
}

#[test]
fn a_failing_listing_aborts_with_its_status() {
    let sandbox = fixture("list-fail");
    let outcome = sandbox.run_env(
        &[],
        &[
            ("FAKE_ACONNECT_LIST", FULL),
            ("FAKE_ACONNECT_LIST_CODE", "4"),
        ],
    );
    assert_eq!(outcome.code, 4);
    assert_eq!(outcome.stdout, b"");
}

#[test]
fn a_missing_aconnect_reports_the_bash_diagnostic() {
    let sandbox = fixture("no-aconnect");
    sandbox.remove_fake("aconnect");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 127);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "{}: line 8: aconnect: command not found\n",
            sandbox.program().display()
        )
    );
}
