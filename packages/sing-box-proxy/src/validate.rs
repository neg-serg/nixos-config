//! `validate_nodes`: TCP reachability scan plus an e2e probe of the candidates.
//!
//! Port of the third Python program embedded in the shell script. The probe
//! starts one throwaway sing-box process per candidate (configs under a temp
//! directory), then drives curl through its SOCKS inbound:
//! 1. relay checks (`http://1.1.1.1`, Cloudflare/Google `generate_204`) — any
//!    accepted HTTP status marks the tunnel as relaying TCP;
//! 2. a throughput check (`speed.cloudflare.com`, >= MIN_SPEED B/s) because the
//!    free pool is full of relays that pass 204s but cap bulk downloads;
//! 3. a Telegram probe (api.telegram.org) that classifies the node as
//!    telegram-capable; `refresh` passes that subset to the generator.
//!
//! Environment knobs keep their shell names: `E2E_CAP`, `MIN_WORKING`,
//! `VALIDATE_TMP` (see `paths::validate_tmp_dir`), `MIN_SPEED`, `SPEED_BYTES`,
//! `SPEED_TIMEOUT`; malformed values fall back to the defaults instead of
//! crashing like `int()` did.
//!
//! Deviations from the Python original: the probe children are stopped with
//! SIGKILL at the terminate point instead of SIGTERM followed by SIGKILL one
//! second later (the shell's outcome is identical for sing-box), and internal
//! I/O failures are reported as an error line + exit 1 instead of a python
//! traceback.

use crate::jsonout::to_python_json;
use crate::nodes::{parse_addr, parse_line, ParserMode};
use crate::output::Ui;
use crate::random::shuffle;
use crate::shell;
use serde_json::json;
use std::collections::{BTreeMap, HashMap};
use std::env;
use std::fs;
use std::io;
use std::net::{TcpStream, ToSocketAddrs};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc;
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

/// `(host, port, proto)` — ordering matches python's tuple sort.
pub type Key = (String, i64, String);

const UDP_PROTOCOLS: [&str; 4] = ["hysteria", "hysteria2", "hy2", "tuic"];
const RELAY_STATUSES: [&str; 5] = ["204", "301", "302", "200", "403"];

#[derive(Debug, Clone)]
pub struct ValidateOptions {
    pub e2e_cap: usize,
    pub min_working: usize,
    pub min_speed: u64,
    pub speed_bytes: u64,
    pub speed_timeout: u64,
    pub tcp_timeout: Duration,
    pub probe_base_port: usize,
    pub tmp_dir: PathBuf,
}

impl Default for ValidateOptions {
    fn default() -> Self {
        Self {
            e2e_cap: 150,
            min_working: 3,
            min_speed: 100_000,
            speed_bytes: 2_000_000,
            speed_timeout: 12,
            tcp_timeout: Duration::from_millis(2500),
            probe_base_port: 11300,
            tmp_dir: crate::paths::validate_tmp_dir(),
        }
    }
}

