//! `validate_nodes` tests.
//!
//! Real loopback sockets are used for the TCP scan; the e2e probe drives a
//! scripted `curl` stub (the probe targets are fixed public URLs, so a real
//! HTTP client would need internet). `sing-box`/`setsid`/`pkill`/`sleep` are
//! stubs too: no real sing-box process is ever started.

mod common;

use common::{Stubs, TestDir};
use sing_box_proxy::output::Ui;
use sing_box_proxy::validate::{validate_nodes, ValidateOptions};
use std::fs;
use std::net::TcpListener;
use std::path::Path;

const CURL_STUB: &str = r#"mode=${FAKE_CURL_MODE:-ok}
case "$mode" in
  ok)
    case "$*" in
      *speed.cloudflare.com*) printf '250000' ;;
      *api.telegram.org*) printf '200' ;;
      *) printf '204' ;;
    esac
    ;;
  no-tg)
    case "$*" in
      *api.telegram.org*) printf '000'; exit 7 ;;
      *speed.cloudflare.com*) printf '250000' ;;
      *) printf '204' ;;
    esac
    ;;
  fail-speed)
    case "$*" in
      *speed.cloudflare.com*) printf '1000' ;;
      *) printf '204' ;;
    esac
    ;;
  fail-relay)
    printf '000'
    ;;
esac"#;

fn validate(
    text: &str,
    mode: &str,
    options: &ValidateOptions,
) -> (String, sing_box_proxy::validate::ValidateOutcome) {
    std::env::set_var("FAKE_CURL_MODE", mode);
    let mut buffer: Vec<u8> = Vec::new();
    let outcome = {
        let mut ui = Ui::new(&mut buffer, false, false);
        validate_nodes(text, options, &mut ui)
    };
    (String::from_utf8_lossy(&buffer).into_owned(), outcome)
}

fn open_port() -> (TcpListener, u16) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("bind loopback");
    let port = listener.local_addr().unwrap().port();
    (listener, port)
}

fn closed_port() -> u16 {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    port
}

fn options(tmp: &Path) -> ValidateOptions {
    ValidateOptions {
        tmp_dir: tmp.to_path_buf(),
        ..ValidateOptions::default()
    }
}

