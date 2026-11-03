//! Hermetic tests for the `synth` port: name normalisation, the run-or-raise
//! decision (`pgrep` + `hyprctl` JSON), the start argv and the diagnostics.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_synth");

const PGREP: &str = "exit \"${FAKE_PGREP_CODE:-1}\"\n";
const SYSTEMCTL: &str = "exit \"${FAKE_SYSTEMCTL_CODE:-0}\"\n";
const NOHUP: &str = "exit 0\n";
const HYPRCTL: &str = r#"case "$1" in
  clients) printf '%s' "${FAKE_HYPR_JSON:-}" ;;
  dispatch) exit "${FAKE_HYPR_DISPATCH_CODE:-0}" ;;
esac
"#;

const SURGE_WINDOW: &str =
    "[{\"address\":\"0xaaa\",\"class\":\"Surge XT\",\"title\":\"Surge XT - patch\"}]";
const RENOISE_WINDOW: &str =
    "[{\"address\":\"0xbbb\",\"class\":\"Renoise\",\"title\":\"Renoise 3.5.4\"}]";
const OTHER_WINDOW: &str =
    "[{\"address\":\"0xccc\",\"class\":\"Firefox\",\"title\":\"Mozilla Firefox\"}]";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("pgrep", PGREP);
    sandbox.fake("systemctl", SYSTEMCTL);
    sandbox.fake("nohup", NOHUP);
    sandbox.fake("hyprctl", HYPRCTL);
    sandbox
}

#[test]
fn a_missing_name_is_a_parameter_error() {
    let sandbox = fixture("no-name");
    for args in [vec![], vec![""]] {
        let outcome = sandbox.run(&args);
        assert_eq!(outcome.code, 1);
        assert_eq!(outcome.stdout, b"");
        assert_eq!(
            text(&outcome.stderr),
            format!(
                "{}: line 13: 1: usage: synth <name>\n",
                sandbox.program().display()
            )
        );
    }
    assert_eq!(sandbox.log(), "");
}

#[test]
fn a_running_surge_window_is_raised() {
    let sandbox = fixture("surge-raised");
    let outcome = sandbox.run_env(
        &["Surge_XT"],
        &[("FAKE_PGREP_CODE", "0"), ("FAKE_HYPR_JSON", SURGE_WINDOW)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "synth: Surge XT raised\n");
    assert_eq!(
        sandbox.log_lines_for("pgrep"),
        vec!["pgrep\t-f\t/bin/Surge XT"]
    );
    assert_eq!(
        sandbox.log_lines_for("hyprctl"),
        vec![
            "hyprctl\tclients\t-j",
            "hyprctl\tdispatch\tfocuswindow\taddress:0xaaa"
        ]
    );
}

#[test]
fn a_running_surge_without_a_matching_window_is_left_alone() {
    let sandbox = fixture("surge-nomatch");
    let outcome = sandbox.run_env(
        &["Surge_XT"],
        &[("FAKE_PGREP_CODE", "0"), ("FAKE_HYPR_JSON", OTHER_WINDOW)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "synth: Surge XT already running\n");
    assert_eq!(
        sandbox.log_lines_for("hyprctl"),
        vec!["hyprctl\tclients\t-j"]
    );
}

#[test]
fn a_stopped_surge_is_started_through_nohup() {
    let sandbox = fixture("surge-start");
    let outcome = sandbox.run(&["Surge_XT"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "synth: starting Surge XT standalone ...\nsynth: Surge XT started\n"
    );
    let log = sandbox.wait_log("nohup");
    assert!(log.contains("nohup\t/run/current-system/sw/bin/Surge XT\n"));
    assert!(!log.contains("hyprctl\t"));
}

#[test]
fn surge_aliases_map_to_the_same_route() {
    for name in ["SurgeXT", "surge", "vst3:Surge_XT"] {
        let sandbox = fixture("alias");
        let outcome = sandbox.run(&[name]);
        assert_eq!(outcome.code, 0, "{name}");
        assert!(text(&outcome.stdout).contains("synth: Surge XT started\n"));
    }
}

#[test]
fn vital_uses_the_user_service() {
    let sandbox = fixture("vital-start");
    let outcome = sandbox.run(&["vital"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "synth: starting Vital (vital-standalone) ...\nsynth: Vital started\n"
    );
    assert_eq!(
        sandbox.log_lines_for("systemctl"),
        vec!["systemctl\t--user\tstart\tvital-standalone"]
    );
}

#[test]
fn a_running_vital_is_reported() {
    let sandbox = fixture("vital-running");
    let outcome = sandbox.run_env(&["Vital"], &[("FAKE_PGREP_CODE", "0")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "synth: Vital already running\n");
    assert!(sandbox.log_lines_for("systemctl").is_empty());
}

#[test]
fn a_failing_vital_service_stops_the_script() {
    let sandbox = fixture("vital-fail");
    let outcome = sandbox.run_env(&["Vital"], &[("FAKE_SYSTEMCTL_CODE", "5")]);
    assert_eq!(outcome.code, 5);
    assert_eq!(
        text(&outcome.stdout),
        "synth: starting Vital (vital-standalone) ...\n"
    );
}

#[test]
fn other_names_go_through_renoise() {
    let sandbox = fixture("renoise-start");
    let outcome = sandbox.run(&["LegendHZ"]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "synth: starting Renoise (LegendHZ via yabridge as regular VST3) ...\n\
         synth: Renoise started — add LegendHZ on a track FX chain (VST3)\n"
    );
    assert!(sandbox
        .wait_log("nohup\trenoise")
        .contains("nohup\trenoise\n"));
}

#[test]
fn a_running_renoise_is_raised_for_the_original_name() {
    let sandbox = fixture("renoise-raised");
    let outcome = sandbox.run_env(
        &["vst3:Legend  HZ"],
        &[("FAKE_PGREP_CODE", "0"), ("FAKE_HYPR_JSON", RENOISE_WINDOW)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stdout),
        "synth: Renoise raised (vst3:Legend  HZ as VST)\n"
    );
    assert_eq!(sandbox.log_lines_for("pgrep"), vec!["pgrep\t-f\trenoise"]);
    assert_eq!(
        sandbox.log_lines_for("hyprctl"),
        vec![
            "hyprctl\tclients\t-j",
            "hyprctl\tdispatch\tfocuswindow\taddress:0xbbb"
        ]
    );
}

#[test]
fn malformed_window_json_degrades_to_already_running() {
    let sandbox = fixture("bad-json");
    let outcome = sandbox.run_env(
        &["Surge_XT"],
        &[("FAKE_PGREP_CODE", "0"), ("FAKE_HYPR_JSON", "{not json")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "synth: Surge XT already running\n");
}

#[test]
fn a_missing_hyprctl_never_raises() {
    let sandbox = fixture("no-hyprctl");
    sandbox.remove_fake("hyprctl");
    let outcome = sandbox.run_env(&["Surge_XT"], &[("FAKE_PGREP_CODE", "0")]);
    assert_eq!(outcome.code, 0);
    assert_eq!(text(&outcome.stdout), "synth: Surge XT already running\n");
}