fn env_number<T: std::str::FromStr>(name: &str, default: T) -> T {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

impl ValidateOptions {
    pub fn from_env() -> Self {
        let default = Self::default();
        Self {
            e2e_cap: env_number("E2E_CAP", default.e2e_cap),
            min_working: env_number("MIN_WORKING", default.min_working),
            min_speed: env_number("MIN_SPEED", default.min_speed),
            speed_bytes: env_number("SPEED_BYTES", default.speed_bytes),
            speed_timeout: env_number("SPEED_TIMEOUT", default.speed_timeout),
            ..default
        }
    }
}

pub struct ValidateOutcome {
    /// Working node URIs, in candidate order (the shell printed these to stdout).
    pub working: Vec<String>,
    /// Telegram-capable subset (same order).
    pub tg_working: Vec<String>,
    pub exit_code: i32,
}

pub fn validate_nodes(text: &str, options: &ValidateOptions, ui: &mut Ui) -> ValidateOutcome {
    if !shell::command_exists("sing-box") {
        ui.raw("✗ ERROR: sing-box not found in PATH");
        return failure();
    }

    let mut candidates: BTreeMap<Key, (String, String)> = BTreeMap::new();
    for raw_line in text.trim().split('\n') {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        if let Some((host, port, proto)) = parse_addr(line) {
            candidates
                .entry((host, port, proto.clone()))
                .or_insert_with(|| (proto, line.to_string()));
        }
    }
    if candidates.is_empty() {
        ui.raw("✗ ERROR: no parseable candidates");
        return failure();
    }
    let keys: Vec<Key> = candidates.keys().cloned().collect();
    ui.raw(format!(":: candidates: {}", keys.len()));

    let tcp_keys: Vec<Key> = keys
        .iter()
        .filter(|key| !UDP_PROTOCOLS.contains(&candidates[key].0.as_str()))
        .cloned()
        .collect();
    let udp_keys: Vec<Key> = keys
        .iter()
        .filter(|key| UDP_PROTOCOLS.contains(&candidates[key].0.as_str()))
        .cloned()
        .collect();
    ui.raw(format!(
        ":: tcp-scan: {} tcp, {} udp (skipped)",
        tcp_keys.len(),
        udp_keys.len()
    ));

    let scan_results = scan_tcp(&tcp_keys, options.tcp_timeout);
    let mut open_keys: Vec<Key> = tcp_keys
        .iter()
        .zip(scan_results.iter())
        .filter(|(_, open)| **open)
        .map(|(key, _)| key.clone())
        .collect();
    open_keys.extend(udp_keys.iter().cloned());
    ui.raw(format!(
        ":: tcp open: {}/{} (udp auto-included)",
        open_keys.len(),
        keys.len()
    ));
    if open_keys.is_empty() {
        ui.raw("✗ ERROR: no reachable nodes");
        return failure();
    }

    shuffle(&mut open_keys);
    let probe_candidates: Vec<Key> = open_keys
        .iter()
        .take(options.e2e_cap)
        .filter(|key| parse_line(&candidates[key].1, ParserMode::Probe).is_some())
        .cloned()
        .collect();
    ui.raw(format!(
        ":: e2e: probing up to {} open nodes (relay + throughput)...",
        probe_candidates.len()
    ));

    if let Err(err) = prepare_tmp_dir(&options.tmp_dir) {
        ui.raw(format!("✗ ERROR: cannot prepare probe directory: {err}"));
        return failure();
    }

    let mut processes: Vec<Child> = Vec::new();
    let t0 = Instant::now();
    let mut probed = 0usize;
    let mut working = 0usize;
    let mut results: HashMap<Key, Option<&'static str>> = HashMap::new();

    let mut wave_start = 0usize;
    while wave_start < probe_candidates.len() {
        let wave_end = (wave_start + 20).min(probe_candidates.len());
        let wave = &probe_candidates[wave_start..wave_end];
        for (offset, key) in wave.iter().enumerate() {
            let port = options.probe_base_port + wave_start + offset;
            let path = options.tmp_dir.join(format!("probe-{port}.json"));
            if let Err(err) = write_probe_config(&candidates[key].1, port, &path) {
                kill_probes(&mut processes);
                pkill_probes(&options.tmp_dir);
                ui.raw(format!("✗ ERROR: cannot write probe config: {err}"));
                return failure();
            }
            let spawn = std::process::Command::new("setsid")
                .arg("sing-box")
                .arg("run")
                .arg("-c")
                .arg(&path)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn();
            match spawn {
                Ok(child) => processes.push(child),
                Err(err) => {
                    kill_probes(&mut processes);
                    pkill_probes(&options.tmp_dir);
                    ui.raw(format!("✗ ERROR: cannot start sing-box probe: {err}"));
                    return failure();
                }
            }
        }

        shell::sleep_secs(8);

        let ports: Vec<usize> = (0..wave.len())
            .map(|offset| options.probe_base_port + wave_start + offset)
            .collect();
        let (sender, receiver) = mpsc::channel::<(usize, Option<&'static str>)>();
        thread::scope(|scope| {
            for (offset, port) in ports.iter().enumerate() {
                let sender = sender.clone();
                let port = *port;
                let options = &*options;
                scope.spawn(move || {
                    let _ = sender.send((offset, probe_port(port, options)));
                });
            }
        });
        drop(sender);

        for _ in 0..wave.len() {
            let Ok((offset, result)) = receiver.recv() else {
                break;
            };
            probed += 1;
            if result.is_some() {
                working += 1;
            }
            results.insert(wave[offset].clone(), result);
            ui.progress(
                &format!(
                    "  e2e: {}/{} probed, {} relay+speed OK ({}s)",
                    probed,
                    probe_candidates.len(),
                    working,
                    t0.elapsed().as_secs()
                ),
                false,
            );
        }
        ui.progress("", true);

        stop_probes(&mut processes);
        wave_start = wave_end;
    }

    kill_probes(&mut processes);
    pkill_probes(&options.tmp_dir);

    let work: Vec<Key> = probe_candidates
        .iter()
        .filter(|key| results.get(*key).is_some_and(Option::is_some))
        .cloned()
        .collect();
    let tg_work: Vec<Key> = probe_candidates
        .iter()
        .filter(|key| results.get(*key) == Some(&Some("tg")))
        .cloned()
        .collect();
    ui.raw(format!(
        "✓ e2e working: {}/{}",
        work.len(),
        probe_candidates.len()
    ));
    if work.is_empty() {
        ui.raw("✗ ERROR: no working nodes; keeping existing config");
        return failure();
    }
    if work.len() < options.min_working {
        ui.raw(format!(
            "! only {} working nodes (wanted >= {}); proceeding with verified subset",
            work.len(),
            options.min_working
        ));
    }

    let working: Vec<String> = work.iter().map(|key| candidates[key].1.clone()).collect();
    let tg_working: Vec<String> = tg_work
        .iter()
        .map(|key| candidates[key].1.clone())
        .collect();

    if !tg_working.is_empty() {
        let tg_path = options.tmp_dir.join("tg-working.txt");
        let body = format!("{}\n", tg_working.join("\n"));
        if let Err(err) = fs::write(&tg_path, body) {
            ui.raw(format!("✗ ERROR: cannot write Telegram node list: {err}"));
            return failure();
        }
        ui.raw(format!(
            "✓ Telegram-capable: {}/{}",
            tg_working.len(),
            working.len()
        ));
    } else {
        ui.raw("! no Telegram-capable nodes (telegram routing will degrade)");
    }

    ValidateOutcome {
        working,
        tg_working,
        exit_code: 0,
    }
}

fn failure() -> ValidateOutcome {
    ValidateOutcome {
        working: Vec::new(),
        tg_working: Vec::new(),
        exit_code: 1,
    }
}

fn prepare_tmp_dir(path: &Path) -> io::Result<()> {
    if path.exists() {
        if path.is_dir() {
            return Ok(());
        }
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            format!("{} is not a directory", path.display()),
        ));
    }
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
}

