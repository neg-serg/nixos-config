//! Config generation and the bootstrap "heal an existing config" patcher.
//!
//! `build_config` is the port of `gen_cfg`'s Python body; `patch_config` is the
//! port of the bootstrap patcher. Both reproduce the original JSON key order
//! (serde_json's `preserve_order` plus `jsonout`) and the original defaults.

use crate::jsonout::to_python_json;
use crate::nodes::{self, ParserMode};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub const TG_CIDRS: [&str; 8] = [
    "91.108.4.0/22",
    "91.108.8.0/22",
    "91.108.12.0/22",
    "91.108.16.0/22",
    "91.108.56.0/22",
    "95.161.64.0/20",
    "149.154.160.0/20",
    "185.76.151.0/24",
];

pub fn final_dns() -> Value {
    json!({
        "servers": [
            {"tag": "remote", "type": "https", "server": "1.1.1.1", "server_port": 443}
        ],
        "strategy": "prefer_ipv4"
    })
}

pub fn final_route() -> Value {
    json!({
        "rules": [
            {"ip_is_private": true, "outbound": "direct"},
            {
                "domain_suffix": ["telegram.org", "t.me", "telegram.me", "telegram.dog"],
                "outbound": "tg-auto"
            },
            {"ip_cidr": TG_CIDRS, "outbound": "tg-auto"},
            {
                "domain_suffix": ["deepseek.com", "deepseek.cn"],
                "action": "route",
                "outbound": "auto"
            },
            {"action": "resolve", "server": "remote", "strategy": "prefer_ipv4"}
        ],
        "final": "auto",
        "auto_detect_interface": true,
        "default_domain_resolver": "remote"
    })
}

pub struct BuildOutcome {
    pub config: Option<Value>,
    /// stderr lines the generator emitted, in order (plain `log()` lines).
    pub logs: Vec<String>,
    pub exit_code: i32,
    pub node_count: usize,
    pub tg_count: usize,
}

/// `gen_cfg`'s Python body: parse the node list and build the sing-box config.
///
/// `nodes_text` is the content of `NODES_FILE` (or `NODES_TEXT`), `tg_nodes_text`
/// the content of `TG_NODES_FILE` (empty when absent), `lan_auth` the trimmed
/// content of the LAN secret (`""` when absent).
pub fn build_config(nodes_text: &str, tg_nodes_text: &str, lan_auth: &str) -> BuildOutcome {
    let mut logs = Vec::new();
    let mut outbounds: Vec<Value> = Vec::new();
    let mut seen: HashSet<(String, i64, String)> = HashSet::new();
    let mut tag_by_key: HashMap<(String, i64, String), String> = HashMap::new();

    for raw_line in nodes_text.trim().split('\n') {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let Some(mut outbound) = nodes::parse_line(line, ParserMode::GenConfig) else {
            continue;
        };
        let canonical = line.split('#').next().unwrap_or("").trim().to_string();
        let server = outbound
            .get("server")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_lowercase();
        let port = outbound
            .get("server_port")
            .and_then(Value::as_i64)
            .unwrap_or(0);
        let key = (server, port, canonical);
        if !seen.insert(key.clone()) {
            continue;
        }
        let kind = outbound
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        let tag = format!(
            "{}-{}",
            kind.chars().take(2).collect::<String>(),
            outbounds.len()
        );
        outbound["tag"] = json!(tag);
        tag_by_key.insert(key, tag.clone());
        outbounds.push(outbound);
    }

    if outbounds.is_empty() {
        logs.push("✗ ERROR: no parseable nodes in node list".to_string());
        return BuildOutcome {
            config: None,
            logs,
            exit_code: 1,
            node_count: 0,
            tg_count: 0,
        };
    }

    let tags: Vec<String> = outbounds
        .iter()
        .map(|outbound| {
            outbound
                .get("tag")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string()
        })
        .collect();

    let mut tg_tags: Vec<String> = Vec::new();
    for raw_line in tg_nodes_text.trim().split('\n') {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let Some(outbound) = nodes::parse_line(line, ParserMode::GenConfig) else {
            continue;
        };
        let canonical = line.split('#').next().unwrap_or("").trim().to_string();
        let server = outbound
            .get("server")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_lowercase();
        let port = outbound
            .get("server_port")
            .and_then(Value::as_i64)
            .unwrap_or(0);
        if let Some(tag) = tag_by_key.get(&(server, port, canonical)) {
            if !tg_tags.contains(tag) {
                tg_tags.push(tag.clone());
            }
        }
    }
    if tg_tags.is_empty() {
        logs.push("! no Telegram-capable nodes — tg-auto falls back to all nodes".to_string());
        tg_tags = tags.clone();
    }

    outbounds.push(json!({
        "type": "urltest",
        "tag": "auto",
        "outbounds": tags,
        "interval": "15s",
        "tolerance": 50
    }));
    outbounds.push(json!({
        "type": "urltest",
        "tag": "tg-auto",
        "outbounds": tg_tags.clone(),
        "interval": "15s",
        "tolerance": 50
    }));
    outbounds.push(json!({"type": "direct", "tag": "direct"}));

    let mut in_lan = json!({
        "type": "socks",
        "tag": "in-lan",
        "listen": "0.0.0.0",
        "listen_port": 10810
    });
    if !lan_auth.is_empty() {
        let Some((username, password)) = lan_auth.split_once(':') else {
            logs.push("✗ ERROR: LAN secret is not in user:pass form".to_string());
            return BuildOutcome {
                config: None,
                logs,
                exit_code: 1,
                node_count: 0,
                tg_count: 0,
            };
        };
        in_lan["users"] = json!([{"username": username, "password": password}]);
    }

    let inbounds = json!([
        {"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": 10808},
        in_lan,
        {"type": "socks", "tag": "in-lan-vm", "listen": "0.0.0.0", "listen_port": 10811},
        {"type": "http", "tag": "in-lan-vm-http", "listen": "0.0.0.0", "listen_port": 10812}
    ]);
    let dns = final_dns();
    let route = final_route();

    let config = json!({
        "log": {"level": "error"},
        "dns": dns,
        "inbounds": inbounds,
        "outbounds": outbounds,
        "route": route
    });

    logs.push(format!(
        "✓ Config: {} outbounds + urltest ({} tg-capable)",
        tags.len(),
        tg_tags.len()
    ));
    BuildOutcome {
        config: Some(config),
        logs,
        exit_code: 0,
        node_count: tags.len(),
        tg_count: tg_tags.len(),
    }
}

