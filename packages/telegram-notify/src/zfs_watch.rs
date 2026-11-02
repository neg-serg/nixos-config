//! ZFS/NVMe watchdog: message the chat when a pool, the snapshots or a drive
//! changes state.
//!
//! The watcher only reports *transitions* (a problem appearing, a pool
//! recovering, a scrub finishing), so a standing fault does not turn into a
//! daily nag. `CHECK_VERSION` guards the meaning of the checks themselves: the
//! first run after an upgrade only re-baselines, which keeps a fixed false
//! positive from producing a fake "recovered" notice.
//!
//! Checks:
//!   * `zpool status` — overall state, per-vdev error counters, faulted states,
//!     and the newest scrub result;
//!   * snapshots — the sanoid datasets must exist, have a fresh snapshot, and
//!     not pin more space than the pool can spare;
//!   * NVMe SMART — critical warning, temperature, spare reserve, wear and
//!     media errors, read straight from the drives because smartd is off here.
//!
//! Everything is configurable through the environment (the unit sets it):
//!   ZFS_WATCH_STATE_FILE, ZFS_WATCH_STATE_DIR
//!   ZFS_WATCH_ZPOOL, ZFS_WATCH_ZFS, ZFS_WATCH_NVME, ZFS_WATCH_SENDER
//!   ZFS_WATCH_NVME_GLOB, ZFS_WATCH_SNAPSHOT_DATASETS (space separated)
//!   ZFS_WATCH_NVME_MAX_TEMP_C, ZFS_WATCH_NVME_MIN_SPARE,
//!   ZFS_WATCH_NVME_MAX_USED, ZFS_WATCH_SNAPSHOT_MAX_AGE_HOURS,
//!   ZFS_WATCH_USEDSNAP_PERCENT, ZFS_WATCH_NOW (epoch seconds, tests only)

#[path = "lib.rs"]
mod shared;

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use shared::json::Value;

const DEFAULT_ZPOOL: &str = "/run/current-system/sw/bin/zpool";
const DEFAULT_ZFS: &str = "/run/current-system/sw/bin/zfs";
const DEFAULT_STATE_DIR: &str = "/var/lib/telegram-zfs-watch";
const DEFAULT_STATE_FILE: &str = "/var/lib/telegram-zfs-watch/state.json";
/// Bump when a check changes meaning: the first run after an upgrade only
/// re-baselines.
const CHECK_VERSION: i64 = 2;
const DEFAULT_NVME_MAX_TEMP_C: f64 = 75.0;
const DEFAULT_NVME_MIN_SPARE: f64 = 10.0;
const DEFAULT_NVME_MAX_USED: f64 = 90.0;
const DEFAULT_SNAPSHOT_MAX_AGE_HOURS: f64 = 3.0;
const DEFAULT_USEDSNAP_PERCENT: f64 = 20.0;

/// vdev states that indicate a fault even with zero error counters.
const FAULT_STATES: [&str; 5] = ["DEGRADED", "FAULTED", "OFFLINE", "UNAVAIL", "REMOVED"];

/// User-facing problem text. The Python script kept these as `\u` escapes so
/// the source stayed ASCII; the same escapes are used here.
const MSG_DATASET_MISSING: &str = "\u{434}\u{430}\u{442}\u{430}\u{441}\u{435}\u{442} \u{43e}\u{442}\u{441}\u{443}\u{442}\u{441}\u{442}\u{432}\u{443}\u{435}\u{442}"; // "датасет отсутствует"
const MSG_NO_SNAPSHOTS: &str =
    "\u{43d}\u{435}\u{442} \u{441}\u{43d}\u{430}\u{43f}\u{448}\u{43e}\u{442}\u{43e}\u{432}"; // "нет снапшотов"
