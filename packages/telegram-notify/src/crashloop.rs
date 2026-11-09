//! Crash-loop scanner: alert when a systemd unit restarts too often.
//!
//! Every run compares `NRestarts` against the previous scan and alerts when a
//! unit grew by at least [`CRASH_THRESHOLD`] restarts, at most once per hour
//! per unit. Both systemd managers are watched — a crash-looping system unit
//! and a crash-looping user unit are equally interesting — and only units
//! systemd is configured to restart are considered, because a unit with
//! `Restart=no` can never accumulate `NRestarts`.
//!
//! Alerts go to Telegram through the shared `telegram-send` wrapper and are
//! mirrored to the local BBS `alerts` board; the delivery result decides
//! whether the baseline advances, so a failed send retries on the next scan
//! instead of silently marking the burst as handled.
//!
//! Paths and the user manager come from the environment (the unit sets them):
//!   CRASHLOOP_SYSTEMCTL      systemctl binary (default the system one)
//!   CRASHLOOP_USER_MANAGER   `--machine` target for the user manager (e.g. neg@.host)
//!   CRASHLOOP_SENDER         telegram-send wrapper
//!   CRASHLOOP_MINIBBS        minibbs posting helper; empty disables the mirror
//!   CRASHLOOP_STATE_DIR      where state.json lives
//!   CRASHLOOP_NOW            override "now" in epoch seconds (tests only)

#[path = "lib.rs"]
mod shared;

use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

const DEFAULT_SYSTEMCTL: &str = "/run/current-system/sw/bin/systemctl";
const DEFAULT_STATE_DIR: &str = "/var/lib/telegram-crashloop";

/// A unit is crash-looping when `NRestarts` grew by at least this many within
/// one ~5 min scan window, well above any expected single blip
/// (`RestartSec` below 5s allows up to ~60 restarts per 5 min).
const CRASH_THRESHOLD: i64 = 6;
/// Do not re-alert the same unit more than once per hour.
const COOLDOWN_SECONDS: i64 = 60 * 60;
/// Only these restart policies can accumulate `NRestarts`.
const AUTO_RESTART: [&str; 5] = [
    "always",
    "on-failure",
    "on-abnormal",
    "on-abort",
    "on-success",
];

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn state_dir() -> PathBuf {
    PathBuf::from(env_or("CRASHLOOP_STATE_DIR", DEFAULT_STATE_DIR))
}

/// State of one watched unit.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Entry {
    pub last: i64,
    pub next_allowed: i64,
}

/// The whole scanner state: unit key -> entry.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct State {
    pub units: BTreeMap<String, Entry>,
}

impl State {
    /// Load `state.json`; a missing or broken file is an empty state.
    pub fn load(path: &std::path::Path) -> State {
        let Ok(text) = std::fs::read_to_string(path) else {
            return State::default();
        };
        let Some(shared::json::Value::Object(_)) = shared::json::parse(&text) else {
            return State::default();
        };
        let parsed = shared::json::parse(&text).expect("parsed above");
        let mut state = State::default();
        let Some(units) = parsed.get("units") else {
            return state;
        };
        let Some(shared::json::Value::Object(entries)) = Some(units.clone()) else {
            return state;
        };
        for (key, value) in entries {
            state.units.insert(
                key,
                Entry {
                    last: value
                        .get("last")
                        .and_then(shared::json::Value::as_i64)
                        .unwrap_or(0),
                    next_allowed: value
                        .get("next_allowed")
                        .and_then(shared::json::Value::as_i64)
                        .unwrap_or(0),
                },
            );
        }
        state
    }

    /// Write `state.json` atomically: a crash mid-write cannot corrupt it.
    pub fn save(&self, path: &std::path::Path) -> std::io::Result<()> {
        let mut body = String::from("{\n  \"units\": {");
        let mut first = true;
        for (key, entry) in &self.units {
            if first {
                body.push('\n');
                first = false;
            } else {
                body.push_str(",\n");
            }
            body.push_str(&format!(
                "    {:?}: {{\n      \"last\": {},\n      \"next_allowed\": {}\n    }}",
                key, entry.last, entry.next_allowed
            ));
        }
        if !first {
            body.push('\n');
            body.push_str("  ");
        }
        body.push_str("}\n}\n");
        let tmp = path.with_extension("tmp");
        if let Some(parent) = tmp.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(body.as_bytes())?;
        file.sync_all().ok();
        std::fs::rename(&tmp, path)
    }
}