pub struct PatchOutcome {
    pub changed: bool,
    pub logs: Vec<String>,
}

fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(flag) => *flag,
        Value::Number(number) => number.as_f64().is_some_and(|n| n != 0.0),
        Value::String(text) => !text.is_empty(),
        Value::Array(items) => !items.is_empty(),
        Value::Object(map) => !map.is_empty(),
    }
}

fn remove_key_preserving_order(map: &mut Map<String, Value>, key: &str) {
    let entries: Vec<(String, Value)> = std::mem::take(map)
        .into_iter()
        .filter(|(existing, _)| existing != key)
        .collect();
    for (existing, value) in entries {
        map.insert(existing, value);
    }
}

/// `bootstrap`'s Python patcher: heal dns/route, the `tg-auto` group, urltest
/// intervals and the LAN inbound's users block. Returns the emitted messages.
///
/// Intentional deviation: the shell version called `os.chmod` after writing
/// without importing `os`, so every healing run exited 1 with a NameError after
/// writing the file (the file mode was left untouched). The port performs the
/// chmod and reports success; see the crate report.
pub fn patch_config(config: &mut Value, lan_auth: &str) -> Result<PatchOutcome, String> {
    if !config.is_object() {
        return Err("config root is not a JSON object".to_string());
    }
    let mut logs = Vec::new();
    let mut changed = false;

    let real_tags: Vec<Value> = match config.get("outbounds") {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|outbound| {
                let kind = outbound.get("type").and_then(Value::as_str).unwrap_or("");
                if kind == "urltest" || kind == "direct" {
                    return None;
                }
                match outbound.get("tag") {
                    Some(Value::String(tag)) if !tag.is_empty() => Some(json!(tag)),
                    _ => None,
                }
            })
            .collect(),
        _ => Vec::new(),
    };
    let tg_index = match config.get("outbounds") {
        Some(Value::Array(items)) => items
            .iter()
            .position(|outbound| outbound.get("tag").and_then(Value::as_str) == Some("tg-auto")),
        _ => None,
    };

    if tg_index.is_none() && !real_tags.is_empty() {
        let outbounds = config
            .get_mut("outbounds")
            .and_then(Value::as_array_mut)
            .ok_or_else(|| "config has no outbounds array".to_string())?;
        outbounds.push(json!({
            "type": "urltest",
            "tag": "tg-auto",
            "outbounds": real_tags,
            "interval": "15s",
            "tolerance": 50
        }));
        changed = true;
        logs.push(":: Config: added tg-auto group (all nodes until next refresh)".to_string());
    } else if let Some(index) = tg_index {
        let empty = match config["outbounds"][index].get("outbounds") {
            None => true,
            Some(value) => !truthy(value),
        };
        if empty && !real_tags.is_empty() {
            config["outbounds"][index]["outbounds"] = Value::Array(real_tags.clone());
            changed = true;
            logs.push(":: Config: tg-auto group had no nodes - reset to all nodes".to_string());
        }
    }

    if let Some(outbounds) = config.get_mut("outbounds").and_then(Value::as_array_mut) {
        for outbound in outbounds.iter_mut() {
            if outbound.get("type").and_then(Value::as_str) != Some("urltest") {
                continue;
            }
            let needs_reset = match outbound.get("interval") {
                None | Some(Value::Null) => false,
                Some(Value::String(interval)) if interval == "15s" => false,
                Some(_) => true,
            };
            if needs_reset {
                outbound["interval"] = json!("15s");
                changed = true;
            }
        }
    }

    let dns = final_dns();
    let route = final_route();
    if config.get("dns") != Some(&dns) || config.get("route") != Some(&route) {
        config["dns"] = dns;
        config["route"] = route;
        changed = true;
        logs.push(":: Config: DNS/route reset to final shape (client-side resolve)".to_string());
    }

    let want_users = if lan_auth.is_empty() {
        None
    } else {
        let (username, password) = lan_auth
            .split_once(':')
            .ok_or_else(|| "LAN secret is not in user:pass form".to_string())?;
        Some(json!([{"username": username, "password": password}]))
    };
    let lan_index = match config.get("inbounds") {
        Some(Value::Array(items)) => items
            .iter()
            .position(|inbound| inbound.get("tag").and_then(Value::as_str) == Some("in-lan")),
        _ => None,
    };
    match lan_index {
        None => {
            let inbounds = config
                .get_mut("inbounds")
                .and_then(Value::as_array_mut)
                .ok_or_else(|| "config has no inbounds array".to_string())?;
            let mut inbound = json!({
                "type": "socks",
                "tag": "in-lan",
                "listen": "0.0.0.0",
                "listen_port": 10810
            });
            if let Some(users) = &want_users {
                inbound["users"] = users.clone();
            }
            inbounds.push(inbound);
            changed = true;
            logs.push(format!(
                ":: Config: added LAN inbound (0.0.0.0:10810, {})",
                if want_users.is_some() {
                    "password auth"
                } else {
                    "no auth"
                }
            ));
        }
        Some(index) => {
            let inbounds = config
                .get_mut("inbounds")
                .and_then(Value::as_array_mut)
                .ok_or_else(|| "config has no inbounds array".to_string())?;
            let current = inbounds[index].get("users").cloned().unwrap_or(Value::Null);
            let wanted = want_users.clone().unwrap_or(Value::Null);
            if current != wanted {
                match want_users {
                    Some(users) => {
                        inbounds[index]["users"] = users;
                        logs.push(
                            ":: Config: LAN inbound credentials synced from secret".to_string(),
                        );
                    }
                    None => {
                        if let Some(object) = inbounds[index].as_object_mut() {
                            remove_key_preserving_order(object, "users");
                        }
                        logs.push(
                            ":: Config: LAN inbound is passwordless (users removed)".to_string(),
                        );
                    }
                }
                changed = true;
            }
        }
    }

    Ok(PatchOutcome { changed, logs })
}