const MSG_LAST_SNAPSHOT_HOURS: &str = "\u{43f}\u{43e}\u{441}\u{43b}\u{435}\u{434}\u{43d}\u{438}\u{439} \u{441}\u{43d}\u{430}\u{43f}\u{448}\u{43e}\u{442} {:.1} \u{447} \u{43d}\u{430}\u{437}\u{430}\u{434}"; // "последний снапшот {} ч назад"
const MSG_USEDSNAP_FREE: &str = "\u{441}\u{432}\u{43e}\u{431}\u{43e}\u{434}\u{43d}\u{43e}\u{433}\u{43e} \u{43c}\u{435}\u{441}\u{442}\u{430}"; // "свободного места"

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

/// Python's `{:g}`: the shortest representation without a trailing `.0`.
fn fmt_g(value: f64) -> String {
    format!("{value}")
}

fn env_f64(name: &str, fallback: f64) -> f64 {
    env_or(name, &fallback.to_string())
        .trim()
        .parse()
        .unwrap_or(fallback)
}

fn state_file() -> PathBuf {
    PathBuf::from(env_or("ZFS_WATCH_STATE_FILE", DEFAULT_STATE_FILE))
}

fn state_dir() -> PathBuf {
    PathBuf::from(env_or("ZFS_WATCH_STATE_DIR", DEFAULT_STATE_DIR))
}

fn now_epoch() -> f64 {
    if let Ok(value) = std::env::var("ZFS_WATCH_NOW") {
        if let Ok(parsed) = value.trim().parse::<f64>() {
            return parsed;
        }
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs_f64())
        .unwrap_or(0.0)
}

/// Run a command, returning stdout on success.
fn run_cmd(argv: &[&str]) -> Option<String> {
    let output = Command::new(argv[0])
        .args(&argv[1..])
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).to_string())
}

fn zpool() -> String {
    env_or("ZFS_WATCH_ZPOOL", DEFAULT_ZPOOL)
}

fn zfs() -> String {
    env_or("ZFS_WATCH_ZFS", DEFAULT_ZFS)
}

fn zfs_watch() -> String {
    format!("{}-watch", "")
}

pub fn list_pools() -> Vec<String> {
    let pool = zpool();
    let Some(out) = run_cmd(&[&pool, "list", "-H", "-o", "name"]) else {
        return Vec::new();
    };
    out.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect()
}

fn month_number(name: &str) -> Option<i64> {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    MONTHS
        .iter()
        .position(|month| *month == name)
        .map(|index| index as i64 + 1)
}

/// Comparable tuple for a `zpool` scan date (`%c`: `Sat Sep  5 01:35:33 2026`).
pub fn scrub_key(date: &str) -> Option<(i64, i64, i64, i64, i64, i64)> {
    let normalised: String = date.split_whitespace().collect::<Vec<_>>().join(" ");
    // `Sat Sep 5 01:35:33 2026`: weekday, month, day, time, year.
    let fields: Vec<&str> = normalised.split(' ').collect();
    if fields.len() != 5 {
        return None;
    }
    let month = month_number(fields[1])?;
    let day: i64 = fields[2].parse().ok()?;
    let mut time = fields[3].split(':');
    let hour: i64 = time.next()?.parse().ok()?;
    let minute: i64 = time.next()?.parse().ok()?;
    let second: i64 = time.next()?.parse().ok()?;
    let year: i64 = fields[4].parse().ok()?;
    Some((year, month, day, hour, minute, second))
}

