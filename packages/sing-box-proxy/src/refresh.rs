//! `proxy refresh`: fetch fresh subscriptions, validate them, regenerate the
//! config, restart the proxy and smoke-test it.
//!
//! Port of the shell `refresh()` (and `fetch_sub`/`expand_fallback`, which live
//! in `subscriptions`). Two shell quirks are preserved deliberately:
//! 1. validation stderr is captured and the validation progress is therefore
//!    invisible; only the last six lines are printed when validation fails
//!    (`tail -6 "$ERRLOG"`).
//! 2. when validation fails, the function returns 0. The shell did
//!    `if ! WORKING=$(validate_nodes ...); then rc=$?; ... return $rc`, and
//!    `$?` in the branch is the status of the negated command (0), so the
//!    original `proxy refresh` exited 0 on validation failure. Preserved for
//!    exit-code parity; flip `return 0` below to `return 1` to fix it.

use crate::config;
use crate::output::Ui;
use crate::paths::Paths;
use crate::secrets;
use crate::service;
use crate::shell;
use crate::subscriptions;
use crate::validate::ValidateOptions;
use std::fs;

const SUBSCRIPTIONS: [&str; 9] = [
    "https://cdn.jsdelivr.net/gh/rtwo2/FastNodes@main/sub/protocols/vless.txt",
    "https://cdn.jsdelivr.net/gh/rtwo2/FastNodes@main/sub/everything.txt",
    "https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/sub_merge.txt",
    "https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/Eternity.txt",
    "https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub",
    "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/v2ray-base64.txt",
    "https://raw.githubusercontent.com/vless-reality/vless-reality.github.io/refs/heads/main/.github/links/v2.txt",
    "https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/airport_sub_merge.txt",
    "https://raw.githubusercontent.com/yebekhe/TelegramV2rayCollector/main/sub/base64/normal.txt",
];

fn previous_config_path(paths: &Paths) -> std::path::PathBuf {
    let mut path = paths.config.clone().into_os_string();
    path.push(".prev");
    std::path::PathBuf::from(path)
}

