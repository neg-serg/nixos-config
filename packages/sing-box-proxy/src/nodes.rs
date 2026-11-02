//! Node URI parsing.
//!
//! Two variants, exactly as the shell script had them:
//! - `ParserMode::GenConfig` is the `gen_cfg` parser (`parse_line`): it builds
//!   the outbound objects written to the config.
//! - `ParserMode::Probe` is the `validate_nodes` parser (`parse_outbound`): it
//!   is only used to filter e2e candidates. It differs from the generator in
//!   two places, both preserved on purpose:
//!   1. `hysteria2`/`hy2` goes through `hp_parse`, so a malformed host:port
//!      drops the node instead of falling back to port 443.
//!   2. the `trojan://` branch never returns its object (the shell's function
//!      falls through to `return None`), so trojan nodes never reach the e2e
//!      probe. This is a bug in the shell version, kept bug-for-bug; see the
//!      crate report for the one-line change that would include trojan nodes.
//!
//! All query parsing follows the generator's `clean()`: split on `&`, first
//! occurrence wins, keys are not percent-decoded, values are (`+` is preserved
//! — `parse_qs` would turn it into a space and break reality public keys).

use serde_json::{json, Value};
use std::collections::HashMap;

pub type Query = HashMap<String, String>;

const FINGERPRINTS: [&str; 9] = [
    "chrome",
    "firefox",
    "ios",
    "android",
    "edge",
    "safari",
    "360",
    "random",
    "randomized",
];

const VMESS_SECURITIES: [&str; 5] = ["auto", "aes-128-gcm", "chacha20-poly1305", "none", "zero"];

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum ParserMode {
    GenConfig,
    Probe,
}

/// python's `urllib.parse.unquote` (utf-8, `errors=replace`, `+` preserved).
pub fn unquote(input: &str) -> String {
    percent_encoding::percent_decode_str(input)
        .decode_utf8_lossy()
        .into_owned()
}

pub fn qget<'a>(query: &'a Query, key: &str) -> Option<&'a str> {
    query.get(key).map(String::as_str)
}

/// python's `clean()`: parse a URI query string without mangling `+`.
pub fn clean(input: &str) -> Query {
    let mut out = Query::new();
    if input.is_empty() {
        return out;
    }
    let normalized = input.replace("&amp;", "&");
    let without_fragment = normalized.split('#').next().unwrap_or("");
    for pair in without_fragment.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (key, value) = match pair.split_once('=') {
            Some((key, value)) => (key, unquote(value.split('#').next().unwrap_or(""))),
            None => (pair, String::new()),
        };
        out.entry(key.to_string()).or_insert(value);
    }
    out
}

/// `hp_parse`: `host:port[/path...]` -> `(host, port)`.
pub fn hp_parse(text: &str) -> Option<(String, i64)> {
    let colon = text.find(':')?;
    let host = &text[..colon];
    if host.is_empty() || host.contains(['?', '#', '/']) {
        return None;
    }
    let rest = &text[colon + 1..];
    let digits = rest
        .find(|ch: char| !ch.is_ascii_digit())
        .unwrap_or(rest.len());
    if digits == 0 {
        return None;
    }
    let port: i64 = rest[..digits].parse().ok()?;
    let tail = &rest[digits..];
    if !tail.is_empty() && !tail.starts_with(['/', '?', '#']) {
        return None;
    }
    Some((host.to_string(), port))
}

