//! CLI behaviour tests.
//!
//! Everything external is stubbed on PATH: systemctl, pgrep, pkill, ss, stat,
//! ip, curl, sing-box, setsid, nohup and sleep. The real sing-box process, the
//! live config, /tmp/sing-box-trojan.log and /run/secrets are never touched:
//! HOME and the PROXY_* path overrides always point into a temp dir.

mod common;

use common::scripts::*;
use common::{base_env, fixture, run_proxy, shell_mode, stderr, stdout, Stubs, TestDir};
use std::fs;
use std::os::unix::fs::PermissionsExt;

fn stopped_stubs(tag: &str) -> Stubs {
    let stubs = Stubs::new(tag);
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_FAIL);
    stubs.add("ss", SS_LISTENERS);
    stubs
}

#[test]
fn no_arguments_means_status() {
    let dir = TestDir::new("status-empty");
    let stubs = stopped_stubs("status-empty");
    let path = stubs.only_path();
    let env = base_env(&dir);
    let output = run_proxy(&[], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        "== proxy status ==\n\
         Service:   STOPPED\n\
         Listeners: 10808 10810\n\
         Xray:      stopped\n"
    );
}

#[test]
fn status_reports_config_counts() {
    let dir = TestDir::new("status-config");
    let stubs = stopped_stubs("status-config");
    stubs.add("stat", STAT);
    let config_path = dir.join("config.json");
    fs::write(&config_path, fixture("golden/gen/mixed_nolan.json")).unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    let output = run_proxy(&[], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        "== proxy status ==\n\
         Service:   STOPPED\n\
         Listeners: 10808 10810\n\
         Nodes:     27 outbounds (config: 2026-01-02 03:04:05)\n\
         TG:        27 nodes in tg-auto group\n\
         Xray:      stopped\n"
    );
}

#[test]
fn status_running_prints_checks_and_active_node() {
    let dir = TestDir::new("status-running");
    let stubs = Stubs::new("status-running");
    stubs.add(
        "systemctl",
        r#"case "$*" in
  *is-failed*) exit 1 ;;
  *--user*is-active*sing-box-proxy*) exit 0 ;;
  *) exit 1 ;;
esac"#,
    );
    stubs.add("pgrep", PGREP_4242);
    stubs.add("ss", SS_ACTIVE);
    stubs.add("curl", CURL_STATUS);
    let path = stubs.only_path();
    let env = base_env(&dir);
    let output = run_proxy(&[], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        "== proxy status ==\n\
         Service:   RUNNING\n\
         Listeners: 10808\n\
         Upstream:  OK in 0.123s\n\
         Telegram:  OK (HTTP 200 in 0.500s)\n\
         Active:    0 (urltest pick)\n\
         Xray:      stopped\n"
    );
}

#[test]
fn status_with_invalid_config_prints_unknown_counts() {
    let dir = TestDir::new("status-bad-config");
    let stubs = Stubs::new("status-bad-config");
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_FAIL);
    stubs.add("ss", "exit 0");
    stubs.add("stat", STAT);
    let config_path = dir.join("config.json");
    fs::write(&config_path, "not json").unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    let output = run_proxy(&[], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(
        stdout(&output),
        "== proxy status ==\n\
         Service:   STOPPED\n\
         Nodes:     ? outbounds (config: 2026-01-02 03:04:05)\n\
         TG:        ? nodes in tg-auto group\n\
         Xray:      stopped\n"
    );
}

#[test]
fn unknown_command_and_usage() {
    let dir = TestDir::new("unknown");
    let stubs = stopped_stubs("unknown");
    let path = stubs.only_path();
    let env = base_env(&dir);
    let output = run_proxy(&["bogus"], &env, &path);
    let binary = env!("CARGO_BIN_EXE_proxy");

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("✗ unknown command: bogus\nUsage: {binary} {{on|off|status|refresh|gen|run <cmd...>}}\n")
    );
}

#[test]
fn run_without_arguments_fails() {
    let dir = TestDir::new("run-empty");
    let stubs = Stubs::new("run-empty");
    let path = stubs.only_path();
    let env = base_env(&dir);
    let output = run_proxy(&["run"], &env, &path);
    let binary = env!("CARGO_BIN_EXE_proxy");

    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("✗ nothing to run\nUsage: {binary} run <command...>\n")
    );
}

