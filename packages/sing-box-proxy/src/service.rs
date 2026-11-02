//! `on`/`off`/`status`/`gen`/`run` commands.
//!
//! All human messages keep the shell's split: status/active lines go to stdout,
//! every `say`/`ok`/`warn`/`fail`/`step` goes to stderr. systemd/sing-box calls
//! keep the original arguments and the original stderr suppression.

use crate::config;
use crate::output::{Ui, BOLD, CYAN, GREEN, RED, RESET, YELLOW};
use crate::paths::Paths;
use crate::secrets;
use crate::shell;
use serde_json::Value;
use std::fs;
use std::io::Write;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

const PROXY_SERVICE: &str = "sing-box-proxy.service";
const XRAY_SERVICE: &str = "xray.service";
const SOCKS_ENDPOINT: &str = "127.0.0.1:10808";
const PROXY_URL: &str = "socks5h://127.0.0.1:10808";

/// `proxy on` / `proxy gen`: create or heal the config.
pub fn bootstrap(ui: &mut Ui, paths: &Paths) -> i32 {
    if paths.config.is_file() {
        ui.say("Config exists — checking DNS/LAN sections...");
        let text = match fs::read_to_string(&paths.config) {
            Ok(text) => text,
            Err(err) => {
                ui.fail(&format!("cannot read config: {err}"));
                return 1;
            }
        };
        let mut config: Value = match serde_json::from_str(&text) {
            Ok(config) => config,
            Err(err) => {
                ui.fail(&format!("cannot parse config: {err}"));
                return 1;
            }
        };
        let lan_auth = secrets::load_lan_auth(paths);
        match config::patch_config(&mut config, &lan_auth) {
            Ok(outcome) => {
                for line in &outcome.logs {
                    ui.raw(line);
                }
                if outcome.changed {
                    if let Err(err) = config::write_config_in_place(&paths.config, &config) {
                        ui.fail(&format!("cannot write config: {err}"));
                        return 1;
                    }
                }
                ui.raw(":: Config: patched");
                0
            }
            Err(message) => {
                ui.fail(&message);
                1
            }
        }
    } else {
        let secret = match secrets::load_fallback(paths) {
            Ok(secret) => secret.unwrap_or_default(),
            Err(err) => {
                ui.fail(&format!("cannot read {}: {err}", paths.secret.display()));
                return 1;
            }
        };
        let fallback = crate::subscriptions::expand_fallback(ui, &secret);
        if fallback.is_empty() {
            ui.warn("No fallback nodes — run 'proxy refresh' or create the SOPS secret");
            return 0;
        }
        ui.say("First run: creating config...");
        let lan_auth = secrets::load_lan_auth(paths);
        let outcome = config::build_config(&fallback, &tg_nodes_from_env(), &lan_auth);
        for line in &outcome.logs {
            ui.raw(line);
        }
        let Some(config) = outcome.config else {
            return outcome.exit_code;
        };
        if outcome.exit_code != 0 {
            return outcome.exit_code;
        }
        match config::write_config(&paths.config, &config) {
            Ok(()) => 0,
            Err(err) => {
                ui.fail(&format!("cannot write config: {err}"));
                1
            }
        }
    }
}

/// The shell's bootstrap only sets `NODES_FILE`/`CFG_PATH`/`LAN_AUTH`, so a
/// `TG_NODES_FILE`/`TG_NODES_TEXT` inherited from the caller's environment still
/// reached the embedded generator. Preserve that (empty values are ignored, as
/// in `os.environ.get(...)` truthiness).
fn tg_nodes_from_env() -> String {
    match std::env::var("TG_NODES_FILE") {
        Ok(path) if !path.is_empty() => fs::read_to_string(path).unwrap_or_default(),
        _ => std::env::var("TG_NODES_TEXT").unwrap_or_default(),
    }
}