/// `parse_addr`: `(host, port, proto)` for the TCP/UDP scan, or `None`.
///
/// Mirrors the three anchored regexes of the shell (`re.match`, no `$`), so a
/// URI whose host:port is followed by arbitrary trailing bytes still matches.
pub fn parse_addr(line: &str) -> Option<(String, i64, String)> {
    let schemes = [
        "vless",
        "vmess",
        "ss",
        "trojan",
        "anytls",
        "hysteria2",
        "hy2",
        "tuic",
    ];
    for scheme in schemes {
        let Some(rest) = line.strip_prefix(&format!("{scheme}://")) else {
            continue;
        };
        // `[^@]+@`: the first '@' must not be the first character of the rest.
        let at = rest.find('@')?;
        if at == 0 {
            return None;
        }
        let after_at = &rest[at + 1..];
        // `([^:?#/]+):` — host runs up to the first delimiter, which must be ':'.
        let Some(delimiter) = after_at.find([':', '?', '#', '/']) else {
            continue;
        };
        if !after_at[delimiter..].starts_with(':') {
            continue;
        }
        let host = &after_at[..delimiter];
        if host.is_empty() {
            continue;
        }
        let after_colon = &after_at[delimiter + 1..];
        let digits = after_colon
            .find(|ch: char| !ch.is_ascii_digit())
            .unwrap_or(after_colon.len());
        if digits == 0 {
            continue;
        }
        let port: i64 = after_colon[..digits].parse().ok()?;
        return Some((host.to_string(), port, scheme.to_string()));
    }
    // hysteria v1 carries auth in the query string (no user@ part).
    if let Some(rest) = line.strip_prefix("hysteria://") {
        let host_end = rest.find([':', '?', '#', '/'])?;
        if !rest[host_end..].starts_with(':') {
            return None;
        }
        let host = &rest[..host_end];
        if host.is_empty() {
            return None;
        }
        let after_colon = &rest[host_end + 1..];
        let digits = after_colon
            .find(|ch: char| !ch.is_ascii_digit())
            .unwrap_or(after_colon.len());
        if digits == 0 {
            return None;
        }
        let port: i64 = after_colon[..digits].parse().ok()?;
        return Some((host.to_string(), port, "hysteria".to_string()));
    }
    None
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

/// python's `str()` for values that can appear in a vmess JSON payload.
fn py_str(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => Some(text.clone()),
        Value::Number(number) => Some(number.to_string()),
        Value::Bool(true) => Some("True".to_string()),
        Value::Bool(false) => Some("False".to_string()),
        Value::Null => Some("None".to_string()),
        // python would print a repr; not a shape any real payload uses.
        Value::Array(_) | Value::Object(_) => None,
    }
}

/// python's `int()` for JSON values (numbers, booleans and numeric strings).
fn py_int(value: &Value) -> Option<i64> {
    match value {
        Value::Null => None,
        Value::Bool(true) => Some(1),
        Value::Bool(false) => Some(0),
        Value::Number(number) => {
            if let Some(n) = number.as_i64() {
                Some(n)
            } else {
                number.as_f64().map(|n| n.trunc() as i64)
            }
        }
        Value::String(text) => text.trim().parse().ok(),
        Value::Array(_) | Value::Object(_) => None,
    }
}

/// python's `int(float())` with the exception swallowed by the caller.
fn py_num(text: &str) -> Option<i64> {
    let value: f64 = text.trim().parse().ok()?;
    if !value.is_finite() {
        return None;
    }
    Some(value.trunc() as i64)
}

fn utls_tls(server_name: &Value, fingerprint: &str) -> Value {
    json!({
        "enabled": true,
        "server_name": server_name,
        "utls": {"enabled": true, "fingerprint": fingerprint}
    })
}

fn normalize_fp(query: &Query) -> &str {
    match qget(query, "fp") {
        Some(fp) if FINGERPRINTS.contains(&fp) => fp,
        _ => "chrome",
    }
}

/// `security=reality` with a long enough public key adds the reality block.
fn maybe_reality(tls: &mut Value, security: &str, pbk: &str, sid: &str, translate: bool) {
    if security != "reality" || pbk.chars().count() < 32 {
        return;
    }
    let public_key = if translate {
        pbk.replace('+', "-")
            .replace('/', "_")
            .trim_end_matches('=')
            .to_string()
    } else {
        pbk.to_string()
    };
    tls["reality"] = json!({
        "enabled": true,
        "public_key": public_key,
        "short_id": sid
    });
}

enum QueryTransport {
    /// `type=xhttp`/`splithttp`: the whole node is dropped.
    Drop,
    /// No supported transport type: no `transport` key.
    Absent,
    Json(Value),
}

