//! Alertmanager → Telegram webhook bridge.
//!
//! Listens on 127.0.0.1:9094 and forwards every Alertmanager webhook
//! notification to the configured chat, one line per alert. Bracketed
//! status/severity words read badly in a phone push, so each becomes one emoji
//! with no space between them: status first, severity second. The severity
//! emoji is kept only for warning/critical (info carries no news) and an
//! unknown value falls back to ❔, which keeps a push to one short line.
//!
//! The secrets are re-read on every request, so a chat-id change takes effect
//! without restarting the bridge.
//!
//! Environment:
//!   BRIDGE_TOKEN_PATH   decrypted bot token
//!   BRIDGE_CHAT_ID_PATH decrypted chat id
//!   BRIDGE_BIND         listen address (default 127.0.0.1:9094)
//!   BRIDGE_CURL, BRIDGE_PROXY, BRIDGE_API_BASE
//!   BRIDGE_ONCE=1       handle one request and exit (tests)

#[path = "lib.rs"]
mod shared;

use std::io::{Read, Write};
use std::net::TcpListener;
use std::process::{Command, Stdio};

use shared::json::Value;

const DEFAULT_CURL: &str = "/run/current-system/sw/bin/curl";
const DEFAULT_PROXY: &str = "socks5h://127.0.0.1:10808";
const DEFAULT_BIND: &str = "127.0.0.1:9094";
const DEFAULT_API_BASE: &str = "https://api.telegram.org";

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

fn read_secret(path: &str) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn status_emoji(status: &str) -> &'static str {
    match status.to_lowercase().as_str() {
        "firing" => "🔥",
        "resolved" => "✅",
        _ => "❔",
    }
}

fn severity_emoji(severity: &str) -> &'static str {
    match severity.to_lowercase().as_str() {
        "critical" => "🚨",
        "warning" => "⚠️",
        _ => "",
    }
}

fn text_field<'a>(value: &'a Value, key: &str, fallback: &'a str) -> &'a str {
    value.get(key).and_then(Value::as_str).unwrap_or(fallback)
}

/// Messages for one Alertmanager payload, in alert order.
pub fn messages(payload: &Value) -> Vec<String> {
    let Some(Value::Array(alerts)) = payload.get("alerts") else {
        return Vec::new();
    };
    alerts
        .iter()
        .map(|alert| {
            let status = text_field(alert, "status", "");
            let labels = alert.get("labels").unwrap_or(&Value::Null);
            let annotations = alert.get("annotations").unwrap_or(&Value::Null);
            let name = text_field(labels, "alertname", "Unknown");
            let severity = text_field(labels, "severity", "unknown");
            let summary = text_field(annotations, "summary", "No summary");
            format!(
                "{}{} {}: {}",
                status_emoji(status),
                severity_emoji(severity),
                name,
                summary
            )
        })
        .collect()
}

/// One Bot API sendMessage through curl, URL on stdin.
pub fn send(text: &str, token: &str, chat_id: &str) -> bool {
    let curl = env_or("BRIDGE_CURL", DEFAULT_CURL);
    let proxy = env_or("BRIDGE_PROXY", DEFAULT_PROXY);
    let base = env_or("BRIDGE_API_BASE", DEFAULT_API_BASE);
    let url = format!("{base}/bot{token}/sendMessage");
    let mut command = Command::new(curl);
    command.args(["-s", "-o", "/dev/null", "--proxy", &proxy, "-K", "-"]);
    command.args(["--data-urlencode", &format!("chat_id={chat_id}")]);
    command.args(["--data-urlencode", &format!("text={text}")]);
    command
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let Ok(mut child) = command.spawn() else {
        return false;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(shared::curl_url_config(&url).as_bytes());
    }
    child.wait().map(|status| status.success()).unwrap_or(false)
}