/// Write a freshly generated config: parent directory 0700 (created when
/// missing), file 0600 — the file carries live node credentials.
pub fn write_config(path: &Path, config: &Value) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
            fs::set_permissions(parent, fs::Permissions::from_mode(0o700))?;
        }
    }
    write_config_in_place(path, config)
}

/// Rewrite an existing config (bootstrap heal) and enforce 0600.
pub fn write_config_in_place(path: &Path, config: &Value) -> io::Result<()> {
    fs::write(path, to_python_json(config))?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
}

#[cfg(test)]
mod tests {
    use super::*;

    const NODES: &str = "vless://uuid@a.example.com:443?security=reality&pbk=0123456789abcdefghijklmnopqrstuvwxyzABCDEFG&sid=ab&type=ws&path=%2Fws#A\n\
trojan://p%C3%A4ss@tj.example.com:443?sni=tjsni.example.com&type=ws&host=tjws.example.com&path=%2Ftj#B\n";

    #[test]
    fn builds_expected_shape() {
        let outcome = build_config(NODES, "", "fixtureuser:fixturepass");
        assert_eq!(outcome.exit_code, 0);
        let config = outcome.config.unwrap();
        assert_eq!(config["dns"]["strategy"], "prefer_ipv4");
        assert_eq!(config["route"]["final"], "auto");
        assert_eq!(config["route"]["rules"][2]["outbound"], "tg-auto");
        assert_eq!(config["inbounds"][1]["users"][0]["username"], "fixtureuser");
        assert_eq!(config["outbounds"][0]["tag"], "vl-0");
        assert_eq!(config["outbounds"][1]["tag"], "tr-1");
        assert_eq!(config["outbounds"][1]["type"], "trojan");
        assert_eq!(config["outbounds"][2]["tag"], "auto");
        assert_eq!(config["outbounds"][3]["tag"], "tg-auto");
        assert_eq!(
            config["outbounds"][3]["outbounds"],
            serde_json::json!(["vl-0", "tr-1"])
        );
        assert_eq!(config["outbounds"][4]["tag"], "direct");
    }