/// `(overall_state, problems, last_scrub)` from `zpool status <pool>`.
pub fn parse_status(text: &str) -> (Option<String>, Vec<String>, Option<(i64, String)>) {
    let mut state = None;
    let mut problems = Vec::new();
    let mut scan: Option<String> = None;
    let mut in_config = false;
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        if let Some(value) = line.strip_prefix("state: ") {
            state = Some(value.trim().to_string());
        }
        if line.starts_with("scan:") {
            scan = Some(line.to_string());
        }
        if line.starts_with("config:") {
            in_config = true;
            continue;
        }
        if line.starts_with("errors:")
            || line.starts_with("actions:")
            || line.starts_with("status:")
            || line.starts_with("scrub:")
        {
            in_config = false;
        }
        if !in_config {
            continue;
        }
        let tokens: Vec<&str> = line.split_whitespace().collect();
        if tokens.is_empty() || tokens[0] == "NAME" {
            continue; // table header
        }
        // A real vdev row always ends with three numeric error counters.
        if tokens.len() >= 5
            && tokens[tokens.len() - 3..]
                .iter()
                .all(|token| token.chars().all(|ch| ch.is_ascii_digit()))
        {
            let name = tokens[0];
            let vstate = tokens[1];
            let read: i64 = tokens[tokens.len() - 3].parse().unwrap_or(0);
            let write: i64 = tokens[tokens.len() - 2].parse().unwrap_or(0);
            let cksum: i64 = tokens[tokens.len() - 1].parse().unwrap_or(0);
            let mut bits = Vec::new();
            if read != 0 {
                bits.push(format!("read={read}"));
            }
            if write != 0 {
                bits.push(format!("write={write}"));
            }
            if cksum != 0 {
                bits.push(format!("cksum={cksum}"));
            }
            if !bits.is_empty() {
                problems.push(format!("{name}: {}", bits.join(" ")));
            } else if FAULT_STATES.contains(&vstate) {
                problems.push(format!("{name}: state {vstate}"));
            }
        }
    }
    let mut scrub = None;
    if let Some(scan) = scan {
        scrub = parse_scrub(&scan);
    }
    (state, problems, scrub)
}

/// `... scrub repaired 0B in ... with 0 errors on Sat Sep  5 01:35:33 2026`.
fn parse_scrub(scan: &str) -> Option<(i64, String)> {
    let scrub_start = scan.find("scrub")?;
    let tail = &scan[scrub_start..];
    let with = tail.find("with ")?;
    let rest = &tail[with + 5..];
    let mut words = rest.split_whitespace();
    let errors: i64 = words.next()?.parse().ok()?;
    if words.next()? != "errors" || words.next()? != "on" {
        return None;
    }
    let on = rest.find(" on ")? + 4;
    Some((errors, rest[on..].trim().to_string()))
}

pub fn human_bytes(size: f64) -> String {
    let mut value = size;
    for unit in ["B", "K", "M", "G", "T"] {
        if value < 1024.0 || unit == "T" {
            return format!("{value:.1}{unit}");
        }
        value /= 1024.0;
    }
    format!("{value:.1}T")
}

/// Snapshot/free-space problems for one dataset; empty means healthy.
pub fn dataset_problems(dataset: &str, now: f64) -> Vec<String> {
    let zfs_bin = zfs();
    let pool_bin = zpool();
    let exists = Command::new(&zfs_bin)
        .args(["list", "-H", "-o", "name", dataset])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false);
    if !exists {
        return vec![MSG_DATASET_MISSING.to_string()];
    }
    let Some(out) = run_cmd(&[
        &zfs_bin, "list", "-H", "-p", "-d", "1", "-t", "snapshot", "-o", "creation", "-s",
        "creation", dataset,
    ]) else {
        return Vec::new();
    };
    let mut problems = Vec::new();
    let stamps: Vec<i64> = out
        .split_whitespace()
        .filter(|token| token.chars().all(|ch| ch.is_ascii_digit()))
        .filter_map(|token| token.parse().ok())
        .collect();
    let max_age = env_f64(
        "ZFS_WATCH_SNAPSHOT_MAX_AGE_HOURS",
        DEFAULT_SNAPSHOT_MAX_AGE_HOURS,
    );
    if stamps.is_empty() {
        problems.push(MSG_NO_SNAPSHOTS.to_string());
    } else {
        let newest = stamps.iter().copied().max().unwrap_or(0);
        let age = (now - newest as f64) / 3600.0;
        if age > max_age {
            problems.push(MSG_LAST_SNAPSHOT_HOURS.replace("{}", &format!("{age:.1}")));
        }
    }
    let pool = dataset.split('/').next().unwrap_or(dataset);
    let free: i64 = run_cmd(&[&pool_bin, "list", "-H", "-p", "-o", "free", pool])
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0);
    let usedsnap: i64 = run_cmd(&[&zfs_bin, "list", "-H", "-p", "-o", "usedsnap", dataset])
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0);
    let percent = env_f64("ZFS_WATCH_USEDSNAP_PERCENT", DEFAULT_USEDSNAP_PERCENT);
    if free > 0 && usedsnap as f64 > free as f64 * percent / 100.0 {
        problems.push(format!(
            "USEDSNAP {} > {}% {} ({})",
            human_bytes(usedsnap as f64),
            fmt_g(percent),
            MSG_USEDSNAP_FREE,
            human_bytes(free as f64)
        ));
    }
    problems
}