/// `proxy on`: stop xray, prefer the user unit, fall back to a detached run.
pub fn start(ui: &mut Ui, paths: &Paths) -> i32 {
    if shell::run_success("systemctl", &["is-active", "--quiet", XRAY_SERVICE], false) {
        ui.say("Stopping xray...");
        if !shell::run_success("sudo", &["-n", "systemctl", "stop", XRAY_SERVICE], true) {
            // xray runs as the user — pkill works without root; systemd then
            // marks the unit inactive.
            shell::pkill("xray.*config.json");
            ui.warn("no passwordless sudo — xray stopped via pkill");
        }
    }
    if shell::run_success("systemctl", &["--user", "start", PROXY_SERVICE], true) {
        shell::sleep_secs(1);
        if shell::run_success(
            "systemctl",
            &["--user", "is-active", "--quiet", PROXY_SERVICE],
            true,
        ) {
            ui.ok(&format!("Proxy on {SOCKS_ENDPOINT} (systemd user service)"));
            lan_msg(ui, paths);
            return 0;
        }
    }
    // Fallback (user unit not installed): legacy direct launch.
    shell::pkill("sing-box.*trojan");
    shell::sleep_secs(1);
    if let Ok(log) = fs::File::create(&paths.log) {
        if let Ok(log_stderr) = log.try_clone() {
            let _ = Command::new("nohup")
                .arg("sing-box")
                .arg("run")
                .arg("-c")
                .arg(&paths.config)
                .stdin(Stdio::inherit())
                .stdout(Stdio::from(log))
                .stderr(Stdio::from(log_stderr))
                .spawn();
        }
    }
    shell::sleep_secs(2);
    if shell::pgrep("sing-box.*trojan") {
        ui.ok(&format!("Proxy on {SOCKS_ENDPOINT}"));
        lan_msg(ui, paths);
        0
    } else {
        ui.fail("proxy failed to start");
        // `tail -3 "$LOG" 2>/dev/null || true` writes to stdout.
        for line in shell::tail_lines(&paths.log, 3) {
            println!("{line}");
        }
        1
    }
}

/// `proxy off`: stop the user unit (or pkill the legacy process), restore xray.
pub fn stop(ui: &mut Ui, paths: &Paths) -> i32 {
    let _ = paths;
    if !shell::run_success("systemctl", &["--user", "stop", PROXY_SERVICE], true) {
        shell::pkill("sing-box.*trojan");
    }
    if !shell::run_success("systemctl", &["is-active", "--quiet", XRAY_SERVICE], true) {
        ui.say("Restoring xray...");
        if !shell::run_success("sudo", &["-n", "systemctl", "start", XRAY_SERVICE], true) {
            ui.warn("no passwordless sudo — run: sudo systemctl start xray.service");
        }
    }
    ui.ok("Proxy off");
    0
}

fn lan_msg(ui: &mut Ui, paths: &Paths) {
    let ip = shell::stdout_trimmed("ip", &["-4", "-o", "addr", "show", "scope", "global"])
        .and_then(|output| {
            let first_line = output.lines().next()?.to_string();
            let field = first_line.split_whitespace().nth(3)?.to_string();
            Some(field.split('/').next().unwrap_or("").to_string())
        })
        .filter(|address| !address.is_empty());
    let auth = if secrets::load_lan_auth(paths).is_empty() {
        "no auth"
    } else {
        "user:pass auth"
    };
    match ip {
        Some(address) => ui.say(&format!(
            "LAN proxy: socks5://{address}:10810 ({auth}, LAN only)"
        )),
        None => ui.say(&format!("LAN proxy: 0.0.0.0:10810 ({auth}, LAN only)")),
    }
}

/// `curl ... --socks5-hostname 127.0.0.1:10808 <url>` with the shell's
/// `|| echo 000` fallback: the printed code is stdout plus "000" on failure.
pub fn curl_proxy_code(url: &str, max_time: &str) -> String {
    let output = shell::run_capture(
        "curl",
        &[
            "-sS".into(),
            "-m".into(),
            max_time.into(),
            "-o".into(),
            "/dev/null".into(),
            "-w".into(),
            "%{http_code}".into(),
            "--socks5-hostname".into(),
            SOCKS_ENDPOINT.into(),
            url.into(),
        ],
        None,
        true,
    );
    match output {
        Ok(output) => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            if !output.status.success() {
                text.push_str("000");
            }
            text.trim_end_matches('\n').to_string()
        }
        Err(_) => "000".to_string(),
    }
}

/// `curl -w '%{http_code}|%{time_total}'` variant used by `status`.
pub fn curl_proxy_code_and_time(url: &str, max_time: &str) -> String {
    let output = shell::run_capture(
        "curl",
        &[
            "-sS".into(),
            "-m".into(),
            max_time.into(),
            "-o".into(),
            "/dev/null".into(),
            "-w".into(),
            "%{http_code}|%{time_total}".into(),
            "--socks5-hostname".into(),
            SOCKS_ENDPOINT.into(),
            url.into(),
        ],
        None,
        true,
    );
    match output {
        Ok(output) => {
            let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
            if !output.status.success() {
                text.push_str("000|0");
            }
            text.trim_end_matches('\n').to_string()
        }
        Err(_) => "000|0".to_string(),
    }
}

