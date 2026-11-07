//! The local-LLM probe: llama-swap's `/running` answer plus the DRM card's
//! VRAM counters, folded into one object per sample.
//!
//! Why here and not in the bar's logic: a scene that polled this with `curl`
//! once a second would pay a process start per tick. The sysmon worker already
//! runs for the bar, so one small HTTP GET per sample is nearly free and the
//! indicator arrives with the rest of the system numbers.
//!
//! Plain HTTP/1.1 over a localhost socket on purpose: the endpoint is local and
//! unencrypted, and the worker has no HTTP dependency. `Connection: close` plus
//! `Content-Length` is what llama-swap answers; a chunked body is not expected
//! from it, and an unexpected shape reads as "idle" rather than stalling.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::Value;

/// The dGPU (the card that can hold a model) is the one above this size; the
/// iGPU reports 2 GiB. The probe picks the largest qualifying card so a future
/// second dGPU does not silently become "the" card.
const VRAM_MIN: u64 = 8 * 1024 * 1024 * 1024;
const HTTP_TIMEOUT: Duration = Duration::from_millis(500);

pub struct LlmProbe {
    host: String,
    port: u16,
    path: String,
    vram_used: Option<PathBuf>,
    vram_total: Option<PathBuf>,
    model: String,
    since: u64,
}

impl LlmProbe {
    /// `url` is the full `/running` endpoint, e.g.
    /// `http://127.0.0.1:9292/running`. An unparsable URL means no probe.
    pub fn new(url: &str) -> Option<Self> {
        let (host, port, path) = parse_url(url)?;
        let (vram_used, vram_total) = match discover_vram() {
            Some((used, total)) => (Some(used), Some(total)),
            None => (None, None),
        };
        Some(Self {
            host,
            port,
            path,
            vram_used,
            vram_total,
            model: String::new(),
            since: 0,
        })
    }

    /// One object for the sample. `now` is epoch seconds; `loaded_sec` counts
    /// from the first sample that saw the current model, so the bar can show
    /// how long the card has been held.
    pub fn object(&mut self, now: u64) -> String {
        let (model, state, ttl) = match self.get() {
            Some(body) => parse_running(&body),
            None => (String::new(), String::new(), 0),
        };
        if model.is_empty() {
            self.model.clear();
            self.since = 0;
        } else if self.model != model {
            self.model = model.clone();
            self.since = now;
        }
        let loaded = if self.since > 0 {
            now.saturating_sub(self.since)
        } else {
            0
        };
        let used = self
            .vram_used
            .as_ref()
            .and_then(|path| read_gib(path))
            .unwrap_or(0.0);
        let total = self
            .vram_total
            .as_ref()
            .and_then(|path| read_gib(path))
            .unwrap_or(0.0);
        format!(
            "{{\"active\":{},\"model\":{},\"state\":{},\"ttl\":{},\"loaded_sec\":{},\"vram_used_gib\":{used:.1},\"vram_total_gib\":{total:.1}}}",
            if model.is_empty() { "false" } else { "true" },
            json(&model),
            json(&state),
            ttl,
            loaded
        )
    }

    fn get(&self) -> Option<String> {
        let address = (self.host.as_str(), self.port)
            .to_socket_addrs()
            .ok()?
            .next()?;
        let mut stream = TcpStream::connect_timeout(&address, HTTP_TIMEOUT).ok()?;
        stream.set_read_timeout(Some(HTTP_TIMEOUT)).ok()?;
        stream.set_write_timeout(Some(HTTP_TIMEOUT)).ok()?;
        write!(
            stream,
            "GET {} HTTP/1.1\r\nHost: {}:{}\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
            self.path, self.host, self.port
        )
        .ok()?;
        let mut response = Vec::new();
        stream.read_to_end(&mut response).ok()?;
        if !(response.starts_with(b"HTTP/1.1 200") || response.starts_with(b"HTTP/1.0 200")) {
            return None;
        }
        let split = response
            .windows(4)
            .position(|window| window == b"\r\n\r\n")?;
        String::from_utf8(response[split + 4..].to_vec()).ok()
    }
}