fn number(value: Option<&Value>) -> Option<f64> {
    match value? {
        Value::Number(number) => Some(*number),
        Value::Str(text) => text.trim().parse().ok(),
        _ => None,
    }
}

fn nvme_field<'a>(log: &'a Value, names: &[&str]) -> Option<&'a Value> {
    names.iter().find_map(|name| log.get(name))
}

/// `(problems, info)` from one drive's SMART log.
pub fn nvme_facts(device: &str) -> (Vec<String>, Value) {
    let nvme = env_or("ZFS_WATCH_NVME", "nvme");
    let Some(out) = run_cmd(&[&nvme, "smart-log", "--output-format=json", device]) else {
        return (
            vec!["smart-log cannot be read".to_string()],
            Value::Object(Vec::new()),
        );
    };
    let Some(log) = shared::json::parse(&out) else {
        return (
            vec!["smart-log returned non-JSON".to_string()],
            Value::Object(Vec::new()),
        );
    };
    let mut problems = Vec::new();
    let mut info: Vec<(String, Value)> = Vec::new();
    let critical = number(nvme_field(&log, &["critical_warning"])).unwrap_or(0.0) as i64;
    if critical != 0 {
        problems.push(format!("critical_warning=0x{critical:x}"));
    }
    if let Some(temp) = number(nvme_field(&log, &["temperature"])) {
        // The spec stores the field in Kelvins and nvme-cli passes it through
        // (a healthy idle drive reads ~305 = 32 C); some builds already convert,
        // so only large values are treated as Kelvin.
        let temp_c = if temp > 200.0 { temp - 273.15 } else { temp };
        info.push((
            "temp_c".to_string(),
            Value::Number((temp_c * 10.0).round() / 10.0),
        ));
        let max_temp = env_f64("ZFS_WATCH_NVME_MAX_TEMP_C", DEFAULT_NVME_MAX_TEMP_C);
        if temp_c >= max_temp {
            problems.push(format!("temperature {temp_c:.0}°C"));
        }
    }
    let spare = number(nvme_field(&log, &["available_spare", "avail_spare"]));
    let threshold = number(nvme_field(
        &log,
        &[
            "available_spare_threshold",
            "spare_thresh",
            "avl_spare_threshold",
        ],
    ));
    if let Some(spare) = spare {
        info.push(("spare_percent".to_string(), Value::Number(spare)));
        let min_spare = env_f64("ZFS_WATCH_NVME_MIN_SPARE", DEFAULT_NVME_MIN_SPARE);
        if spare < min_spare || threshold.map(|limit| spare < limit).unwrap_or(false) {
            problems.push(format!("available_spare {}%", fmt_g(spare)));
        }
    }
    if let Some(used) = number(nvme_field(&log, &["percentage_used", "percent_used"])) {
        info.push(("used_percent".to_string(), Value::Number(used)));
        let max_used = env_f64("ZFS_WATCH_NVME_MAX_USED", DEFAULT_NVME_MAX_USED);
        if used >= max_used {
            problems.push(format!("wear {}%", fmt_g(used)));
        }
    }
    let media_errors = number(nvme_field(&log, &["media_errors"])).unwrap_or(0.0) as i64;
    info.push((
        "media_errors".to_string(),
        Value::Number(media_errors as f64),
    ));
    if media_errors != 0 {
        problems.push(format!("media_errors={media_errors}"));
    }
    (problems, Value::Object(info))
}

// -- state -------------------------------------------------------------