fn handle(mut stream: std::net::TcpStream) {
    let mut buffer = [0u8; 65536];
    let mut request = Vec::new();
    loop {
        match stream.read(&mut buffer) {
            Ok(0) => break,
            Ok(read) => {
                request.extend_from_slice(&buffer[..read]);
                if let Some(position) = find_header_end(&request) {
                    let head = String::from_utf8_lossy(&request[..position]).to_string();
                    let length = content_length(&head);
                    let body_start = position + 4;
                    while request.len() < body_start + length {
                        match stream.read(&mut buffer) {
                            Ok(0) => break,
                            Ok(read) => request.extend_from_slice(&buffer[..read]),
                            Err(_) => break,
                        }
                    }
                    let body = String::from_utf8_lossy(&request[body_start..]).to_string();
                    if let Some(payload) = shared::json::parse(&body) {
                        let token = read_secret(&env_or("BRIDGE_TOKEN_PATH", ""));
                        let chat_id = read_secret(&env_or("BRIDGE_CHAT_ID_PATH", ""));
                        if let (Some(token), Some(chat_id)) = (token, chat_id) {
                            for message in messages(&payload) {
                                send(&message, &token, &chat_id);
                            }
                        }
                    }
                    let _ = stream.write_all(
                        b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK",
                    );
                    let _ = stream.flush();
                    return;
                }
            }
            Err(_) => break,
        }
    }
    let _ = stream
        .write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
}

fn find_header_end(request: &[u8]) -> Option<usize> {
    request.windows(4).position(|window| window == b"\r\n\r\n")
}

fn content_length(head: &str) -> usize {
    head.lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            if name.trim().eq_ignore_ascii_case("content-length") {
                value.trim().parse().ok()
            } else {
                None
            }
        })
        .unwrap_or(0)
}

fn main() -> std::process::ExitCode {
    let bind = env_or("BRIDGE_BIND", DEFAULT_BIND);
    let listener = match TcpListener::bind(&bind) {
        Ok(listener) => listener,
        Err(exc) => {
            eprintln!("bridge: cannot listen on {bind}: {exc}");
            return std::process::ExitCode::from(1);
        }
    };
    let once =
        matches!(std::env::var("BRIDGE_ONCE"), Ok(value) if !value.is_empty() && value != "0");
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                handle(stream);
                if once {
                    break;
                }
            }
            Err(_) => break,
        }
    }
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn alerts_become_one_short_line_each() {
        let payload = shared::json::parse(
            r#"{"alerts": [
                {"status": "firing", "labels": {"alertname": "oom-kill", "severity": "critical"},
                 "annotations": {"summary": "1 OOM kill(s): node"}},
                {"status": "resolved", "labels": {"alertname": "systemd-failed-unit", "severity": "warning"},
                 "annotations": {"summary": "Systemd unit failed: foo.service"}},
                {"status": "firing", "labels": {"alertname": "x", "severity": "info"},
                 "annotations": {"summary": "quiet"}}
            ]}"#,
        )
        .expect("payload");
        assert_eq!(
            messages(&payload),
            vec![
                "🔥🚨 oom-kill: 1 OOM kill(s): node",
                "✅⚠️ systemd-failed-unit: Systemd unit failed: foo.service",
                "🔥 x: quiet",
            ]
        );
    }

    #[test]
    fn unknown_status_and_missing_fields_still_yield_a_line() {
        let payload = shared::json::parse(r#"{"alerts": [{}]}"#).expect("payload");
        assert_eq!(messages(&payload), vec!["❔ Unknown: No summary"]);
        assert!(messages(&shared::json::parse(r#"{"alerts": []}"#).unwrap()).is_empty());
        assert!(messages(&shared::json::parse(r#"{}"#).unwrap()).is_empty());
    }

    #[test]
    fn content_length_is_read_case_insensitively() {
        assert_eq!(content_length("POST / HTTP/1.1\r\nContent-Length: 42"), 42);
        assert_eq!(content_length("POST / HTTP/1.1\r\ncontent-length:7"), 7);
        assert_eq!(content_length("POST / HTTP/1.1"), 0);
    }
}