/// `probe_cfg()`: one throwaway sing-box config with a single node outbound.
fn write_probe_config(node_line: &str, port: usize, path: &Path) -> io::Result<()> {
    let outbound = parse_line(node_line, ParserMode::GenConfig)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "node does not parse"))?;
    let config = json!({
        "log": {"level": "error"},
        "dns": {
            "servers": [{"tag": "remote", "type": "https", "server": "1.1.1.1", "server_port": 443}],
            "strategy": "ipv4_only"
        },
        "inbounds": [{
            "type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": port
        }],
        "outbounds": [outbound, {"type": "direct", "tag": "direct"}],
        "route": {"final": "node", "default_domain_resolver": "remote"}
    });
    fs::write(path, to_python_json(&config))
}

fn scan_tcp(keys: &[Key], timeout: Duration) -> Vec<bool> {
    let results = Mutex::new(vec![false; keys.len()]);
    let next = AtomicUsize::new(0);
    let workers = keys.len().min(300);
    thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let index = next.fetch_add(1, Ordering::Relaxed);
                if index >= keys.len() {
                    break;
                }
                let open = tcp_check(&keys[index].0, keys[index].1, timeout);
                results.lock().unwrap()[index] = open;
            });
        }
    });
    results.into_inner().unwrap()
}