/// Transport construction shared by vless and trojan (query-string variants).
fn query_transport(query: &Query) -> QueryTransport {
    let kind = qget(query, "type").unwrap_or("").to_lowercase();
    if kind == "xhttp" || kind == "splithttp" {
        return QueryTransport::Drop;
    }
    let host = qget(query, "host").filter(|value| !value.is_empty());
    let path = qget(query, "path").filter(|value| !value.is_empty());
    let value = match kind.as_str() {
        "ws" => {
            let mut transport = json!({"type": "ws"});
            if let Some(path) = path {
                transport["path"] = json!(path);
            }
            if let Some(host) = host {
                transport["headers"] = json!({"Host": host});
            }
            transport
        }
        "grpc" => {
            let mut transport = json!({"type": "grpc"});
            if let Some(service) = qget(query, "serviceName").filter(|value| !value.is_empty()) {
                transport["service_name"] = json!(service);
            }
            transport
        }
        "httpupgrade" => {
            let mut transport = json!({"type": "httpupgrade"});
            if let Some(host) = host {
                transport["host"] = json!(host);
            }
            if let Some(path) = path {
                transport["path"] = json!(path);
            }
            transport
        }
        "http" => {
            let mut transport = json!({"type": "http"});
            if let Some(host) = host {
                transport["host"] = json!([host]);
            }
            if let Some(path) = path {
                transport["path"] = json!(path);
            }
            transport
        }
        _ => return QueryTransport::Absent,
    };
    QueryTransport::Json(value)
}

/// Parse one node URI into a sing-box outbound object. `None` means the line is
/// not a supported/valid node (the generator silently skips it).
pub fn parse_line(line: &str, mode: ParserMode) -> Option<Value> {
    if line.starts_with("hysteria2://") || line.starts_with("hy2://") {
        return parse_hysteria2(line, mode);
    }
    if let Some(rest) = line.strip_prefix("vless://") {
        return parse_vless(rest);
    }
    if let Some(rest) = line.strip_prefix("ss://") {
        return parse_shadowsocks(rest);
    }
    if let Some(rest) = line.strip_prefix("trojan://") {
        return parse_trojan(rest, mode);
    }
    if let Some(rest) = line.strip_prefix("vmess://") {
        return parse_vmess(rest);
    }
    if let Some(rest) = line.strip_prefix("tuic://") {
        return parse_tuic(rest);
    }
    if let Some(rest) = line.strip_prefix("hysteria://") {
        return parse_hysteria_v1(rest);
    }
    if let Some(rest) = line.strip_prefix("anytls://") {
        return parse_anytls(rest);
    }
    None
}

fn parse_hysteria2(line: &str, mode: ParserMode) -> Option<Value> {
    let rest = line
        .strip_prefix("hysteria2://")
        .or_else(|| line.strip_prefix("hy2://"))?;
    let authority = match rest.split_once('@') {
        Some((_, after)) => after,
        None => rest,
    };
    let host_port = authority.split('?').next().unwrap_or(authority);
    let (host, port) = match mode {
        ParserMode::GenConfig => {
            let host = host_port.split(':').next().unwrap_or(host_port).to_string();
            let port_text = host_port
                .split_once(':')
                .map(|(_, port)| port)
                .unwrap_or("443");
            let digits = port_text.split('?').next().unwrap_or(port_text);
            let port = if !digits.is_empty() && digits.chars().all(|ch| ch.is_ascii_digit()) {
                digits.parse().ok()?
            } else {
                443
            };
            (host, port)
        }
        ParserMode::Probe => hp_parse(host_port)?,
    };
    let password = match rest.split_once('@') {
        Some(_) => rest.split('@').next().unwrap_or(rest),
        None => rest.split('?').next().unwrap_or(rest),
    };
    let query = clean(
        authority
            .split_once('?')
            .map(|(_, query)| query)
            .unwrap_or(""),
    );
    let server_name = qget(&query, "sni").unwrap_or(host.as_str()).to_string();
    let mut outbound = json!({
        "type": "hysteria2",
        "tag": "node",
        "server": host.clone(),
        "server_port": port,
        "password": password,
        "tls": {
            "enabled": true,
            "insecure": true,
            "server_name": server_name
        }
    });
    if query.contains_key("obfs") {
        outbound["obfs"] = json!({
            "type": qget(&query, "obfs").unwrap_or(""),
            "password": qget(&query, "obfs-password").unwrap_or("")
        });
    }
    Some(outbound)
}