fn stat_age(path: &std::path::Path) -> String {
    let output = shell::run_capture(
        "stat",
        &["-c".into(), "%y".into(), path.as_os_str().to_os_string()],
        None,
        true,
    );
    match output {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout).into_owned();
            let first = text.split('.').next().unwrap_or("");
            first.trim_end_matches('\n').to_string()
        }
        _ => String::new(),
    }
}

fn outbounds_array(config: &Value) -> Option<&Vec<Value>> {
    config.get("outbounds").and_then(Value::as_array)
}

fn count_nodes(config: &Value) -> String {
    match outbounds_array(config) {
        Some(outbounds) => outbounds
            .iter()
            .filter(|outbound| {
                let kind = outbound.get("type").and_then(Value::as_str).unwrap_or("");
                kind != "urltest" && kind != "direct"
            })
            .count()
            .to_string(),
        None => "?".to_string(),
    }
}

fn count_tg_nodes(config: &Value) -> String {
    let Some(outbounds) = outbounds_array(config) else {
        return "?".to_string();
    };
    let mut count = 0usize;
    for outbound in outbounds {
        if outbound.get("tag").and_then(Value::as_str) != Some("tg-auto") {
            continue;
        }
        match outbound.get("outbounds").and_then(Value::as_array) {
            Some(nodes) => count += nodes.len(),
            None => return "?".to_string(),
        }
    }
    count.to_string()
}

fn listener_ports() -> Vec<String> {
    let Some(output) = shell::stdout_trimmed("ss", &["-tlnp"]) else {
        return Vec::new();
    };
    let mut ports: Vec<(i64, String)> = Vec::new();
    for line in output.lines() {
        if !["10808", "10810", "10811", "10812"]
            .iter()
            .any(|port| line.contains(port))
        {
            continue;
        }
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let address = fields[3];
        let port = match address.rsplit_once(':') {
            Some((_, port)) => port,
            None => address,
        };
        ports.push((port.parse().unwrap_or(0), port.to_string()));
    }
    ports.sort_by_key(|(numeric, _)| *numeric);
    ports.dedup_by_key(|(numeric, _)| *numeric);
    ports.into_iter().map(|(_, text)| text).collect()
}

/// Strip the `:[0-9]*` suffix of `awk`'s address field (`sed 's/:[0-9]*$//'`).
fn strip_trailing_port(address: &str) -> &str {
    if let Some(index) = address.rfind(':') {
        let suffix = &address[index + 1..];
        if suffix.chars().all(|ch| ch.is_ascii_digit()) {
            return &address[..index];
        }
    }
    address
}