fn tcp_check(host: &str, port: i64, timeout: Duration) -> bool {
    if !(0..=65535).contains(&port) {
        return false;
    }
    let Ok(mut addresses) = (host, port as u16).to_socket_addrs() else {
        return false;
    };
    let Some(address) = addresses.next() else {
        return false;
    };
    TcpStream::connect_timeout(&address, timeout).is_ok()
}

fn curl(args: &[String], timeout_secs: u64) -> Option<std::process::Output> {
    let owned: Vec<std::ffi::OsString> = args.iter().map(std::ffi::OsString::from).collect();
    shell::run_capture(
        "curl",
        &owned,
        Some(Duration::from_secs(timeout_secs)),
        false,
    )
    .ok()
}

fn socks_target(port: usize) -> String {
    format!("127.0.0.1:{port}")
}

/// One candidate probe: relay -> speed -> telegram.
fn probe_port(port: usize, options: &ValidateOptions) -> Option<&'static str> {
    let target = socks_target(port);
    let relay_checks: [Vec<String>; 3] = [
        vec![
            "-sS".into(),
            "-o".into(),
            "/dev/null".into(),
            "-w".into(),
            "%{http_code}".into(),
            "--max-time".into(),
            "6".into(),
            "--socks5".into(),
            target.clone(),
            "http://1.1.1.1".into(),
        ],
        vec![
            "-sS".into(),
            "-o".into(),
            "/dev/null".into(),
            "-w".into(),
            "%{http_code}".into(),
            "--max-time".into(),
            "8".into(),
            "--socks5-hostname".into(),
            target.clone(),
            "https://cp.cloudflare.com/generate_204".into(),
        ],
        vec![
            "-sS".into(),
            "-o".into(),
            "/dev/null".into(),
            "-w".into(),
            "%{http_code}".into(),
            "--max-time".into(),
            "8".into(),
            "--socks5-hostname".into(),
            target.clone(),
            "https://www.gstatic.com/generate_204".into(),
        ],
    ];
    let mut relay_ok = false;
    for args in relay_checks {
        let Some(output) = curl(&args, 15) else {
            continue;
        };
        let code = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if RELAY_STATUSES.contains(&code.as_str()) {
            relay_ok = true;
            break;
        }
    }
    if !relay_ok {
        return None;
    }

    let speed_args = vec![
        "-sS".into(),
        "-o".into(),
        "/dev/null".into(),
        "-w".into(),
        "%{speed_download}".into(),
        "--max-time".into(),
        options.speed_timeout.to_string(),
        "--socks5-hostname".into(),
        target.clone(),
        format!(
            "https://speed.cloudflare.com/__down?bytes={}",
            options.speed_bytes
        ),
    ];
    let output = curl(&speed_args, options.speed_timeout + 5)?;
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let speed: f64 = if text.is_empty() {
        0.0
    } else {
        text.parse().ok()?
    };
    if speed < options.min_speed as f64 {
        return None;
    }

    let telegram_args = vec![
        "-sS".into(),
        "-o".into(),
        "/dev/null".into(),
        "-w".into(),
        "%{http_code}".into(),
        "--max-time".into(),
        "8".into(),
        "--socks5-hostname".into(),
        target,
        "https://api.telegram.org".into(),
    ];
    let telegram_ok = match curl(&telegram_args, 12) {
        Some(output) => {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            output.status.success()
                && !text.is_empty()
                && text.chars().all(|ch| ch.is_ascii_digit())
        }
        None => false,
    };
    Some(if telegram_ok { "tg" } else { "ok" })
}

/// SIGKILL on the terminate step (see the module notes); the second `kill` of
/// the shell becomes a no-op because the children are already reaped.
fn kill_probes(processes: &mut [Child]) {
    for child in processes.iter_mut() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

fn stop_probes(processes: &mut Vec<Child>) {
    kill_probes(processes);
    shell::sleep_secs(1);
    processes.clear();
    shell::sleep_secs(1);
}

fn pkill_probes(tmp: &Path) {
    let pattern = format!("sing-box.*{}", tmp.display());
    let args = [
        std::ffi::OsString::from("-f"),
        std::ffi::OsString::from(pattern),
    ];
    let _ = shell::run_capture("pkill", &args, None, false);
}