fn parse_vless(rest: &str) -> Option<Value> {
    let uuid = rest.split('@').next().unwrap_or(rest);
    let authority = match rest.split_once('@') {
        Some((_, after)) => after,
        None => rest,
    };
    let host_port = authority.split('?').next().unwrap_or(authority);
    let (host, port) = hp_parse(host_port)?;
    let query = clean(
        authority
            .split_once('?')
            .map(|(_, query)| query)
            .unwrap_or(""),
    );
    let mut outbound = json!({
        "type": "vless",
        "tag": "node",
        "server": host.clone(),
        "server_port": port,
        "uuid": uuid,
        "packet_encoding": "xudp"
    });
    let security = qget(&query, "security").unwrap_or("");
    if matches!(security, "tls" | "reality" | "xtls") {
        let server_name = json!(qget(&query, "sni").unwrap_or(host.as_str()));
        let mut tls = utls_tls(&server_name, normalize_fp(&query));
        maybe_reality(
            &mut tls,
            security,
            qget(&query, "pbk").unwrap_or(""),
            qget(&query, "sid").unwrap_or(""),
            true,
        );
        outbound["tls"] = tls;
    }
    if qget(&query, "flow").unwrap_or("") == "xtls-rprx-vision" {
        outbound["flow"] = json!("xtls-rprx-vision");
    }
    match query_transport(&query) {
        QueryTransport::Drop => return None,
        QueryTransport::Absent => {}
        QueryTransport::Json(transport) => outbound["transport"] = transport,
    }
    Some(outbound)
}

fn parse_shadowsocks(rest: &str) -> Option<Value> {
    let (method, password, host_port);
    if let Some((userinfo, after_at)) = rest.split_once('@') {
        if userinfo.contains(':') {
            let (m, p) = userinfo.split_once(':').unwrap();
            method = m.to_string();
            password = p.to_string();
        } else {
            let decoded = crate::b64::b64dec(userinfo);
            if !decoded.contains(':') {
                return None;
            }
            let (m, p) = decoded.split_once(':').unwrap();
            method = m.to_string();
            password = p.to_string();
        }
        host_port = after_at.to_string();
    } else {
        let decoded = crate::b64::b64dec(rest.split('#').next().unwrap_or(""));
        if !decoded.contains(':') || !decoded.contains('@') {
            return None;
        }
        let (m, rest_after_method) = decoded.split_once(':').unwrap();
        let (p, h) = rest_after_method.rsplit_once('@').unwrap();
        method = m.to_string();
        password = p.to_string();
        host_port = h.to_string();
    }
    let host_port = host_port.split('#').next().unwrap_or(host_port.as_str());
    let (host, port) = hp_parse(host_port)?;
    let query = clean(rest.split_once('?').map(|(_, query)| query).unwrap_or(""));
    if query.contains_key("plugin") {
        return None;
    }
    Some(json!({
        "type": "shadowsocks",
        "tag": "node",
        "server": host,
        "server_port": port,
        "method": method,
        "password": password
    }))
}

