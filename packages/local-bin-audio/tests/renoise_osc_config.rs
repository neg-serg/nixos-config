//! Hermetic tests for the `renoise-osc-config` port: the Python heredoc rewrite
//! (tags, newline normalisation), the backup, the running-renoise guard and the
//! environment default.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_renoise-osc-config");

const PGREP: &str = "exit \"${FAKE_PGREP_CODE:-1}\"\n";
const CP: &str = "exit \"${FAKE_CP_CODE:-0}\"\n";

const CFG: &str = ".config/Renoise/V3.5.4/Config.xml";
const BAK: &str = ".config/Renoise/V3.5.4/Config.xml.renoise-osc.bak";

const DISABLED: &str = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<RenoiseConfig>\n  <OscServerEnabled>false</OscServerEnabled>\n  <OscServerProtocol>Tcp</OscServerProtocol>\n  <OscServerPort>9000</OscServerPort>\n</RenoiseConfig>\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("pgrep", PGREP);
    sandbox.fake("cp", CP);
    sandbox
}

fn cfg_path(sandbox: &Sandbox) -> String {
    format!("{}/{}", sandbox.home.display(), CFG)
}

#[test]
fn a_disabled_config_is_enabled_and_pinned_to_9002() {
    let sandbox = fixture("disabled");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0, "{}", text(&outcome.stderr));
    assert_eq!(
        text(&outcome.stderr),
        "note: OSC server is disabled in Config.xml — enabling it\n"
    );
    assert_eq!(
        text(&outcome.stdout),
        format!(
            "Config.xml: OSC enabled, protocol Udp, port 9002\nbackup kept at: {}/{}\n",
            sandbox.home.display(),
            BAK
        )
    );
    let rewritten = text(&sandbox.read_home(CFG));
    assert!(rewritten.contains("<OscServerEnabled>true</OscServerEnabled>"));
    assert!(rewritten.contains("<OscServerProtocol>Udp</OscServerProtocol>"));
    assert!(rewritten.contains("<OscServerPort>9002</OscServerPort>"));
    assert!(!rewritten.contains("false"));
    assert!(!rewritten.contains("Tcp"));
    assert_eq!(
        sandbox.log_lines_for("cp"),
        vec![format!(
            "cp\t{}\t{}/{}",
            cfg_path(&sandbox),
            sandbox.home.display(),
            BAK
        )]
    );
}

#[test]
fn an_enabled_config_produces_no_note() {
    let sandbox = fixture("enabled");
    let enabled = DISABLED
        .replace(
            "<OscServerEnabled>false</OscServerEnabled>",
            "<OscServerEnabled>true</OscServerEnabled>",
        )
        .replace(
            "<OscServerProtocol>Tcp</OscServerProtocol>",
            "<OscServerProtocol>Udp</OscServerProtocol>",
        );
    sandbox.write_home(CFG, enabled.as_bytes());
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stderr, b"");
    assert!(text(&sandbox.read_home(CFG)).contains("<OscServerPort>9002</OscServerPort>"));
}

#[test]
fn the_port_environment_variable_overrides_the_default() {
    let sandbox = fixture("port-env");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run_env(&[], &[("RENOISE_OSC_PORT", "9123")]);
    assert_eq!(outcome.code, 0);
    assert!(text(&outcome.stdout).contains("port 9123\n"));
    assert!(text(&sandbox.read_home(CFG)).contains("<OscServerPort>9123</OscServerPort>"));
}

#[test]
fn an_empty_port_uses_the_default() {
    let sandbox = fixture("port-empty");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run_env(&[], &[("RENOISE_OSC_PORT", "")]);
    assert_eq!(outcome.code, 0);
    assert!(text(&sandbox.read_home(CFG)).contains("<OscServerPort>9002</OscServerPort>"));
}

#[test]
fn a_running_renoise_blocks_the_rewrite() {
    let sandbox = fixture("running");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run_env(&[], &[("FAKE_PGREP_CODE", "0")]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        text(&outcome.stderr),
        "renoise is running — close it first, then re-run\n"
    );
    assert_eq!(sandbox.read_home(CFG), DISABLED.as_bytes());
    assert!(sandbox.log_lines_for("cp").is_empty());
}

#[test]
fn a_missing_config_is_reported() {
    let sandbox = fixture("missing");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        text(&outcome.stderr),
        format!("Config.xml not found: {}/{}\n", sandbox.home.display(), CFG)
    );
}

#[test]
fn an_existing_backup_is_not_overwritten() {
    let sandbox = fixture("backup");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    sandbox.write_home(BAK, b"old backup\n");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert!(sandbox.log_lines_for("cp").is_empty());
    assert_eq!(sandbox.read_home(BAK), b"old backup\n");
}

#[test]
fn crlf_input_is_normalised_like_pythons_text_mode() {
    let sandbox = fixture("crlf");
    let crlf = DISABLED.replace('\n', "\r\n");
    sandbox.write_home(CFG, crlf.as_bytes());
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let rewritten = text(&sandbox.read_home(CFG));
    assert!(!rewritten.contains('\r'));
    assert_eq!(rewritten.matches('\n').count(), 6);
}

#[test]
fn tags_split_across_lines_are_not_matched() {
    let sandbox = fixture("split");
    sandbox.write_home(
        CFG,
        b"<RenoiseConfig>\n<OscServerEnabled>\n</OscServerEnabled>\n<OscServerPort>9000</OscServerPort>\n</RenoiseConfig>\n",
    );
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let rewritten = text(&sandbox.read_home(CFG));
    assert!(rewritten.contains("<OscServerEnabled>\n</OscServerEnabled>"));
    assert!(rewritten.contains("<OscServerPort>9002</OscServerPort>"));
}

#[test]
fn a_later_same_line_tag_is_matched_after_a_split_one() {
    let sandbox = fixture("second-tag");
    sandbox.write_home(
        CFG,
        b"<RenoiseConfig>\n<OscServerEnabled>\n</OscServerEnabled>\n<OscServerEnabled>false</OscServerEnabled>\n</RenoiseConfig>\n",
    );
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let rewritten = text(&sandbox.read_home(CFG));
    assert!(rewritten.contains(
        "<OscServerEnabled>\n</OscServerEnabled>\n<OscServerEnabled>true</OscServerEnabled>"
    ));
    assert!(!rewritten.contains("<OscServerEnabled>false</OscServerEnabled>"));
}

#[test]
fn a_config_without_tags_is_left_as_is() {
    let sandbox = fixture("untagged");
    sandbox.write_home(
        CFG,
        b"<RenoiseConfig>\n  <Other>1</Other>\n</RenoiseConfig>\n",
    );
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.read_home(CFG),
        b"<RenoiseConfig>\n  <Other>1</Other>\n</RenoiseConfig>\n"
    );
}

#[test]
fn missing_pgrep_is_silent() {
    let sandbox = fixture("no-pgrep");
    sandbox.remove_fake("pgrep");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    assert_eq!(
        text(&outcome.stderr),
        "note: OSC server is disabled in Config.xml — enabling it\n"
    );
}

#[test]
fn a_failing_cp_aborts_before_the_rewrite() {
    let sandbox = fixture("cp-fail");
    sandbox.write_home(CFG, DISABLED.as_bytes());
    let outcome = sandbox.run_env(&[], &[("FAKE_CP_CODE", "6")]);
    assert_eq!(outcome.code, 6);
    assert_eq!(sandbox.read_home(CFG), DISABLED.as_bytes());
}