fn load_state(path: &Path) -> Value {
    match std::fs::read_to_string(path)
        .ok()
        .and_then(|text| shared::json::parse(&text))
    {
        Some(Value::Object(_)) => {
            shared::json::parse(&std::fs::read_to_string(path).unwrap_or_default())
                .unwrap_or_else(|| Value::Object(vec![("pools".into(), Value::Object(Vec::new()))]))
        }
        _ => Value::Object(vec![("pools".to_string(), Value::Object(Vec::new()))]),
    }
}

fn object(entries: Vec<(String, Value)>) -> Value {
    Value::Object(entries)
}

fn section<'a>(state: &'a Value, key: &str) -> Vec<(String, Value)> {
    match state.get(key) {
        Some(Value::Object(entries)) => entries.clone(),
        _ => Vec::new(),
    }
}

fn entry_ok(entry: Option<&Value>) -> bool {
    match entry.and_then(|value| value.get("ok")) {
        Some(Value::Bool(flag)) => *flag,
        _ => true,
    }
}

fn send_telegram(text: &str) -> bool {
    let sender = env_or("ZFS_WATCH_SENDER", "telegram-send");
    match Command::new(sender).arg(text).status() {
        Ok(status) if status.success() => true,
        _ => {
            eprintln!("zfs-watch: telegram delivery failed for: {text}");
            false
        }
    }
}