fn parse_trojan(rest: &str, mode: ParserMode) -> Option<Value> {
    let password = unquote(rest.split('@').next().unwrap_or(rest));
    let authority = match rest.split_once('@') {
        Some((_, after)) => after,
        None => rest,
    };
    let host_port = authority.split('?').next().unwrap_or(authority);
    let (host, port) = hp_parse(host_port)?;
    let query = clean(
        authority
            .split_once('?')
            .map(|(_, query)| query)
            .unwrap_or(""),
    );
    let mut outbound = json!({
        "type": "trojan",
        "tag": "node",
        "server": host.clone(),
        "server_port": port,
        "password": password
    });
    let security = qget(&query, "security").unwrap_or("tls");
    if matches!(security, "tls" | "reality") {
        let server_name = json!(qget(&query, "sni").unwrap_or(host.as_str()));
        let mut tls = utls_tls(&server_name, normalize_fp(&query));
        maybe_reality(
            &mut tls,
            security,
            qget(&query, "pbk").unwrap_or(""),
            qget(&query, "sid").unwrap_or(""),
            true,
        );
        outbound["tls"] = tls;
    }
    match query_transport(&query) {
        QueryTransport::Drop => return None,
        QueryTransport::Absent => {}
        QueryTransport::Json(transport) => outbound["transport"] = transport,
    }
    // Preserved shell bug: validate's parse_outbound has no `return ob` in the
    // trojan branch, so probe-mode trojan nodes are always filtered out.
    if mode == ParserMode::Probe {
        return None;
    }
    Some(outbound)
}

fn parse_vmess(rest: &str) -> Option<Value> {
    let payload_text = rest.split('#').next().unwrap_or("");
    let decoded = crate::b64::b64dec(payload_text);
    let payload: Value = serde_json::from_str(&decoded).ok()?;
    if !payload.is_object() {
        return None;
    }
    let host = match payload.get("add") {
        Some(value) => py_str(value)?,
        None => String::new(),
    };
    if host.is_empty() {
        return None;
    }
    let port = match payload.get("port") {
        Some(value) => py_int(value)?,
        None => 0,
    };
    if port == 0 {
        return None;
    }
    let uuid = match payload.get("id") {
        Some(value) => py_str(value)?,
        None => String::new(),
    };
    let security = match payload.get("scy") {
        None => "auto".to_string(),
        Some(value) if !truthy(value) => "auto".to_string(),
        Some(value) => py_str(value)?,
    };
    let security = if VMESS_SECURITIES.contains(&security.as_str()) {
        security
    } else {
        "auto".to_string()
    };
    let alter_id = match payload.get("aid") {
        None => 0,
        Some(value) if !truthy(value) => 0,
        Some(value) => py_int(value)?,
    };
    let mut outbound = json!({
        "type": "vmess",
        "tag": "node",
        "server": host.clone(),
        "server_port": port,
        "uuid": uuid,
        "security": security,
        "alter_id": alter_id
    });
    let tls_type = payload.get("tls").and_then(Value::as_str);
    if let Some(tls_type) = tls_type.filter(|s| matches!(*s, "tls" | "reality" | "xtls")) {
        let fp = payload
            .get("fp")
            .and_then(Value::as_str)
            .filter(|fp| FINGERPRINTS.contains(fp))
            .unwrap_or("chrome");
        let server_name = payload.get("sni").cloned().unwrap_or_else(|| json!(host));
        let mut tls = utls_tls(&server_name, fp);
        if tls_type == "reality" {
            let pbk = match payload.get("pbk") {
                Some(value) => py_str(value)?,
                None => String::new(),
            };
            let sid = match payload.get("sid") {
                Some(value) => py_str(value)?,
                None => String::new(),
            };
            maybe_reality(&mut tls, "reality", &pbk, &sid, false);
        }
        if let Some(alpn) = payload.get("alpn").filter(|value| truthy(value)) {
            let alpn = py_str(alpn)?;
            tls["alpn"] = Value::Array(
                alpn.split(',')
                    .filter(|item| !item.is_empty())
                    .map(|item| json!(item))
                    .collect(),
            );
        }
        outbound["tls"] = tls;
    }
    let network = match payload.get("net") {
        None => Some("tcp".to_string()),
        Some(Value::String(net)) => Some(net.clone()),
        Some(_) => None,
    };
    let host_header = payload.get("host").cloned().unwrap_or_else(|| json!(""));
    let path = payload.get("path").cloned().unwrap_or_else(|| json!(""));
    match network.as_deref() {
        Some("ws") => {
            let mut transport = json!({"type": "ws"});
            if truthy(&path) {
                transport["path"] = path.clone();
            }
            if truthy(&host_header) {
                transport["headers"] = json!({"Host": host_header.clone()});
            }
            outbound["transport"] = transport;
        }
        Some("grpc") => {
            let path_text = match payload.get("path") {
                None => "",
                Some(Value::String(text)) => text.as_str(),
                Some(_) => return None,
            };
            let mut service = path_text.split('?').next().unwrap_or("");
            if let Some(stripped) = service.strip_prefix('/') {
                service = stripped;
            }
            let mut transport = json!({"type": "grpc"});
            if !service.is_empty() {
                transport["service_name"] = json!(service);
            }
            if truthy(&host_header) {
                transport["authority"] = host_header.clone();
            }
            outbound["transport"] = transport;
        }
        Some("httpupgrade") => {
            let mut transport = json!({"type": "httpupgrade"});
            if truthy(&host_header) {
                transport["host"] = host_header.clone();
            }
            if truthy(&path) {
                transport["path"] = path.clone();
            }
            outbound["transport"] = transport;
        }
        Some("h2") | Some("http") => {
            let mut transport = json!({"type": "http"});
            if truthy(&host_header) {
                transport["host"] = json!([host_header.clone()]);
            }
            if truthy(&path) {
                transport["path"] = path.clone();
            }
            outbound["transport"] = transport;
        }
        Some("xhttp") | Some("splithttp") => return None,
        Some("tcp") if payload.get("type").and_then(Value::as_str) == Some("http") => {
            let mut transport = json!({"type": "http"});
            if truthy(&host_header) {
                transport["host"] = json!([host_header.clone()]);
            }
            if truthy(&path) {
                transport["path"] = path.clone();
            }
            outbound["transport"] = transport;
        }
        _ => {}
    }
    Some(outbound)
}

