//! Hermetic tests for the `hypr-resize-proportional` port.
//!
//! `bc` is the original's numeric evaluator and stays a subprocess, so the
//! tests drive it with a fake that records the expressions it receives and
//! answers from a small table.

mod support;

use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_hypr-resize-proportional");

#[test]
fn missing_argument_reports_the_parameter_error() {
    let sandbox = Sandbox::new("hrp-noarg");
    sandbox.install_default_fakes();
    for arguments in [vec![], vec![""]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 1);
        assert_eq!(
            outcome.stderr,
            format!("{BIN}: line 7: 1: Usage: hypr-resize-proportional [+/-]PERCENT\n")
                .into_bytes()
        );
        assert!(sandbox.calls("hyprctl").is_empty());
    }
}

#[test]
fn tiled_window_is_skipped_silently() {
    let sandbox = Sandbox::new("hrp-tiled");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[(
            "FAKE_ACTIVEWINDOW",
            r#"{"floating":false,"size":[800,600]}"#,
        )],
    );
    assert_eq!(outcome.code, 0);
    assert!(sandbox.calls("bc").is_empty());
    assert!(sandbox.dispatch().is_empty());
}

#[test]
fn grow_uses_bc_and_dispatches_the_delta() {
    let sandbox = Sandbox::new("hrp-grow");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.bc_expressions(),
        vec!["1.0 + +10 / 100.0", "800 * 1.1 / 1", "600 * 1.1 / 1"]
    );
    assert_eq!(
        sandbox.dispatch(),
        vec![vec![
            b"dispatch".to_vec(),
            b"resizeactive".to_vec(),
            b"80 60".to_vec()
        ]]
    );
}

#[test]
fn shrink_and_minimum_clamp() {
    let sandbox = Sandbox::new("hrp-clamp");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["-99"],
        &[
            ("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#),
            // The fake answers 0.1 for the factor and 80/60 for the products.
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.bc_expressions(),
        vec!["1.0 + -99 / 100.0", "800 * 0.1 / 1", "600 * 0.1 / 1"]
    );
    assert_eq!(
        sandbox.dispatch(),
        vec![vec![
            b"dispatch".to_vec(),
            b"resizeactive".to_vec(),
            b"-600 -450".to_vec()
        ]],
        "200x150 minimum"
    );
}

#[test]
fn monitor_clamp_uses_the_first_output_and_its_scale() {
    let sandbox = Sandbox::new("hrp-monitor");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[
            ("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#),
            ("FAKE_MONITORS", r#"[{"width":100,"height":90,"scale":1}]"#),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.dispatch()[0][2],
        b"-700 -510".to_vec(),
        "clamped to 100x90"
    );

    sandbox.reset();
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[
            ("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#),
            (
                "FAKE_MONITORS",
                r#"[{"width":2560,"height":1440,"scale":2}]"#,
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.dispatch()[0][2],
        b"80 60".to_vec(),
        "1280x720 logical monitor, no clamp"
    );
}

#[test]
fn missing_bc_keeps_the_original_dispatch() {
    let sandbox = Sandbox::new("hrp-nobc");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("bc")).expect("drop fake bc");
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#)],
    );
    assert_eq!(outcome.code, 0);
    let stderr = str_of(&outcome.stderr);
    for line in [20, 21, 22] {
        assert!(
            stderr.contains(&format!("{BIN}: line {line}: bc: command not found\n")),
            "line {line}: {stderr}"
        );
    }
    assert_eq!(
        sandbox.dispatch()[0][2],
        b"-600 -450".to_vec(),
        "the empty expansions clamp to 200x150"
    );
}

#[test]
fn fractional_bc_output_hits_bash_arithmetic_diagnostics() {
    let sandbox = Sandbox::new("hrp-float");
    sandbox.install_default_fakes();
    sandbox.fake(
        "bc",
        r#"expression=$(cat)
case "$expression" in
  "1.0 + +10 / 100.0") printf '%s\n' "1.100000" ;;
  "800 * 1.100000 / 1") printf '%s\n' "880.000000" ;;
  "600 * 1.100000 / 1") printf '%s\n' "660.000000" ;;
  *) printf '0\n' ;;
esac
exit 0
"#,
    );
    let outcome = sandbox.run_env(
        BIN,
        &["+10"],
        &[("FAKE_ACTIVEWINDOW", r#"{"floating":true,"size":[800,600]}"#)],
    );
    assert_eq!(outcome.code, 0);
    let stderr = str_of(&outcome.stderr);
    assert!(
        stderr.contains(
            "line 29: ((: 880.000000: arithmetic syntax error: invalid arithmetic operator (error token is \".000000\")"
        ),
        "{stderr}"
    );
    assert!(
        stderr.contains(
            "line 35: 880.000000: arithmetic syntax error: invalid arithmetic operator (error token is \".000000\")"
        ),
        "{stderr}"
    );
    assert_eq!(
        sandbox.dispatch()[0][2],
        b" ".to_vec(),
        "the failed assignment leaves dw/dh empty"
    );
}

#[test]
fn hyprctl_failure_exits_1() {
    let sandbox = Sandbox::new("hrp-hyprfail");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["+10"], &[("FAKE_HYPRCTL_AW_EXIT", "1")]);
    assert_eq!(outcome.code, 1);
    assert!(sandbox.dispatch().is_empty());
}

#[test]
fn invalid_window_json_is_not_floating() {
    let sandbox = Sandbox::new("hrp-badjson");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &["+10"], &[("FAKE_ACTIVEWINDOW", "not json")]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.dispatch().is_empty());
}
