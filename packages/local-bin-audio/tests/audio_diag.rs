//! Hermetic tests for the `audio-diag` port: the report layout, the routing and
//! volume checks, the RME mixer branch (when this host exposes the card), the
//! essential-tool exit code and the exact argv of every probe.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_audio-diag");

const DATE: &str = "printf '2026-11-03 12:00:00\\n'\n";
const PWLINK: &str = r#"case "$1" in
  -l) printf '%s' "${FAKE_PWLINK_LIST:-}" ;;
  -o) printf '%s' "${FAKE_PWLINK_OUT:-}" ;;
esac
"#;
const WPCTL: &str = r#"case "$1" in
  status) printf '%s' "${FAKE_WPCTL_STATUS:-}" ;;
  get-volume) printf '%s' "${FAKE_WPCTL_VOLUME:-}" ;;
esac
"#;
const AMIXER: &str = "printf '%s' \"${FAKE_AMIXER:-}\"\n";
const PGREP: &str = "exit \"${FAKE_PGREP_CODE:-1}\"\n";
const SYSTEMCTL: &str = "printf '%s' \"${FAKE_SYSTEMCTL:-}\"\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("date", DATE);
    sandbox.fake("pw-link", PWLINK);
    sandbox.fake("wpctl", WPCTL);
    sandbox.fake("amixer", AMIXER);
    sandbox.fake("pgrep", PGREP);
    sandbox.fake("systemctl", SYSTEMCTL);
    sandbox
}

fn healthy_links() -> &'static str {
    "playback.game-stereo:output_FL\n  |-> RME:playback_AUX2\n\
     playback.game-stereo:output_FR\n  |-> RME:playback_AUX3\n"
}

fn healthy_status() -> &'static str {
    "Audio\n ├─ Sinks:\n │  *   41. game-stereo    [Audio/Sink]\n\
     │      71. RME AIO Pro_24048964 Pro    [vol: 1.00]\n\
     ├─ Filters:\n │      40. playback.game-stereo    [Stream/Output/Audio]\n"
}

fn unity_mixer() -> String {
    let mut text = String::new();
    for channel in 1..=16 {
        text.push_str(&format!(
            "numid={channel},iface=MIXER,name='Chn'\n  ; type=INTEGER\n  : values=64\n"
        ));
    }
    text
}

fn env_unity() -> Vec<(&'static str, String)> {
    vec![
        ("FAKE_PWLINK_LIST", healthy_links().to_string()),
        ("FAKE_WPCTL_STATUS", healthy_status().to_string()),
        ("FAKE_WPCTL_VOLUME", "Volume: 1.00\n".to_string()),
        ("FAKE_AMIXER", unity_mixer()),
        ("FAKE_SYSTEMCTL", "PULSE_SINK=game-stereo\n".to_string()),
    ]
}

