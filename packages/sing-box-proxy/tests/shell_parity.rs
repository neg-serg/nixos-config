//! CLI parity against the legacy shell script.
//!
//! These tests are skipped unless `PROXY_SHELL` points at the legacy
//! `packages/local-bin/bin/proxy` (the Nix build sandbox does not have it).
//! Only commands that never read the SOPS secrets are exercised: `status`,
//! `off` and `run`, plus the unknown-command and no-argument error paths.
//! All external programs are stubs; the shell and the port see the same fake
//! environment and must produce identical stdout/stderr/exit codes.

mod common;

use common::scripts::*;
use common::{fixture, run_proxy, run_shell, shell_script, stderr, stdout, Stubs, TestDir};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Output;

fn normalize(text: &str, paths: &[&Path]) -> String {
    let mut normalized = text.to_string();
    for path in paths {
        normalized = normalized.replace(&path.display().to_string(), "PROXY");
    }
    normalized
}

fn assert_parity(name: &str, shell: &Output, rust: &Output, paths: &[&Path]) {
    assert_eq!(
        normalize(&stdout(shell), paths),
        normalize(&stdout(rust), paths),
        "{name}: stdout differs"
    );
    assert_eq!(
        normalize(&stderr(shell), paths),
        normalize(&stderr(rust), paths),
        "{name}: stderr differs"
    );
    assert_eq!(
        shell.status.code(),
        rust.status.code(),
        "{name}: exit code differs (shell stderr: {})",
        stderr(shell)
    );
}

fn home_with_default_config(dir: &TestDir, fixture_name: &str) -> PathBuf {
    let home = dir.join("home");
    let config_dir = home.join(".config/sing-box-trojan");
    fs::create_dir_all(&config_dir).unwrap();
    fs::write(config_dir.join("config.json"), fixture(fixture_name)).unwrap();
    home
}

#[test]
fn cli_parity_with_the_legacy_shell_script() {
    let Some(script) = shell_script() else {
        eprintln!("skipping shell parity: set PROXY_SHELL to the legacy proxy script");
        return;
    };
    let binary = PathBuf::from(env!("CARGO_BIN_EXE_proxy"));
    let paths: [&Path; 2] = [script.as_path(), binary.as_path()];
    let dir = TestDir::new("parity");

    // --- status, stopped, no config ---------------------------------------
    let stubs = Stubs::new("parity-status-empty");
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_FAIL);
    stubs.add("ss", SS_LISTENERS);
    let env = vec![
        (
            "HOME".to_string(),
            dir.join("empty-home").display().to_string(),
        ),
        (
            "PROXY_CONFIG".to_string(),
            dir.join("empty-home/config.json").display().to_string(),
        ),
    ];
    let path = stubs.layered_path();
    let shell_out = run_shell(&script, &[], &env, &path);
    let rust_out = run_proxy(&[], &env, &path);
    assert_parity("status/stopped/no-config", &shell_out, &rust_out, &paths);
    let shell_out = run_shell(&script, &["status"], &env, &path);
    let rust_out = run_proxy(&["status"], &env, &path);
    assert_parity("status/explicit", &shell_out, &rust_out, &paths);

    // --- status, stopped, with a generated config -------------------------
    let home = home_with_default_config(&dir, "golden/gen/mixed_nolan.json");
    let env = vec![("HOME".to_string(), home.display().to_string())];
    let shell_out = run_shell(&script, &[], &env, &path);
    let rust_out = run_proxy(&[], &env, &path);
    assert_parity("status/stopped/with-config", &shell_out, &rust_out, &paths);
    assert!(
        stdout(&shell_out).contains("Nodes:     27 outbounds"),
        "{}",
        stdout(&shell_out)
    );

    // --- status, failed, with scripted live checks ------------------------
    let stubs = Stubs::new("parity-status-run");
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
    let home = dir.join("no-config-home");
    let env = vec![("HOME".to_string(), home.display().to_string())];
    let path = stubs.layered_path();
    let shell_out = run_shell(&script, &[], &env, &path);
    let rust_out = run_proxy(&[], &env, &path);
    assert_parity("status/running", &shell_out, &rust_out, &paths);
    assert!(stdout(&shell_out).contains("Active:    0 (urltest pick)"));

    // --- status, FAILED ----------------------------------------------------
    let stubs = Stubs::new("parity-status-failed");
    stubs.add(
        "systemctl",
        r#"case "$*" in
  *is-failed*) exit 0 ;;
  *) exit 1 ;;
esac"#,
    );
    stubs.add("pgrep", PGREP_FAIL);
    stubs.add("ss", SS_LISTENERS);
    let env = vec![("HOME".to_string(), home.display().to_string())];
    let path = stubs.layered_path();
    let shell_out = run_shell(&script, &[], &env, &path);
    let rust_out = run_proxy(&[], &env, &path);
    assert_parity("status/failed", &shell_out, &rust_out, &paths);
    assert!(stdout(&shell_out).contains("FAILED"));

    // --- off ---------------------------------------------------------------
    let stubs = Stubs::new("parity-off");
    stubs.add("systemctl", SYSTEMCTL_FAIL);
    stubs.add("pgrep", PGREP_FAIL);
    stubs.add("pkill", IGNORE);
    stubs.add("sudo", SYSTEMCTL_FAIL);
    let env = vec![("HOME".to_string(), home.display().to_string())];
    let path = stubs.layered_path();
    let shell_out = run_shell(&script, &["off"], &env, &path);
    let rust_out = run_proxy(&["off"], &env, &path);
    assert_parity("off", &shell_out, &rust_out, &paths);

    // --- unknown command / run without arguments --------------------------
    for args in [vec!["bogus"], vec!["--help"], vec!["run"]] {
        let stubs = Stubs::new("parity-errors");
        let env = vec![("HOME".to_string(), home.display().to_string())];
        let path = stubs.layered_path();
        let shell_out = run_shell(&script, &args, &env, &path);
        let rust_out = run_proxy(&args, &env, &path);
        assert_parity(&format!("error/{args:?}"), &shell_out, &rust_out, &paths);
    }

    // --- run passthrough ---------------------------------------------------
    let stubs = Stubs::new("parity-run");
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
    let report_arg = report.display().to_string();
    for extra in [
        vec![],
        vec![
            ("NO_PROXY".to_string(), "fixture.invalid".to_string()),
            ("no_proxy".to_string(), "garbage.invalid".to_string()),
        ],
    ] {
        let mut env = vec![("HOME".to_string(), home.display().to_string())];
        env.extend(extra.clone());
        let path = stubs.layered_path();
        let shell_out = run_shell(&script, &["run", &report_arg], &env, &path);
        let rust_out = run_proxy(&["run", &report_arg], &env, &path);
        assert_parity(&format!("run/{extra:?}"), &shell_out, &rust_out, &paths);
        assert_eq!(shell_out.status.code(), Some(7));
    }
}