fn main() -> std::process::ExitCode {
    let dir = state_dir();
    if let Err(exc) = std::fs::create_dir_all(&dir) {
        eprintln!("zfs-watch: cannot create {}: {exc}", dir.display());
        return std::process::ExitCode::from(1);
    }
    let path = state_file();
    let state = load_state(&path);
    let rebaseline = !matches!(state.get("version"), Some(Value::Number(number)) if *number as i64 == CHECK_VERSION);
    let mut messages: Vec<String> = Vec::new();
    let mut had_pending = false;

    let pools = section(&state, "pools");
    let mut new_pools: Vec<(String, Value)> = Vec::new();
    for pool in list_pools() {
        let bin = zpool();
        let Some(status) = run_cmd(&[&bin, "status", &pool]) else {
            eprintln!("zfs-watch: zpool status {pool} failed");
            continue;
        };
        let (overall, problems, scrub) = parse_status(&status);
        let cur_ok =
            problems.is_empty() && (overall.as_deref() == Some("ONLINE") || overall.is_none());
        let mut fields = vec![
            ("ok".to_string(), Value::Bool(cur_ok)),
            (
                "problems".to_string(),
                Value::Array(
                    problems
                        .iter()
                        .map(|text| Value::Str(text.clone()))
                        .collect(),
                ),
            ),
            (
                "state".to_string(),
                match &overall {
                    Some(text) => Value::Str(text.clone()),
                    None => Value::Null,
                },
            ),
            (
                "scrub".to_string(),
                match &scrub {
                    Some((errors, date)) => object(vec![
                        ("errors".to_string(), Value::Number(*errors as f64)),
                        ("date".to_string(), Value::Str(date.clone())),
                    ]),
                    None => Value::Null,
                },
            ),
        ];
        fields.shrink_to_fit();
        let previous = pools
            .iter()
            .find(|(name, _)| name == &pool)
            .map(|(_, value)| value);
        if let Some(previous) = previous.filter(|_| !rebaseline) {
            let prev_ok = entry_ok(Some(previous));
            if prev_ok && !cur_ok {
                let body = if problems.is_empty() {
                    format!("state {}", overall.clone().unwrap_or_default())
                } else {
                    problems.join("; ")
                };
                messages.push(format!("⚠️ ZFS {pool}: {body}"));
                had_pending = true;
            } else if !prev_ok && cur_ok {
                messages.push(format!("✅ ZFS {pool}: recovered"));
                had_pending = true;
            }
            if let Some((errors, date)) = &scrub {
                if let Some(Value::Object(prev_scrub)) = previous.get("scrub") {
                    let prev_date = prev_scrub
                        .iter()
                        .find(|(name, _)| name == "date")
                        .and_then(|(_, value)| value.as_str())
                        .unwrap_or("");
                    let newer = match (scrub_key(date), scrub_key(prev_date)) {
                        (Some(current), Some(previous)) => current > previous,
                        _ => true,
                    };
                    if prev_date != date && newer {
                        messages.push(format!(
                            "🧹 ZFS scrub {pool} finished: {errors} errors ({date})"
                        ));
                        had_pending = true;
                    }
                }
            }
        }
        new_pools.push((pool, object(fields)));
    }

    let datasets = section(&state, "datasets");
    let mut new_datasets: Vec<(String, Value)> = Vec::new();
    let wanted: Vec<String> = env_or("ZFS_WATCH_SNAPSHOT_DATASETS", "")
        .split_whitespace()
        .map(str::to_string)
        .collect();
    for dataset in wanted {
        let problems = dataset_problems(&dataset, now_epoch());
        let cur_ok = problems.is_empty();
        let previous = datasets
            .iter()
            .find(|(name, _)| name == &dataset)
            .map(|(_, value)| value);
        if let Some(previous) = previous.filter(|_| !rebaseline) {
            let prev_ok = entry_ok(Some(previous));
            if prev_ok && !cur_ok {
                messages.push(format!(
                    "⚠️ ZFS snapshots {dataset}: {}",
                    problems.join("; ")
                ));
                had_pending = true;
            } else if !prev_ok && cur_ok {
                messages.push(format!("✅ ZFS snapshots {dataset}: recovered"));
                had_pending = true;
            }
        }
        new_datasets.push((
            dataset,
            object(vec![
                ("ok".to_string(), Value::Bool(cur_ok)),
                (
                    "problems".to_string(),
                    Value::Array(
                        problems
                            .iter()
                            .map(|text| Value::Str(text.clone()))
                            .collect(),
                    ),
                ),
            ]),
        ));
    }

    let nvmes = section(&state, "nvme");
    let mut new_nvmes: Vec<(String, Value)> = Vec::new();
    let glob = env_or("ZFS_WATCH_NVME_GLOB", "/dev/nvme*n1");
    for device in glob_paths(&glob) {
        let name = device.rsplit('/').next().unwrap_or(&device).to_string();
        let (problems, info) = nvme_facts(&device);
        let cur_ok = problems.is_empty();
        let previous = nvmes
            .iter()
            .find(|(candidate, _)| candidate == &name)
            .map(|(_, value)| value);
        if let Some(previous) = previous.filter(|_| !rebaseline) {
            let prev_ok = entry_ok(Some(previous));
            if prev_ok && !cur_ok {
                messages.push(format!("⚠️ NVMe {name}: {}", problems.join("; ")));
                had_pending = true;
            } else if !prev_ok && cur_ok {
                messages.push(format!("✅ NVMe {name}: recovered"));
                had_pending = true;
            }
        }
        new_nvmes.push((
            name,
            object(vec![
                ("ok".to_string(), Value::Bool(cur_ok)),
                (
                    "problems".to_string(),
                    Value::Array(
                        problems
                            .iter()
                            .map(|text| Value::Str(text.clone()))
                            .collect(),
                    ),
                ),
                ("info".to_string(), info),
            ]),
        ));
    }

    // Deliver everything. If any transition/scrub message cannot be delivered,
    // keep the previous state so the same transition is retried next run
    // (no loss, still no spam) instead of being swallowed.
    let delivered = messages.iter().all(|message| send_telegram(message));
    if !had_pending || delivered {
        let updated = object(vec![
            ("version".to_string(), Value::Number(CHECK_VERSION as f64)),
            ("pools".to_string(), object(new_pools)),
            ("datasets".to_string(), object(new_datasets)),
            ("nvme".to_string(), object(new_nvmes)),
        ]);
        if let Err(exc) = std::fs::write(&path, updated.dump(Some(2))) {
            eprintln!("zfs-watch: cannot write {}: {exc}", path.display());
            return std::process::ExitCode::from(1);
        }
    }
    std::process::ExitCode::SUCCESS
}