#[test]
fn run_exports_proxy_variables_and_propagates_exit_code() {
    let dir = TestDir::new("run-exec");
    let stubs = Stubs::new("run-exec");
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_FAIL);
    let report = dir.join("report");
    common::write_script(
        &report,
        r#"printf 'ALL_PROXY=%s\n' "$ALL_PROXY"
printf 'all_proxy=%s\n' "$all_proxy"
printf 'HTTPS_PROXY=%s\n' "$HTTPS_PROXY"
printf 'https_proxy=%s\n' "$https_proxy"
printf 'HTTP_PROXY=%s\n' "$HTTP_PROXY"
printf 'http_proxy=%s\n' "$http_proxy"
printf 'NO_PROXY=%s\n' "$NO_PROXY"
printf 'no_proxy=%s\n' "$no_proxy"
exit 7"#,
    );
    let report = report.to_str().unwrap().to_string();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    // The shell forces lowercase no_proxy to the (defaulted) NO_PROXY value.
    env.push(("no_proxy".into(), "garbage.invalid".into()));
    let output = run_proxy(&["run", &report], &env, &path);
    let binary = env!("CARGO_BIN_EXE_proxy");

    assert_eq!(output.status.code(), Some(7));
    assert_eq!(
        stdout(&output),
        "ALL_PROXY=socks5h://127.0.0.1:10808\n\
         all_proxy=socks5h://127.0.0.1:10808\n\
         HTTPS_PROXY=socks5h://127.0.0.1:10808\n\
         https_proxy=socks5h://127.0.0.1:10808\n\
         HTTP_PROXY=socks5h://127.0.0.1:10808\n\
         http_proxy=socks5h://127.0.0.1:10808\n\
         NO_PROXY=127.0.0.1,localhost\n\
         no_proxy=127.0.0.1,localhost\n"
    );
    assert_eq!(
        stderr(&output),
        format!(
            "! no proxy detected on 127.0.0.1:10808 — run '{binary} on' first\n:: via socks5h://127.0.0.1:10808: {report}\n"
        )
    );
}

#[test]
fn gen_without_secret_does_not_create_a_config() {
    let dir = TestDir::new("gen-empty");
    let stubs = Stubs::new("gen-empty");
    let config_path = dir.join("config/config.json");
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    let output = run_proxy(&["gen"], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "! No fallback nodes — run 'proxy refresh' or create the SOPS secret\n"
    );
    assert!(!config_path.exists());
}

#[test]
fn gen_creates_the_config_from_synthetic_secrets() {
    let dir = TestDir::new("gen-config");
    let stubs = Stubs::new("gen-config");
    let secret = dir.join("fallback.txt");
    let lan = dir.join("lan.txt");
    fs::write(&secret, fixture("nodes/mixed.txt")).unwrap();
    fs::write(&lan, fixture("lan/lan_on.txt")).unwrap();
    let config_path = dir.join("config/config.json");
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    env.push(("PROXY_SECRET".into(), secret.display().to_string()));
    env.push(("PROXY_LAN_SECRET".into(), lan.display().to_string()));
    let output = run_proxy(&["gen"], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        ":: First run: creating config...\n\
         ! no Telegram-capable nodes — tg-auto falls back to all nodes\n\
         ✓ Config: 27 outbounds + urltest (27 tg-capable)\n"
    );
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        fixture("golden/gen/mixed_lan.json")
    );
    assert_eq!(shell_mode(&config_path), 0o600);
    assert_eq!(shell_mode(config_path.parent().unwrap()), 0o700);
}

#[test]
fn gen_heals_an_existing_config() {
    let dir = TestDir::new("gen-heal");
    let stubs = Stubs::new("gen-heal");
    let lan = dir.join("lan.txt");
    fs::write(&lan, fixture("lan/lan_on.txt")).unwrap();
    let config_path = dir.join("config.json");
    fs::write(&config_path, fixture("bootstrap/old_no_tg.json")).unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    env.push(("PROXY_LAN_SECRET".into(), lan.display().to_string()));
    let output = run_proxy(&["gen"], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        ":: Config exists — checking DNS/LAN sections...\n\
         :: Config: added tg-auto group (all nodes until next refresh)\n\
         :: Config: DNS/route reset to final shape (client-side resolve)\n\
         :: Config: added LAN inbound (0.0.0.0:10810, password auth)\n\
         :: Config: patched\n"
    );
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        fixture("golden/bootstrap/old_no_tg.json")
    );
    assert_eq!(shell_mode(&config_path), 0o600);
}