/// `http://host:port/path` → its three pieces. HTTPS is refused: the local
/// router does not serve it and a TLS stack here would be a dependency for
/// nothing.
fn parse_url(url: &str) -> Option<(String, u16, String)> {
    let rest = url.strip_prefix("http://")?;
    let (authority, path) = match rest.find('/') {
        Some(index) => (&rest[..index], &rest[index..]),
        None => (rest, "/running"),
    };
    let authority = authority.rsplit('@').next()?;
    let (host, port) = match authority.rsplit_once(':') {
        Some((host, port)) => (host, port.parse::<u16>().ok()?),
        None => (authority, 80),
    };
    if host.is_empty() {
        return None;
    }
    Some((host.to_string(), port, path.to_string()))
}

/// llama-swap's `{"running":[{"model":"…","state":"…","ttl":60,…}]}`. The
/// array is empty when no model is resident; only the first entry matters
/// because the router serves one model at a time.
fn parse_running(body: &str) -> (String, String, u64) {
    let Ok(value) = serde_json::from_str::<Value>(body) else {
        return (String::new(), String::new(), 0);
    };
    let Some(first) = value
        .get("running")
        .and_then(Value::as_array)
        .and_then(|running| running.first())
    else {
        return (String::new(), String::new(), 0);
    };
    let model = first
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let state = first
        .get("state")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let ttl = first.get("ttl").and_then(Value::as_u64).unwrap_or(0);
    (model, state, ttl)
}

/// The largest `/sys/class/drm/cardN/device` whose `mem_info_vram_total` is
/// above [`VRAM_MIN`], as `(used, total)` paths.
fn discover_vram() -> Option<(PathBuf, PathBuf)> {
    let mut best: Option<(u64, PathBuf, PathBuf)> = None;
    for entry in std::fs::read_dir("/sys/class/drm").ok()?.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        // `card0` is the card; `card0-DP-1` is a connector.
        if !name.starts_with("card") || name.contains('-') {
            continue;
        }
        let device = entry.path().join("device");
        let total_path = device.join("mem_info_vram_total");
        let used_path = device.join("mem_info_vram_used");
        let Some(total) = read_u64(&total_path) else {
            continue;
        };
        if total <= VRAM_MIN {
            continue;
        }
        if best
            .as_ref()
            .map_or(true, |(best_total, _, _)| total > *best_total)
        {
            best = Some((total, used_path, total_path));
        }
    }
    best.map(|(_, used, total)| (used, total))
}

fn read_u64(path: &Path) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn read_gib(path: &Path) -> Option<f64> {
    read_u64(path).map(|bytes| bytes as f64 / (1024.0 * 1024.0 * 1024.0))
}

/// A JSON string literal for the model/state fields, which are the only free
/// text here. serde_json is already a dependency of the worker.
fn json(value: &str) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "\"\"".to_string())
}

#[cfg(test)]
mod tests {
    use super::{parse_running, parse_url};

    #[test]
    fn url_is_split_into_host_port_and_path() {
        assert_eq!(
            parse_url("http://127.0.0.1:9292/running"),
            Some(("127.0.0.1".to_string(), 9292, "/running".to_string()))
        );
        assert_eq!(
            parse_url("http://localhost"),
            Some(("localhost".to_string(), 80, "/running".to_string()))
        );
        assert_eq!(parse_url("https://127.0.0.1:9292/running"), None);
        assert_eq!(parse_url("127.0.0.1:9292/running"), None);
    }

    #[test]
    fn running_entry_is_read_and_idle_is_empty() {
        let body = r#"{"running":[{"model":"qwen3.6-35b-abliterated","state":"ready","cmd":"x","ttl":60}]}"#;
        assert_eq!(
            parse_running(body),
            (
                "qwen3.6-35b-abliterated".to_string(),
                "ready".to_string(),
                60
            )
        );
        assert_eq!(
            parse_running(r#"{"running":[]}"#),
            (String::new(), String::new(), 0)
        );
        assert_eq!(parse_running("not json"), (String::new(), String::new(), 0));
    }
}