fn parse_tuic(rest: &str) -> Option<Value> {
    let credentials = rest.split('@').next().unwrap_or(rest);
    if !credentials.contains(':') {
        return None;
    }
    let (uuid, password) = credentials.split_once(':').unwrap();
    let authority = match rest.split_once('@') {
        Some((_, after)) => after,
        None => rest,
    };
    let (host, port) = hp_parse(authority.split('?').next().unwrap_or(authority))?;
    let query = clean(
        authority
            .split_once('?')
            .map(|(_, query)| query)
            .unwrap_or(""),
    );
    let mut tls = json!({
        "enabled": true,
        "server_name": qget(&query, "sni").unwrap_or(host.as_str())
    });
    if matches!(
        qget(&query, "allow_insecure").unwrap_or("0"),
        "1" | "true" | "yes"
    ) {
        tls["insecure"] = json!(true);
    }
    if let Some(alpn) = qget(&query, "alpn").filter(|value| !value.is_empty()) {
        tls["alpn"] = Value::Array(
            alpn.split(',')
                .filter(|item| !item.is_empty())
                .map(|item| json!(item))
                .collect(),
        );
    }
    Some(json!({
        "type": "tuic",
        "tag": "node",
        "server": host,
        "server_port": port,
        "uuid": unquote(uuid),
        "password": unquote(password),
        "congestion_control": qget(&query, "congestion_control").unwrap_or("bbr"),
        "udp_relay_mode": qget(&query, "udp_relay_mode").unwrap_or("native"),
        "tls": tls
    }))
}