fn systemctl(scope: &str, args: &[&str]) -> String {
    let systemctl = env_or("CRASHLOOP_SYSTEMCTL", DEFAULT_SYSTEMCTL);
    let mut command = Command::new(systemctl);
    if scope == "user" {
        let manager = env_or("CRASHLOOP_USER_MANAGER", "");
        if manager.is_empty() {
            return String::new();
        }
        command.args(["--user", "--machine", &manager]);
    }
    command.args(args).stdin(Stdio::null());
    match command.output() {
        Ok(output) => String::from_utf8_lossy(&output.stdout).to_string(),
        Err(_) => String::new(),
    }
}

/// Unit names of the running services in one scope.
pub fn running_units(scope: &str) -> Vec<String> {
    let stdout = systemctl(
        scope,
        &[
            "list-units",
            "--type=service",
            "--state=running",
            "--no-legend",
            "--plain",
        ],
    );
    stdout
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .map(str::to_string)
        .collect()
}

/// Restart policy and `NRestarts` for every unit, from one `systemctl show`.
///
/// One call per manager, not one per unit: every `--user --machine` invocation
/// starts a `systemd-stdio-bridge` transient service and a PAM login session
/// (about six journal records), so the per-unit form turned a 5-minute scan
/// into ~70 sessions and dominated the journal on this host.
pub fn restart_states(
    scope: &str,
    units: &[String],
) -> BTreeMap<String, (Option<String>, Option<i64>)> {
    if units.is_empty() {
        return BTreeMap::new();
    }
    let mut args = vec!["show", "-p", "Id", "-p", "Restart", "-p", "NRestarts"];
    args.extend(units.iter().map(String::as_str));
    parse_show(&systemctl(scope, &args))
}

/// Parse the `Id=`/`Restart=`/`NRestarts=` blocks one `systemctl show` prints
/// for several units at once.
fn parse_show(stdout: &str) -> BTreeMap<String, (Option<String>, Option<i64>)> {
    let mut states = BTreeMap::new();
    let mut id: Option<String> = None;
    let mut policy: Option<String> = None;
    let mut nrestarts: Option<i64> = None;

    for line in stdout.lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        match key {
            "Id" => {
                flush_state(&mut id, &mut policy, &mut nrestarts, &mut states);
                id = Some(value.to_string());
            }
            "Restart" => policy = Some(value.to_string()),
            "NRestarts" => nrestarts = value.trim().parse().ok(),
            _ => {}
        }
    }
    flush_state(&mut id, &mut policy, &mut nrestarts, &mut states);
    states
}

/// Store the block accumulated so far, if it had an `Id=`.
fn flush_state(
    id: &mut Option<String>,
    policy: &mut Option<String>,
    nrestarts: &mut Option<i64>,
    states: &mut BTreeMap<String, (Option<String>, Option<i64>)>,
) {
    if let Some(name) = id.take() {
        states.insert(name, (policy.take(), nrestarts.take()));
    }
}

/// System units keep their name; user units get a prefix so a same-named unit
/// in both managers cannot collide.
pub fn unit_key(scope: &str, unit: &str) -> String {
    if scope == "system" {
        unit.to_string()
    } else {
        format!("user:{unit}")
    }
}

/// Copy the alert onto the local BBS board (best effort, never fatal).
fn mirror_to_board(text: &str) {
    let helper = env_or("CRASHLOOP_MINIBBS", "");
    if helper.is_empty() {
        return;
    }
    let mut command = Command::new(helper);
    command
        .args(["alerts", "crashloop"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null());
    match command.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(text.as_bytes());
            }
            let _ = child.wait();
        }
        Err(exc) => eprintln!("crashloop: board mirror failed: {exc}"),
    }
}

/// Deliver one alert; `true` only on an actual successful delivery.
fn send_alert(text: &str) -> bool {
    mirror_to_board(text);
    let sender = env_or("CRASHLOOP_SENDER", "telegram-send");
    match Command::new(sender).arg(text).status() {
        Ok(status) if status.success() => true,
        Ok(_) => {
            eprintln!("crashloop: could not deliver alert");
            false
        }
        Err(exc) => {
            eprintln!("crashloop: sender error: {exc}");
            false
        }
    }
}