#[test]
fn gen_leaves_an_already_final_config_untouched() {
    let dir = TestDir::new("gen-noop");
    let stubs = Stubs::new("gen-noop");
    let lan = dir.join("lan.txt");
    fs::write(&lan, fixture("lan/lan_on.txt")).unwrap();
    let config_path = dir.join("config.json");
    fs::write(&config_path, fixture("bootstrap/final_noop.json")).unwrap();
    // A read-only file proves the patcher does not rewrite a no-op config.
    fs::set_permissions(&config_path, fs::Permissions::from_mode(0o444)).unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    env.push(("PROXY_LAN_SECRET".into(), lan.display().to_string()));
    let output = run_proxy(&["gen"], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stderr(&output),
        ":: Config exists — checking DNS/LAN sections...\n:: Config: patched\n"
    );
    assert_eq!(
        fs::read_to_string(&config_path).unwrap(),
        fixture("bootstrap/final_noop.json")
    );
    assert_eq!(shell_mode(&config_path), 0o444);
}

fn refresh_stubs(tag: &str, probes_succeed: bool) -> Stubs {
    let stubs = Stubs::new(tag);
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_4242);
    stubs.add("pkill", IGNORE);
    stubs.add("sleep", SLEEP);
    stubs.add("nohup", IGNORE);
    stubs.add("setsid", IGNORE);
    stubs.add("sing-box", IGNORE);
    stubs.add("ip", IP);
    let probes = if probes_succeed {
        r#"  *speed.cloudflare.com*) printf '250000' ;;
  *api.telegram.org*) printf '200' ;;
  *) printf '204' ;;"#
    } else {
        "  *) printf '000' ;;"
    };
    stubs.add(
        "curl",
        &format!(
            r#"url=""
for arg in "$@"; do case "$arg" in http*) url="$arg" ;; esac; done
case "$url" in
  *raw.githubusercontent*|*jsdelivr*) printf 'hysteria2://subnode@127.0.0.1:443?insecure=1#sub\n' ;;
{probes}
esac"#
        ),
    );
    stubs
}

#[test]
fn refresh_validates_and_regenerates_without_network() {
    let dir = TestDir::new("refresh-ok");
    let stubs = refresh_stubs("refresh-ok", true);
    let secret = dir.join("fallback.txt");
    fs::write(
        &secret,
        "hysteria2://fallback@127.0.0.1:443?insecure=1#fb\n",
    )
    .unwrap();
    let config_path = dir.join("config.json");
    fs::write(&config_path, "old-config").unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    env.push(("PROXY_SECRET".into(), secret.display().to_string()));
    let output = run_proxy(&["refresh"], &env, &path);
    let report = stderr(&output);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert!(report.starts_with("== proxy refresh ==\n"), "{report}");
    assert!(report.contains(":: Fetching fresh nodes...\n"));
    assert_eq!(report.matches(" nodes from ").count(), 9, "{report}");
    for name in [
        "vless.txt",
        "everything.txt",
        "sub_merge.txt",
        "Eternity.txt",
        "sub",
        "v2ray-base64.txt",
        "v2.txt",
        "airport_sub_merge.txt",
        "normal.txt",
    ] {
        assert!(
            report.contains(&format!("nodes from {name}\n")),
            "missing {name}: {report}"
        );
    }
    assert!(report.contains(":: Validating candidates (relay + throughput, ~1-3 min)...\n"));
    // Validation stderr is captured and discarded on success.
    assert!(!report.contains(":: candidates:"), "{report}");
    assert!(!report.contains("  e2e:"), "{report}");
    assert!(report.contains(":: Regenerating config with 1 validated nodes...\n"));
    assert!(report.contains(&format!(
        "✓ Config regenerated: {} (1 nodes)\n",
        config_path.display()
    )));
    assert!(!report.contains(":: Restarting proxy service..."));
    assert!(report.contains("✓ Proxy on 127.0.0.1:10808\n"), "{report}");
    assert!(
        report.contains(":: LAN proxy: socks5://192.0.2.10:10810 (no auth, LAN only)\n"),
        "{report}"
    );
    assert!(report.contains(":: Smoke-testing the new config (up to ~45s)...\n"));
    assert!(report.contains("✓ Smoke test passed (upstream 204, telegram 200)\n"));

    assert_eq!(
        fs::read_to_string(dir.join("config.json.prev")).unwrap(),
        "old-config"
    );
    let config: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&config_path).unwrap()).unwrap();
    let outbounds = config["outbounds"].as_array().unwrap();
    assert_eq!(outbounds.len(), 4);
    assert_eq!(outbounds[0]["type"], "hysteria2");
    assert_eq!(outbounds[0]["password"], "fallback");
    assert_eq!(outbounds[0]["tag"], "hy-0");
    assert_eq!(outbounds[2]["tag"], "tg-auto");
    assert_eq!(outbounds[2]["outbounds"], serde_json::json!(["hy-0"]));
    assert_eq!(config["inbounds"][1].get("users"), None);
    assert_eq!(shell_mode(&config_path), 0o600);
}