fn parse_hysteria_v1(rest: &str) -> Option<Value> {
    let (host, port) = hp_parse(rest.split('?').next().unwrap_or(rest))?;
    let query = clean(rest.split_once('?').map(|(_, query)| query).unwrap_or(""));
    let mut outbound = json!({
        "type": "hysteria",
        "tag": "node",
        "server": host.clone(),
        "server_port": port
    });
    if let Some(auth) = qget(&query, "auth").filter(|value| !value.is_empty()) {
        outbound["auth_str"] = json!(unquote(auth));
    }
    for (key, field) in [("up", "up_mbps"), ("down", "down_mbps")] {
        if let Some(value) = qget(&query, key).filter(|value| !value.is_empty()) {
            if let Some(rate) = py_num(value) {
                outbound[field] = json!(rate);
            }
        }
    }
    if let Some(obfs) = qget(&query, "obfs").filter(|value| !value.is_empty()) {
        outbound["obfs"] = json!(obfs);
    }
    let insecure = !matches!(
        qget(&query, "insecure").unwrap_or("1"),
        "0" | "false" | "no"
    );
    let server_name = qget(&query, "sni")
        .or_else(|| qget(&query, "server_name"))
        .unwrap_or(host.as_str())
        .to_string();
    let mut tls = json!({
        "enabled": true,
        "insecure": insecure,
        "server_name": server_name
    });
    if let Some(alpn) = qget(&query, "alpn").filter(|value| !value.is_empty()) {
        tls["alpn"] = Value::Array(
            alpn.split(',')
                .filter(|item| !item.is_empty())
                .map(|item| json!(item))
                .collect(),
        );
    }
    outbound["tls"] = tls;
    Some(outbound)
}