fn now() -> i64 {
    if let Ok(value) = std::env::var("CRASHLOOP_NOW") {
        if let Ok(parsed) = value.trim().parse::<i64>() {
            return parsed;
        }
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_secs() as i64)
        .unwrap_or(0)
}

fn main() -> std::process::ExitCode {
    let current = now();
    let path = state_dir().join("state.json");
    let mut state = State::load(&path);
    let mut changed = false;

    for scope in ["system", "user"] {
        let units = running_units(scope);
        let mut states = restart_states(scope, &units);
        for unit in units {
            let Some((policy, nrestarts)) = states.remove(&unit) else {
                continue;
            };
            let Some(policy) = policy else { continue };
            if !AUTO_RESTART.contains(&policy.as_str()) {
                continue;
            }
            let Some(nrestarts) = nrestarts else { continue };
            let key = unit_key(scope, &unit);

            let Some(entry) = state.units.get(&key).cloned() else {
                // First observation: baseline it, never alert on first sight of
                // an already-restarted unit.
                state.units.insert(
                    key,
                    Entry {
                        last: nrestarts,
                        next_allowed: 0,
                    },
                );
                changed = true;
                continue;
            };

            // Counter reset (stop/reload/reboot): adopt the lower value as the
            // new baseline without alerting, so real restarts are not missed
            // across a reset.
            if nrestarts <= entry.last {
                if nrestarts != entry.last {
                    state.units.insert(
                        key,
                        Entry {
                            last: nrestarts,
                            next_allowed: entry.next_allowed,
                        },
                    );
                    changed = true;
                }
                continue;
            }

            let delta = nrestarts - entry.last;
            if delta >= CRASH_THRESHOLD && current >= entry.next_allowed {
                let text =
                    format!("🔄 crash-loop: {key}: {delta} restarts in 5 min ({nrestarts} total)");
                println!("crashloop: alert {text}");
                if send_alert(&text) {
                    state.units.insert(
                        key,
                        Entry {
                            last: nrestarts,
                            next_allowed: current + COOLDOWN_SECONDS,
                        },
                    );
                    changed = true;
                } else {
                    // Delivery failed: keep the baseline so the next scan
                    // retries, and never mark the burst as handled.
                    eprintln!("crashloop: send failed for {key}, will retry next scan");
                }
            } else {
                // Below threshold or inside the cooldown: adopt the counter so a
                // sustained crash-loop re-alerts with a fresh delta later, but
                // never accumulates into a giant stale number.
                state.units.insert(
                    key,
                    Entry {
                        last: nrestarts,
                        next_allowed: entry.next_allowed,
                    },
                );
                changed = true;
            }
        }
    }

    if changed {
        if let Err(exc) = state.save(&path) {
            eprintln!("crashloop: cannot write {}: {exc}", path.display());
        }
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "crashloop-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|delta| delta.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    #[test]
    fn state_round_trips_through_json() {
        let dir = temp_dir("state");
        let path = dir.join("state.json");
        let mut state = State::default();
        state.units.insert(
            "user:koito".to_string(),
            Entry {
                last: 7,
                next_allowed: 1_760_000_000,
            },
        );
        state.units.insert("mpd".to_string(), Entry::default());
        state.save(&path).expect("save");
        assert_eq!(State::load(&path), state);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn broken_state_is_empty() {
        let dir = temp_dir("broken");
        let path = dir.join("state.json");
        std::fs::write(&path, "{not json").unwrap();
        assert_eq!(State::load(&path), State::default());
        assert_eq!(State::load(&dir.join("missing.json")), State::default());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn user_units_get_a_prefix() {
        assert_eq!(unit_key("system", "koito.service"), "koito.service");
        assert_eq!(unit_key("user", "koito.service"), "user:koito.service");
    }

    #[test]
    fn show_output_is_parsed_per_unit() {
        let stdout = "\
Id=mpd.service
Restart=always
NRestarts=3

Id=dbus-broker.service
Restart=no
NRestarts=0

Id=broken.service
Restart=on-failure
NRestarts=not-a-number
";
        let states = parse_show(stdout);
        assert_eq!(
            states.get("mpd.service"),
            Some(&(Some("always".to_string()), Some(3)))
        );
        assert_eq!(
            states.get("dbus-broker.service"),
            Some(&(Some("no".to_string()), Some(0)))
        );
        assert_eq!(
            states.get("broken.service"),
            Some(&(Some("on-failure".to_string()), None))
        );
        assert_eq!(states.get("missing.service"), None);
    }
}