    #[test]
    fn empty_node_list_is_an_error() {
        let outcome = build_config("not-a-node\n", "", "");
        assert_eq!(outcome.exit_code, 1);
        assert!(outcome.config.is_none());
        assert_eq!(
            outcome.logs,
            vec!["✗ ERROR: no parseable nodes in node list"]
        );
    }

    #[test]
    fn lan_auth_without_colon_is_an_error() {
        let outcome = build_config(NODES, "", "no-colon");
        assert_eq!(outcome.exit_code, 1);
        assert!(outcome.config.is_none());
    }

    #[test]
    fn patch_adds_missing_pieces() {
        let mut config = json!({
            "log": {"level": "error"},
            "dns": {},
            "inbounds": [{"type": "socks", "tag": "in", "listen": "127.0.0.1", "listen_port": 10808}],
            "outbounds": [
                {"type": "vless", "tag": "vl-0", "server": "a.example.com", "server_port": 443},
                {"type": "urltest", "tag": "auto", "outbounds": ["vl-0"], "interval": "1m", "tolerance": 50},
                {"type": "direct", "tag": "direct"}
            ],
            "route": {"final": "direct"}
        });
        let outcome = patch_config(&mut config, "fixtureuser:fixturepass").unwrap();
        assert!(outcome.changed);
        assert!(config["outbounds"]
            .as_array()
            .unwrap()
            .iter()
            .any(|o| o["tag"] == "tg-auto"));
        assert_eq!(config["outbounds"][1]["interval"], "15s");
        assert_eq!(config["dns"], final_dns());
        assert_eq!(config["inbounds"][1]["users"][0]["username"], "fixtureuser");
        assert_eq!(
            outcome.logs,
            vec![
                ":: Config: added tg-auto group (all nodes until next refresh)",
                ":: Config: DNS/route reset to final shape (client-side resolve)",
                ":: Config: added LAN inbound (0.0.0.0:10810, password auth)"
            ]
        );
    }

    #[test]
    fn patch_is_order_insensitive_for_dns_objects() {
        let mut config = json!({
            "dns": {"strategy": "prefer_ipv4", "servers": [
                {"tag": "remote", "type": "https", "server": "1.1.1.1", "server_port": 443}
            ]},
            "route": final_route(),
            "inbounds": [{"type": "socks", "tag": "in-lan", "listen": "0.0.0.0", "listen_port": 10810}],
            "outbounds": [{"type": "vless", "tag": "vl-0", "server": "a", "server_port": 443}]
        });
        let outcome = patch_config(&mut config, "").unwrap();
        assert!(
            !outcome.logs.iter().any(|line| line.contains("DNS/route")),
            "reordered dns must compare equal, logs: {:?}",
            outcome.logs
        );
    }

    #[test]
    fn patch_removes_lan_users_when_secret_is_gone() {
        let mut config = json!({
            "dns": final_dns(),
            "route": final_route(),
            "inbounds": [{
                "type": "socks", "tag": "in-lan", "listen": "0.0.0.0", "listen_port": 10810,
                "users": [{"username": "old", "password": "wrong"}]
            }],
            "outbounds": [
                {"type": "vless", "tag": "vl-0", "server": "a", "server_port": 443},
                {"type": "urltest", "tag": "tg-auto", "outbounds": ["vl-0"], "interval": "15s", "tolerance": 50}
            ]
        });
        let outcome = patch_config(&mut config, "").unwrap();
        assert!(outcome.changed);
        assert!(config["inbounds"][0].get("users").is_none());
        assert_eq!(
            outcome.logs,
            vec![":: Config: LAN inbound is passwordless (users removed)"]
        );
    }

    #[test]
    fn python_json_has_no_trailing_newline() {
        let outcome = build_config(NODES, "", "");
        let text = to_python_json(&outcome.config.unwrap());
        assert!(!text.ends_with('\n'));
        assert!(text.starts_with("{\n  \"log\": {"));
    }
}