pub fn run(ui: &mut Ui, paths: &Paths) -> i32 {
    ui.step("proxy refresh");
    ui.say("Fetching fresh nodes...");

    let secret = match secrets::load_fallback(paths) {
        Ok(secret) => secret.unwrap_or_default(),
        Err(err) => {
            ui.fail(&format!("cannot read {}: {err}", paths.secret.display()));
            return 1;
        }
    };
    let fallback = subscriptions::expand_fallback(ui, &secret);
    let mut new_nodes = String::new();
    for url in SUBSCRIPTIONS {
        let data = subscriptions::fetch_sub(url);
        if data.is_empty() {
            ui.warn(&format!("no nodes from {}", subscriptions::basename(url)));
        } else {
            // `echo "$data" | wc -l`: the captured body has no trailing
            // newline, so this is the number of node lines.
            let count = data.matches('\n').count() + 1;
            ui.ok(&format!(
                "{} nodes from {}",
                count,
                subscriptions::basename(url)
            ));
            new_nodes.push('\n');
            new_nodes.push_str(&data);
        }
    }

    let mut all = fallback;
    if !new_nodes.is_empty() {
        all = format!("{all}\n{new_nodes}");
    }
    if all.is_empty() {
        ui.fail("no fallback nodes and no subscription nodes available");
        return 1;
    }

    let temp = match shell::TempDir::new("/tmp/proxy-refresh.") {
        Ok(temp) => temp,
        Err(err) => {
            ui.fail(&format!("cannot create temp dir: {err}"));
            return 1;
        }
    };
    let nodes_path = temp.path().join("nodes.txt");
    if let Err(err) = fs::write(&nodes_path, format!("{all}\n")) {
        ui.fail(&format!("cannot write node list: {err}"));
        return 1;
    }

    ui.say("Validating candidates (relay + throughput, ~1-3 min)...");
    let mut options = ValidateOptions::from_env();
    options.tmp_dir = temp.path().join("validate");
    let mut captured: Vec<u8> = Vec::new();
    let outcome = {
        let mut capture_ui = Ui::new(&mut captured, false, false);
        crate::validate::validate_nodes(&all, &options, &mut capture_ui)
    };
    if outcome.exit_code != 0 {
        // `tail -6 "$ERRLOG" >&2`.
        let text = String::from_utf8_lossy(&captured);
        let lines: Vec<&str> = text.lines().collect();
        for line in lines.iter().skip(lines.len().saturating_sub(6)) {
            ui.raw(line);
        }
        // Preserved shell bug: the branch returned the status of `! cmd` (0).
        return 0;
    }

    let working_lines: Vec<&str> = outcome
        .working
        .iter()
        .map(String::as_str)
        .filter(|line| subscriptions::starts_with_scheme(line))
        .collect();
    if working_lines.is_empty() {
        ui.fail("validation produced no working nodes — keeping existing config");
        return 1;
    }
    let count = working_lines.len();

    let tg_path = options.tmp_dir.join("tg-working.txt");
    let tg_meta = fs::metadata(&tg_path).ok();
    if let Some(meta) = tg_meta.filter(|meta| meta.len() > 0) {
        let text = fs::read_to_string(&tg_path).unwrap_or_default();
        ui.ok(&format!(
            "{} Telegram-capable nodes",
            text.matches('\n').count()
        ));
        let _ = meta;
    } else {
        ui.warn("no Telegram-capable nodes - Telegram may fail until a good node appears");
    }

    let prev_path = previous_config_path(paths);
    if paths.config.is_file() {
        if let Err(err) = fs::copy(&paths.config, &prev_path) {
            ui.fail(&format!("cannot back up config: {err}"));
            return 1;
        }
    }

    ui.say(&format!(
        "Regenerating config with {count} validated nodes..."
    ));
    if let Err(err) = fs::write(&nodes_path, format!("{}\n", working_lines.join("\n"))) {
        ui.fail(&format!("cannot write node list: {err}"));
        return 1;
    }
    let tg_text = fs::read_to_string(&tg_path).unwrap_or_default();
    let lan_auth = secrets::load_lan_auth(paths);
    let generated = config::build_config(&working_lines.join("\n"), &tg_text, &lan_auth);
    for line in &generated.logs {
        ui.raw(line);
    }
    let Some(config) = generated.config else {
        return generated.exit_code;
    };
    if generated.exit_code != 0 {
        return generated.exit_code;
    }
    if let Err(err) = config::write_config(&paths.config, &config) {
        ui.fail(&format!("cannot write config: {err}"));
        return 1;
    }
    ui.ok(&format!(
        "Config regenerated: {} ({count} nodes)",
        paths.config.display()
    ));

    if shell::run_success(
        "systemctl",
        &["--user", "is-active", "--quiet", "sing-box-proxy.service"],
        true,
    ) {
        ui.say("Restarting proxy service...");
        if shell::run_success(
            "systemctl",
            &["--user", "restart", "sing-box-proxy.service"],
            true,
        ) {
            // Service restarted.
        } else {
            let rc = service::start(ui, paths);
            if rc != 0 {
                return rc;
            }
        }
    } else {
        let rc = service::start(ui, paths);
        if rc != 0 {
            return rc;
        }
    }

    ui.say("Smoke-testing the new config (up to ~45s)...");
    let mut passed = false;
    let mut upstream = String::new();
    let mut telegram = String::new();
    for _ in 0..4 {
        shell::sleep_secs(6);
        upstream = service::curl_proxy_code("https://www.gstatic.com/generate_204", "5");
        telegram = service::curl_proxy_code("https://api.telegram.org", "8");
        if upstream == "204" && telegram != "000" {
            passed = true;
            break;
        }
    }
    if passed {
        ui.ok(&format!(
            "Smoke test passed (upstream {upstream}, telegram {telegram})"
        ));
        return 0;
    }
    ui.warn("new config failed the smoke test - restoring previous config");
    if prev_path.is_file() {
        if let Err(err) = fs::copy(&prev_path, &paths.config) {
            ui.fail(&format!("cannot restore config: {err}"));
            return 1;
        }
        if shell::run_success(
            "systemctl",
            &["--user", "restart", "sing-box-proxy.service"],
            true,
        ) {
            // Service restarted with the previous config.
        } else {
            let rc = service::start(ui, paths);
            if rc != 0 {
                return rc;
            }
        }
        ui.ok("previous config restored");
        return 1;
    }
    ui.warn("no previous config to restore - keeping the new one");
    1
}