fn parse_anytls(rest: &str) -> Option<Value> {
    let password = unquote(rest.split('@').next().unwrap_or(rest));
    let authority = match rest.split_once('@') {
        Some((_, after)) => after,
        None => rest,
    };
    let (host, port) = hp_parse(authority.split('?').next().unwrap_or(authority))?;
    let query = clean(
        authority
            .split_once('?')
            .map(|(_, query)| query)
            .unwrap_or(""),
    );
    let mut tls = json!({
        "enabled": true,
        "server_name": qget(&query, "sni").unwrap_or(host.as_str())
    });
    if matches!(
        qget(&query, "insecure").unwrap_or("0"),
        "1" | "true" | "yes"
    ) {
        tls["insecure"] = json!(true);
    }
    Some(json!({
        "type": "anytls",
        "tag": "node",
        "server": host,
        "server_port": port,
        "password": password,
        "tls": tls
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine as _;

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    fn parse(line: &str) -> Value {
        parse_line(line, ParserMode::GenConfig).expect("node parses")
    }

    #[test]
    fn clean_keeps_plus_and_first_duplicate() {
        let query = clean("security=tls&sni=first&sni=second&pbk=a+b/c%3D&amp;x");
        assert_eq!(qget(&query, "security"), Some("tls"));
        assert_eq!(qget(&query, "sni"), Some("first"));
        assert_eq!(qget(&query, "pbk"), Some("a+b/c="));
        assert_eq!(qget(&query, "x"), Some(""));
    }

    #[test]
    fn hp_parse_rules() {
        assert_eq!(
            hp_parse("host.example:443"),
            Some(("host.example".into(), 443))
        );
        assert_eq!(
            hp_parse("host.example:443/path?x#y"),
            Some(("host.example".into(), 443))
        );
        assert_eq!(hp_parse("host.example:abc"), None);
        assert_eq!(hp_parse(":443"), None);
        assert_eq!(hp_parse("host.example:443x"), None);
        assert_eq!(
            hp_parse("host.example:00080"),
            Some(("host.example".into(), 80))
        );
    }

    #[test]
    fn vless_reality_key_translation() {
        let pbk = "AbCdEfGhIjKlMnOpQrStUvWxYz012345%2B%2F%3D";
        let node = parse(&format!(
            "vless://uuid@a.example.com:443?security=reality&pbk={pbk}&sid=ab&sni=x.example.com&fp=firefox&flow=xtls-rprx-vision&type=grpc&serviceName=svc"
        ));
        assert_eq!(
            node["tls"]["reality"]["public_key"],
            "AbCdEfGhIjKlMnOpQrStUvWxYz012345-_"
        );
        assert_eq!(node["tls"]["utls"]["fingerprint"], "firefox");
        assert_eq!(node["flow"], "xtls-rprx-vision");
        assert_eq!(node["transport"]["service_name"], "svc");
    }

    #[test]
    fn vless_rejects_xhttp_and_bad_ports() {
        assert!(parse_line(
            "vless://uuid@a.example.com:443?security=tls&type=xhttp",
            ParserMode::GenConfig
        )
        .is_none());
        assert!(parse_line(
            "vless://uuid@a.example.com:nope?security=tls",
            ParserMode::GenConfig
        )
        .is_none());
    }

    #[test]
    fn hysteria2_generator_tolerates_bad_ports() {
        let node = parse("hysteria2://pw@h.example.com:notaport?obfs=salamander&obfs-password=x");
        assert_eq!(node["server_port"], 443);
        assert_eq!(node["obfs"]["type"], "salamander");
        assert_eq!(node["obfs"]["password"], "x");
        assert!(parse_line("hysteria2://pw@h.example.com:notaport", ParserMode::Probe).is_none());
    }

    #[test]
    fn hysteria2_without_userinfo_keeps_its_quirks() {
        let node = parse("hy2://hostonly.example.com:8443?sni=x.example.com");
        assert_eq!(node["server"], "hostonly.example.com");
        assert_eq!(node["server_port"], 8443);
        // No '@': the password is the whole authority prefix.
        assert_eq!(node["password"], "hostonly.example.com:8443");
    }

    #[test]
    fn shadowsocks_variants() {
        let node = parse(&format!(
            "ss://{}@ss.example.com:8388#name",
            b64(b"aes-256-gcm:pass")
        ));
        assert_eq!(node["method"], "aes-256-gcm");
        assert_eq!(node["password"], "pass");
        let full = parse(&format!(
            "ss://{}#name",
            b64(b"chacha20-ietf-poly1305:pw@ss.example.com:8391")
        ));
        assert_eq!(full["password"], "pw");
        assert_eq!(full["server"], "ss.example.com");
        assert!(parse_line(
            "ss://aes-128-gcm:pw@ss.example.com:8388?plugin=obfs-local",
            ParserMode::GenConfig
        )
        .is_none());
    }

    #[test]
    fn trojan_probe_mode_never_returns_a_node() {
        let line = "trojan://pw@tj.example.com:443?sni=tj.example.com";
        assert!(parse_line(line, ParserMode::GenConfig).is_some());
        assert!(parse_line(line, ParserMode::Probe).is_none());
    }

    #[test]
    fn vmess_transports_and_security_normalisation() {
        let payload = serde_json::json!({
            "add": "vm.example.com", "port": "443", "id": "uuid",
            "scy": "weird", "aid": "7", "net": "grpc", "path": "/svc?ed=2048",
            "tls": "reality", "sni": "s.example.com",
            "pbk": "0123456789012345678901234567890123456789012", "sid": "x"
        });
        let line = format!("vmess://{}", b64(payload.to_string().as_bytes()));
        let node = parse(&line);
        assert_eq!(node["security"], "auto");
        assert_eq!(node["alter_id"], 7);
        assert_eq!(node["transport"]["service_name"], "svc");
        assert_eq!(
            node["tls"]["reality"]["public_key"],
            "0123456789012345678901234567890123456789012"
        );
    }

    #[test]
    fn parse_addr_matches_shell_regexes() {
        assert_eq!(
            parse_addr("vless://uuid@a.example.com:443?x=1"),
            Some(("a.example.com".into(), 443, "vless".into()))
        );
        assert_eq!(
            parse_addr("hy2://pw@b.example.com:8443"),
            Some(("b.example.com".into(), 8443, "hy2".into()))
        );
        assert_eq!(
            parse_addr("hysteria://c.example.com:36712?auth=x"),
            Some(("c.example.com".into(), 36712, "hysteria".into()))
        );
        // Fully base64-encoded shadowsocks has no userinfo '@' -> not scanned.
        assert_eq!(
            parse_addr("ss://YWVzLTI1Ni1nY206cGFzcw==@host:1"),
            Some(("host".into(), 1, "ss".into()))
        );
        assert_eq!(parse_addr("ss://YWVzLTI1Ni1nY206cGFzcw=="), None);
        assert_eq!(
            parse_addr("trojan://pw@host:443"),
            Some(("host".into(), 443, "trojan".into()))
        );
    }
}