#[test]
fn validation_scenarios() {
    let stubs = Stubs::new("validate");
    stubs.add("sing-box", "exit 0");
    stubs.add("setsid", "exit 0");
    stubs.add("pkill", "exit 0");
    stubs.add("sleep", "exit 0");
    stubs.add("curl", CURL_STUB);
    std::env::set_var("PATH", stubs.only_path());

    let dir = TestDir::new("validate-tmp");

    // --- scan + e2e success, UDP auto-included, Telegram split -------------
    let (_listener, live_port) = open_port();
    let dead_port = closed_port();
    let nodes = format!(
        "vless://11111111-2222-3333-4444-555555555555@127.0.0.1:{live_port}?security=tls&type=ws#open\n\
         vless://11111111-2222-3333-4444-555555555556@127.0.0.1:{dead_port}?security=tls#closed\n\
         hysteria2://pw@127.0.0.1:23456?insecure=1#udp\n"
    );
    let mut opts = options(&dir.join("case1"));
    opts.e2e_cap = 150;
    let (report, outcome) = validate(&nodes, "ok", &opts);
    assert_eq!(outcome.exit_code, 0, "{report}");
    let mut working = outcome.working.clone();
    working.sort();
    let mut expected = vec![
        format!("vless://11111111-2222-3333-4444-555555555555@127.0.0.1:{live_port}?security=tls&type=ws#open"),
        "hysteria2://pw@127.0.0.1:23456?insecure=1#udp".to_string(),
    ];
    expected.sort();
    assert_eq!(working, expected, "{report}");
    assert!(report.contains(":: candidates: 3\n"), "{report}");
    assert!(
        report.contains(":: tcp-scan: 2 tcp, 1 udp (skipped)\n"),
        "{report}"
    );
    assert!(
        report.contains(":: tcp open: 2/3 (udp auto-included)\n"),
        "{report}"
    );
    assert!(
        report.contains(":: e2e: probing up to 2 open nodes (relay + throughput)...\n"),
        "{report}"
    );
    assert!(report.contains("✓ e2e working: 2/2\n"), "{report}");
    assert!(report.contains("✓ Telegram-capable: 2/2\n"), "{report}");
    let progress: Vec<&str> = report
        .lines()
        .filter(|line| line.starts_with("  e2e: "))
        .collect();
    assert_eq!(progress.len(), 2, "{report}");
    assert!(
        progress
            .last()
            .unwrap()
            .contains("2/2 probed, 2 relay+speed OK ("),
        "{report}"
    );
    let tg_file = fs::read_to_string(opts.tmp_dir.join("tg-working.txt")).unwrap();
    let mut tg_lines: Vec<&str> = tg_file.lines().collect();
    tg_lines.sort();
    let mut expected_tg: Vec<&str> = expected.iter().map(String::as_str).collect();
    expected_tg.sort();
    assert_eq!(tg_lines, expected_tg);
    // Throwaway probe configs are written with the node and the direct outbound.
    for offset in 0..2 {
        let path = opts.tmp_dir.join(format!("probe-{}.json", 11300 + offset));
        let config: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
        assert_eq!(config["route"]["final"], "node");
        assert_eq!(config["dns"]["strategy"], "ipv4_only");
        assert_eq!(config["outbounds"][1]["tag"], "direct");
    }

    // --- minimum working nodes warning ------------------------------------
    let mut opts = options(&dir.join("min"));
    opts.min_working = 3;
    let (report, outcome) = validate(
        "hysteria2://pw@127.0.0.1:8443?insecure=1#only\n",
        "ok",
        &opts,
    );
    assert_eq!(outcome.exit_code, 0);
    assert!(
        report.contains("! only 1 working nodes (wanted >= 3); proceeding with verified subset\n"),
        "{report}"
    );

    // --- e2e cap -----------------------------------------------------------
    let mut opts = options(&dir.join("cap"));
    opts.e2e_cap = 1;
    let (report, outcome) = validate(
        "hysteria2://a@127.0.0.1:8443?insecure=1#a\n\
         hysteria2://b@127.0.0.1:8444?insecure=1#b\n",
        "ok",
        &opts,
    );
    assert_eq!(outcome.exit_code, 0);
    assert_eq!(outcome.working.len(), 1, "{report}");
    assert!(
        report.contains(":: e2e: probing up to 1 open nodes (relay + throughput)...\n"),
        "{report}"
    );

    // --- Telegram probe failure degrades to all nodes ---------------------
    let opts = options(&dir.join("no-tg"));
    let (report, outcome) = validate(
        "hysteria2://pw@127.0.0.1:8445?insecure=1#tg\n",
        "no-tg",
        &opts,
    );
    assert_eq!(outcome.exit_code, 0);
    assert!(outcome.tg_working.is_empty());
    assert!(
        report.contains("! no Telegram-capable nodes (telegram routing will degrade)\n"),
        "{report}"
    );
    assert!(!opts.tmp_dir.join("tg-working.txt").exists());

    // --- throughput gate ---------------------------------------------------
    let opts = options(&dir.join("slow"));
    let (report, outcome) = validate(
        "hysteria2://pw@127.0.0.1:8446?insecure=1#slow\n",
        "fail-speed",
        &opts,
    );
    assert_eq!(outcome.exit_code, 1);
    assert!(report.contains("✓ e2e working: 0/1\n"), "{report}");
    assert!(
        report.contains("✗ ERROR: no working nodes; keeping existing config\n"),
        "{report}"
    );

    // --- relay failure -----------------------------------------------------
    let opts = options(&dir.join("dead"));
    let (report, outcome) = validate(
        "hysteria2://pw@127.0.0.1:8447?insecure=1#dead\n",
        "fail-relay",
        &opts,
    );
    assert_eq!(outcome.exit_code, 1);
    assert!(report.contains("✗ ERROR: no working nodes; keeping existing config\n"));

    // --- preserved shell bug: trojan nodes never reach the e2e probe -------
    let (_listener, live_port) = open_port();
    let opts = options(&dir.join("trojan"));
    let (report, outcome) = validate(
        &format!("trojan://pw@127.0.0.1:{live_port}?sni=x.example.com#tj\n"),
        "ok",
        &opts,
    );
    assert_eq!(outcome.exit_code, 1);
    assert!(
        report.contains(":: e2e: probing up to 0 open nodes (relay + throughput)...\n"),
        "{report}"
    );
    assert!(
        report.contains("✗ ERROR: no working nodes; keeping existing config\n"),
        "{report}"
    );

    // --- no parseable candidates ------------------------------------------
    let opts = options(&dir.join("garbage"));
    let (report, outcome) = validate("not-a-node\n", "ok", &opts);
    assert_eq!(outcome.exit_code, 1);
    assert!(
        report.contains("✗ ERROR: no parseable candidates\n"),
        "{report}"
    );

    // --- sing-box missing from PATH ---------------------------------------
    let empty = Stubs::new("empty-path");
    std::env::set_var("PATH", empty.only_path());
    let opts = options(&dir.join("no-sing-box"));
    let (report, outcome) = validate("hysteria2://pw@127.0.0.1:8448#x\n", "ok", &opts);
    assert_eq!(outcome.exit_code, 1);
    assert!(
        report.contains("✗ ERROR: sing-box not found in PATH\n"),
        "{report}"
    );
}