#[test]
fn refresh_keeps_the_old_config_when_validation_fails() {
    let dir = TestDir::new("refresh-fail");
    let stubs = refresh_stubs("refresh-fail", false);
    let secret = dir.join("fallback.txt");
    fs::write(
        &secret,
        "hysteria2://fallback@127.0.0.1:443?insecure=1#fb\n",
    )
    .unwrap();
    let config_path = dir.join("config.json");
    fs::write(&config_path, "old-config").unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    env.push(("PROXY_SECRET".into(), secret.display().to_string()));
    let output = run_proxy(&["refresh"], &env, &path);
    let report = stderr(&output);

    // Preserved shell quirk: the failed `if !` branch returns 0.
    assert_eq!(output.status.code(), Some(0), "{report}");
    assert_eq!(stdout(&output), "");
    assert!(!report.contains(":: candidates:"), "{report}");
    assert!(
        report.contains(":: tcp-scan: 0 tcp, 1 udp (skipped)\n"),
        "{report}"
    );
    assert!(report.contains("✓ e2e working: 0/1\n"), "{report}");
    assert!(
        report.contains("✗ ERROR: no working nodes; keeping existing config\n"),
        "{report}"
    );
    assert!(!report.contains(":: Regenerating config"), "{report}");
    assert!(!report.contains("Smoke-testing"), "{report}");
    assert_eq!(fs::read_to_string(&config_path).unwrap(), "old-config");
    assert!(!dir.join("config.json.prev").exists());
}

#[test]
fn off_stops_the_proxy_and_restores_xray_messages() {
    let dir = TestDir::new("off");
    let stubs = Stubs::new("off");
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pkill", IGNORE);
    stubs.add("sudo", SYSTEMCTL_FAIL);
    let path = stubs.only_path();
    let env = base_env(&dir);
    let output = run_proxy(&["off"], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        ":: Restoring xray...\n\
         ! no passwordless sudo — run: sudo systemctl start xray.service\n\
         ✓ Proxy off\n"
    );
}

#[test]
fn proxy_config_override_is_honored() {
    // Guards the additive testing hook: the default path would be
    // $HOME/.config/sing-box-trojan/config.json.
    let dir = TestDir::new("override");
    let stubs = stopped_stubs("override");
    stubs.add("stat", STAT);
    let config_path = dir.join("custom.json");
    fs::write(
        &config_path,
        r#"{"log":{"level":"error"},"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{}}"#,
    )
    .unwrap();
    let path = stubs.only_path();
    let mut env = base_env(&dir);
    env.push(("PROXY_CONFIG".into(), config_path.display().to_string()));
    let output = run_proxy(&[], &env, &path);

    assert_eq!(output.status.code(), Some(0));
    assert!(
        stdout(&output).contains("Nodes:     0 outbounds (config: 2026-01-02 03:04:05)\n"),
        "{}",
        stdout(&output)
    );
}