/// Expand a `/dev/nvme*n1` style pattern by listing the directory. The Python
/// used `glob.glob`, so the same simple `*`/`?` matching is enough here.
fn glob_paths(pattern: &str) -> Vec<String> {
    let (dir, file_pattern) = match pattern.rsplit_once('/') {
        Some((dir, rest)) => (dir.to_string(), rest.to_string()),
        None => (".".to_string(), pattern.to_string()),
    };
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return Vec::new();
    };
    let mut matches: Vec<String> = entries
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().to_string())
        .filter(|name| glob_match(&file_pattern, name))
        .map(|name| format!("{dir}/{name}"))
        .collect();
    matches.sort();
    matches
}

fn glob_match(pattern: &str, name: &str) -> bool {
    let pattern: Vec<char> = pattern.chars().collect();
    let name: Vec<char> = name.chars().collect();
    let mut state = vec![(0usize, 0usize)];
    let mut seen = std::collections::BTreeSet::new();
    while let Some((mut p, mut n)) = state.pop() {
        if !seen.insert((p, n)) {
            continue;
        }
        loop {
            if p == pattern.len() {
                if n == name.len() {
                    return true;
                }
                break;
            }
            match pattern[p] {
                '*' => {
                    state.push((p + 1, n));
                    if n < name.len() {
                        state.push((p, n + 1));
                    }
                    break;
                }
                '?' => {
                    if n < name.len() {
                        p += 1;
                        n += 1;
                    } else {
                        break;
                    }
                }
                ch => {
                    if n < name.len() && name[n] == ch {
                        p += 1;
                        n += 1;
                    } else {
                        break;
                    }
                }
            }
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_text_yields_state_problems_and_scrub() {
        let text = "\
  pool: tank
 state: ONLINE
  scan: scrub repaired 0B in 02:13:41 with 0 errors on Sat Sep  5 01:35:33 2026
config:

        NAME        STATE     READ WRITE CKSUM
        tank        ONLINE       0     0     0
          sda       ONLINE       0     0     0
          sdb       ONLINE       2     0    16

errors: No known data errors
";
        let (state, problems, scrub) = parse_status(text);
        assert_eq!(state.as_deref(), Some("ONLINE"));
        assert_eq!(problems, vec!["sdb: read=2 cksum=16"]);
        assert_eq!(scrub, Some((0, "Sat Sep  5 01:35:33 2026".to_string())));
    }

    #[test]
    fn faulted_vdev_with_clean_counters_is_reported() {
        let text = "\
 state: DEGRADED
config:
        NAME        STATE     READ WRITE CKSUM
        tank        DEGRADED     0     0     0
          sdc       UNAVAIL      0     0     0

errors: No known data errors
";
        let (state, problems, _) = parse_status(text);
        assert_eq!(state.as_deref(), Some("DEGRADED"));
        // The pool row itself carries the degraded state, exactly as the
        // Python parser reported it.
        assert_eq!(problems, vec!["tank: state DEGRADED", "sdc: state UNAVAIL"]);
    }

    #[test]
    fn scrub_dates_are_orderable() {
        assert_eq!(
            scrub_key("Sat Sep  5 01:35:33 2026"),
            Some((2026, 9, 5, 1, 35, 33))
        );
        assert!(scrub_key("garbage").is_none());
        assert!(scrub_key("Sun Oct 12 23:00:00 2026") > scrub_key("Sat Sep  5 01:35:33 2026"));
    }

    #[test]
    fn bytes_are_humanised() {
        assert_eq!(human_bytes(0.0), "0.0B");
        assert_eq!(human_bytes(1023.0), "1023.0B");
        assert_eq!(human_bytes(2048.0), "2.0K");
        assert_eq!(human_bytes(1024.0 * 1024.0 * 1024.0 * 3.0), "3.0G");
    }

    #[test]
    fn globs_match_devices() {
        assert!(glob_match("nvme*n1", "nvme0n1"));
        assert!(glob_match("nvme*n1", "nvme2n1"));
        assert!(!glob_match("nvme*n1", "nvme0n2"));
        assert!(glob_match("nvme?n1", "nvme0n1"));
    }
}