fn run_with(sandbox: &Sandbox, pairs: &[(&'static str, String)]) -> support::Outcome {
    let borrowed: Vec<(&str, &str)> = pairs
        .iter()
        .map(|(name, value)| (*name, value.as_str()))
        .collect();
    sandbox.run_env(&[], &borrowed)
}

#[test]
fn a_healthy_chain_reports_ok_and_exits_zero() {
    let sandbox = fixture("healthy");
    let outcome = run_with(&sandbox, &env_unity());
    let stdout = text(&outcome.stdout);
    assert_eq!(outcome.code, 0, "{stdout}{}", text(&outcome.stderr));
    assert!(stdout.starts_with("==== audio-diag (2026-11-03 12:00:00) ====\n"));
    assert!(stdout.contains("ok    default sink = game-stereo\n"));
    assert!(stdout
        .contains("ok    AES playback_AUX2 <- single source (playback.game-stereo loopback)\n"));
    assert!(stdout
        .contains("ok    AES playback_AUX3 <- single source (playback.game-stereo loopback)\n"));
    assert!(stdout.contains("ok    no direct app -> RME playback links\n"));
    assert!(stdout.contains("ok    volume game-stereo (id 41) = 1.00, not muted\n"));
    assert!(stdout.contains("ok    volume rme-pro (id 71) = 1.00, not muted\n"));
    assert!(stdout.contains("ok    volume loopback (id 40) = 1.00, not muted\n"));
    assert!(stdout.contains("ok    default sink volume = 1.00, not muted\n"));
    assert!(stdout.ends_with("==== audio-diag done: 0 FAIL(s) ====\n"));
}

#[test]
fn probe_argv_is_the_original_one() {
    let sandbox = fixture("argv");
    let outcome = run_with(&sandbox, &env_unity());
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.log_lines_for("date"), vec!["date\t+%F %T"]);
    assert_eq!(sandbox.log_lines_for("pw-link"), vec!["pw-link\t-l"]);
    // `wpctl status` runs once for the default-sink check and once per id
    // extraction; each volume probe runs get-volume twice.
    let statuses = sandbox
        .log_lines_for("wpctl")
        .iter()
        .filter(|line| line.as_str() == "wpctl\tstatus")
        .count();
    assert_eq!(statuses, 4);
    assert_eq!(
        sandbox
            .log_lines_for("wpctl")
            .iter()
            .filter(|line| line.as_str() == "wpctl\tget-volume\t41")
            .count(),
        2
    );
    assert_eq!(
        sandbox.log_lines_for("amixer"),
        vec![format!("amixer\t-c\t0\tcontents")]
    );
    assert_eq!(
        sandbox.log_lines_for("pgrep"),
        vec!["pgrep\t-af\trme-route-all|aes-dedup"]
    );
}

#[test]
fn bad_routing_and_muted_volumes_fail() {
    let sandbox = fixture("bad");
    let links = "playback.game-stereo:output_FL\n  |-> RME:playback_AUX2\n\
                 multimedia:output_FL\n  |-> RME:playback_AUX2\n\
                 firefox:output_FL\n  |-> RME:playback_AUX0\n";
    let mut env = env_unity();
    env.retain(|(name, _)| !matches!(*name, "FAKE_PWLINK_LIST" | "FAKE_WPCTL_VOLUME"));
    env.push(("FAKE_PWLINK_LIST", links.to_string()));
    env.push(("FAKE_WPCTL_VOLUME", "Volume: 0.50 [MUTED]\n".to_string()));
    let outcome = run_with(&sandbox, &env);
    let stdout = text(&outcome.stdout);
    assert_eq!(outcome.code, 1, "{stdout}");
    assert!(stdout.contains(
        "FAIL  AES playback_AUX2 has 2 source(s) (expected exactly 1 = playback.game-stereo:output_*)\n"
    ));
    assert!(stdout.contains("      src: multimedia:output_FL\n"));
    assert!(stdout.contains("FAIL  direct app -> RME playback links (double route)\n"));
    assert!(stdout.contains("      link: firefox:output_FL -> RME:playback_AUX0\n"));
    assert!(stdout
        .contains("FAIL  volume game-stereo (id 41) not at unity/muted: Volume: 0.50 [MUTED]\n"));
    assert!(stdout.contains("FAIL  default sink not at unity: Volume: 0.50 [MUTED]\n"));
    assert!(stdout.contains("FAIL(s) ====") && !stdout.contains("done: 0 FAIL(s)"));
}

#[test]
fn missing_essential_tools_warn_and_exit_two() {
    let sandbox = fixture("missing");
    sandbox.remove_fake("pw-link");
    sandbox.remove_fake("wpctl");
    sandbox.remove_fake("amixer");
    let outcome = sandbox.run(&[]);
    let stdout = text(&outcome.stdout);
    assert_eq!(outcome.code, 2);
    assert!(stdout.contains("WARN  tool 'pw-link' not found\n"));
    assert!(stdout.contains("WARN  tool 'wpctl' not found\n"));
    assert!(stdout.contains("WARN  tool 'amixer' not found\n"));
    assert!(stdout.contains("FAIL  default sink is not game-stereo\n"));
    assert!(stdout.ends_with("==== audio-diag done: 3 FAIL(s) ====\n"));
}

#[test]
fn the_mixer_branch_matches_the_detected_card() {
    let sandbox = fixture("mixer");
    let outcome = run_with(&sandbox, &env_unity());
    let stdout = text(&outcome.stdout);
    let host = std::fs::read_to_string("/proc/asound/cards").unwrap_or_default();
    let has_rme = host
        .lines()
        .any(|line| line.contains("HDSPe") || line.contains("RME AIO"));
    if has_rme {
        assert!(
            stdout.contains("ok    RME mixer Chn (16 controls) all = 64 (unity)\n"),
            "{stdout}"
        );
        assert_eq!(sandbox.log_lines_for("amixer").len(), 1);
    } else {
        assert!(
            stdout.contains("      RME HDSPe card not detected - skipping hardware mixer check\n")
        );
        assert!(sandbox.log_lines_for("amixer").is_empty());
    }
}

#[test]
fn a_bad_mixer_channel_fails_when_the_card_is_present() {
    let sandbox = fixture("mixer-bad");
    let mut mixer = String::new();
    for channel in 1..=16 {
        let value = if channel == 4 { 32 } else { 64 };
        mixer.push_str(&format!(
            "numid={channel},iface=MIXER,name='Chn'\n  ; type=INTEGER\n  : values={value}\n"
        ));
    }
    let mut env = env_unity();
    env.retain(|(name, _)| *name != "FAKE_AMIXER");
    env.push(("FAKE_AMIXER", mixer));
    let outcome = run_with(&sandbox, &env);
    let stdout = text(&outcome.stdout);
    let host = std::fs::read_to_string("/proc/asound/cards").unwrap_or_default();
    if host
        .lines()
        .any(|line| line.contains("HDSPe") || line.contains("RME AIO"))
    {
        assert!(
            stdout.contains("FAIL  RME mixer Chn: 1 of 16 not 64 (unity)\n"),
            "{stdout}"
        );
        assert_eq!(outcome.code, 1);
    }
}