/// `proxy status`: machine-readable-ish state on stdout, exit code always 0.
pub fn status(ui: &mut Ui, out: &mut dyn Write, paths: &Paths) -> i32 {
    let color = ui.color();
    let paint = |code: &'static str| if color { code } else { "" };

    let (state, state_color) = if shell::run_success(
        "systemctl",
        &["--user", "is-failed", "--quiet", PROXY_SERVICE],
        true,
    ) {
        ("FAILED", paint(RED))
    } else if shell::run_success(
        "systemctl",
        &["--user", "is-active", "--quiet", PROXY_SERVICE],
        true,
    ) || shell::pgrep("sing-box.*trojan")
    {
        ("RUNNING", paint(GREEN))
    } else {
        ("STOPPED", paint(YELLOW))
    };

    let _ = writeln!(
        out,
        "{}== {}proxy status =={}",
        paint(BOLD),
        paint(CYAN),
        paint(RESET)
    );
    let _ = writeln!(
        out,
        "{:<10} {}{}{}",
        "Service:",
        state_color,
        state,
        paint(RESET)
    );

    let ports = listener_ports();
    if !ports.is_empty() {
        let _ = writeln!(out, "Listeners: {}", ports.join(" "));
    }

    if paths.config.is_file() {
        let parsed = fs::read_to_string(&paths.config)
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok());
        let (nodes, tg) = match &parsed {
            Some(config) => (count_nodes(config), count_tg_nodes(config)),
            None => ("?".to_string(), "?".to_string()),
        };
        let _ = writeln!(
            out,
            "Nodes:     {} outbounds (config: {})",
            nodes,
            stat_age(&paths.config)
        );
        let _ = writeln!(out, "TG:        {} nodes in tg-auto group", tg);
    }

    if state == "RUNNING" {
        let upstream = curl_proxy_code_and_time("https://www.gstatic.com/generate_204", "6");
        let code = upstream.split('|').next().unwrap_or("");
        let time = upstream.rsplit('|').next().unwrap_or("");
        if code == "204" {
            let _ = writeln!(
                out,
                "{:<10} {}OK{} in {}s",
                "Upstream:",
                paint(GREEN),
                paint(RESET),
                time
            );
        } else {
            let _ = writeln!(
                out,
                "{:<10} {}FAIL{} (code {})",
                "Upstream:",
                paint(RED),
                paint(RESET),
                code
            );
        }
        let telegram = curl_proxy_code_and_time("https://api.telegram.org", "8");
        let telegram_code = telegram.split('|').next().unwrap_or("");
        let telegram_time = telegram.rsplit('|').next().unwrap_or("");
        if telegram_code != "000" {
            let _ = writeln!(
                out,
                "{:<10} {}OK{} (HTTP {} in {}s)",
                "Telegram:",
                paint(GREEN),
                paint(RESET),
                telegram_code,
                telegram_time
            );
        } else {
            let _ = writeln!(
                out,
                "{:<10} {}FAIL{}",
                "Telegram:",
                paint(RED),
                paint(RESET)
            );
        }
        // The active-node lookup keeps the shell's hardcoded config prefix.
        if let Some(pid) =
            shell::pgrep_first("sing-box run -c /home/neg/.config").filter(|pid| !pid.is_empty())
        {
            if let Some(connections) = shell::stdout_trimmed("ss", &["-tnp"]) {
                let mut node = None;
                for line in connections.lines() {
                    if !line.contains(&format!("pid={pid}")) {
                        continue;
                    }
                    if ["127.0.0.1", "192.168", "1.1.1.1"]
                        .iter()
                        .any(|needle| line.contains(needle))
                    {
                        continue;
                    }
                    let fields: Vec<&str> = line.split_whitespace().collect();
                    let address = fields.get(2).copied().unwrap_or("");
                    node = Some(strip_trailing_port(address).to_string());
                    break;
                }
                if let Some(node) = node.filter(|node| !node.is_empty()) {
                    let _ = writeln!(out, "Active:    {} (urltest pick)", node);
                }
            }
        }
    }

    if shell::run_success("systemctl", &["is-active", "--quiet", XRAY_SERVICE], true) {
        let _ = writeln!(out, "Xray:      RUNNING");
    } else {
        let _ = writeln!(out, "Xray:      stopped");
    }
    let _ = out.flush();
    0
}

/// `proxy run <cmd...>`: export the socks proxy variables and exec the command.
pub fn run_command(ui: &mut Ui, argv0: &str, args: &[String]) -> i32 {
    if args.is_empty() {
        ui.fail("nothing to run");
        eprintln!("Usage: {argv0} run <command...>");
        return 1;
    }
    let detected =
        shell::run_success(
            "systemctl",
            &["--user", "is-active", "--quiet", PROXY_SERVICE],
            true,
        ) || shell::run_success("systemctl", &["is-active", "--quiet", XRAY_SERVICE], true)
            || shell::pgrep("sing-box run -c");
    if !detected {
        ui.warn(&format!(
            "no proxy detected on {SOCKS_ENDPOINT} — run '{argv0} on' first"
        ));
    }
    let no_proxy = match std::env::var("NO_PROXY") {
        Ok(value) if !value.is_empty() => value,
        _ => "127.0.0.1,localhost".to_string(),
    };

    let mut command = Command::new(&args[0]);
    command.args(&args[1..]);
    for name in [
        "ALL_PROXY",
        "all_proxy",
        "HTTPS_PROXY",
        "https_proxy",
        "HTTP_PROXY",
        "http_proxy",
    ] {
        command.env(name, PROXY_URL);
    }
    command.env("NO_PROXY", &no_proxy);
    command.env("no_proxy", &no_proxy);

    ui.say(&format!("via {PROXY_URL}: {}", args.join(" ")));
    let error = command.exec();
    eprintln!("{argv0}: {}: {error}", args[0]);
    127
}
