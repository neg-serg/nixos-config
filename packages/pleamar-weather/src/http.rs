//! The HTTP layer: one blocking GET, curl's error spelling, and an
//! interruptible wait.
//!
//! The shell ran
//!
//! ```text
//! curl --fail --silent --show-error --location --max-time N \
//!      --user-agent UA URL
//! ```
//!
//! and used the last line of curl's stderr as the error text. This module
//! keeps the request (same URL bytes, `User-Agent`, `Accept: */*`, 50
//! redirects, one total deadline) and reproduces curl's wording for the cases
//! a caller can hit deterministically:
//!
//! - HTTP status >= 400: `curl: (22) The requested URL returned error: NNN`;
//! - the deadline:        `curl: (28) Operation timed out after N milliseconds
//!                          with 0 bytes received`;
//! - name resolution:     `curl: (6) Could not resolve host: HOST`;
//! - refused/unreachable: `curl: (7) Failed to connect to HOST:PORT ...`.
//!
//! Other transport failures keep curl's code family but carry the reqwest
//! text, because there is no deterministic translation (curl's `(7)` message
//! embeds a measured connect time, TLS errors carry the library's wording, …).
//! They are human-facing text on stderr-equivalent error lines, never protocol
//! data.
//!
//! # Proxies
//!
//! `reqwest` enables environment proxies by default, and on Linux that means
//! exactly the variables curl reads: `ALL_PROXY`/`all_proxy`,
//! `HTTP_PROXY`/`http_proxy`, `HTTPS_PROXY`/`https_proxy`,
//! `NO_PROXY`/`no_proxy` (hyper-util's `Matcher::from_system` falls back to
//! `Matcher::from_env`, which reads that list; macOS/Windows additionally read
//! the OS settings). The `socks` feature above makes `socks5h://` proxy URLs
//! work, which is the form this host's sing-box proxy uses — curl resolves the
//! hostname on the proxy side for `socks5h`, and so does reqwest. Two
//! documented differences remain:
//!
//! - hyper-util disables proxy variables when `REQUEST_METHOD` is set (the
//!   CGI/HTTPoxy guard); curl still honours them there. The worker is never
//!   spawned by CGI, so this cannot trigger in pleamar.
//! - proxy failures name the target host rather than the proxy host.
//!
//! `tests/proxy.rs` proves the environment path against a local SOCKS5 server,
//! so this is verified behaviour, not a reading of the documentation.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::time::Duration;

use reqwest::blocking::Client;
use reqwest::redirect::Policy;

/// How often the waiting thread notices SIGTERM/SIGINT while a request runs.
/// `reqwest` cannot cancel a blocking socket read, so the request lives on a
/// helper thread and the process exits (killing it) as soon as the flag flips.
const INTERRUPT_POLL: Duration = Duration::from_millis(20);

#[derive(Debug)]
pub enum FetchError {
    /// curl-stderr-equivalent text.
    Message(String),
    /// SIGTERM/SIGINT arrived while the request was in flight.
    Interrupted,
}

pub struct Http {
    client: Result<Client, String>,
    timeout_secs: u64,
    interrupt: Arc<AtomicBool>,
}

impl Http {
    pub fn new(timeout_secs: u64, user_agent: &str, interrupt: Arc<AtomicBool>) -> Self {
        // curl sends `Accept: */*` unless told otherwise.
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::ACCEPT,
            reqwest::header::HeaderValue::from_static("*/*"),
        );
        let client = Client::builder()
            .user_agent(user_agent)
            .timeout(Duration::from_secs(timeout_secs))
            // curl's `--location` default: up to 50 redirects.
            .redirect(Policy::limited(50))
            .default_headers(headers)
            .build()
            .map_err(|error| format!("curl: (5) {error}"));
        Self {
            client,
            timeout_secs,
            interrupt,
        }
    }

    /// One GET. The body is returned as text (curl wrote bytes, bash then held
    /// text; JSON and wttr's one-line format are ASCII/UTF-8 in practice).
    pub fn get(&self, url: &str) -> Result<String, FetchError> {
        let client = match &self.client {
            Ok(client) => client.clone(),
            Err(message) => return Err(FetchError::Message(message.clone())),
        };
        let url = url.to_string();
        let timeout_secs = self.timeout_secs;

        let (sender, receiver) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = sender.send(perform(&client, &url, timeout_secs));
        });

        loop {
            match receiver.recv_timeout(INTERRUPT_POLL) {
                Ok(result) => return result,
                Err(RecvTimeoutError::Timeout) => {
                    if self.interrupt.load(Ordering::Relaxed) {
                        return Err(FetchError::Interrupted);
                    }
                }
                // The helper thread cannot disappear without sending; treat it
                // as a transport failure rather than hanging.
                Err(RecvTimeoutError::Disconnected) => {
                    return Err(FetchError::Message(
                        "curl: (7) request thread stopped".to_string(),
                    ));
                }
            }
        }
    }
}

fn perform(client: &Client, url: &str, timeout_secs: u64) -> Result<String, FetchError> {
    let parsed = reqwest::Url::parse(url).ok();
    let response = client.get(url).send().map_err(|error| {
        FetchError::Message(curl_message(&error, timeout_secs, parsed.as_ref()))
    })?;
    let status = response.status();
    // curl's `--fail`: any 4xx/5xx is an error and the body is not used.
    if status.as_u16() >= 400 {
        return Err(FetchError::Message(format!(
            "curl: (22) The requested URL returned error: {}",
            status.as_u16()
        )));
    }
    response
        .text()
        .map_err(|error| FetchError::Message(format!("curl: (18) {error}")))
}

fn curl_message(error: &reqwest::Error, timeout_secs: u64, url: Option<&reqwest::Url>) -> String {
    if error.is_timeout() {
        return format!(
            "curl: (28) Operation timed out after {} milliseconds with 0 bytes received",
            timeout_secs.saturating_mul(1000)
        );
    }
    if error.is_redirect() {
        return "curl: (47) Maximum (50) redirects followed".to_string();
    }
    if error.is_connect() {
        let host = url.and_then(reqwest::Url::host_str).unwrap_or("");
        if source_mentions_dns(error) {
            return format!("curl: (6) Could not resolve host: {host}");
        }
        let port = url
            .and_then(reqwest::Url::port_or_known_default)
            .unwrap_or(0);
        return format!(
            "curl: (7) Failed to connect to {host}:{port} after 0 ms: Could not connect to server"
        );
    }
    if error.is_builder() {
        return format!("curl: (3) URL rejected: {error}");
    }
    format!("curl: (7) {error}")
}

/// A name-resolution failure surfaces as a source in the error chain
/// ("dns error: failed to lookup address information: …"); a refused
/// connection does not.
fn source_mentions_dns(error: &reqwest::Error) -> bool {
    let mut source: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(current) = source {
        let text = current.to_string().to_ascii_lowercase();
        if text.contains("dns") || text.contains("lookup address") || text.contains("resolve host")
        {
            return true;
        }
        source = current.source();
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_client_builds_with_the_worker_defaults() {
        let interrupt = Arc::new(AtomicBool::new(false));
        let http = Http::new(8, "pleamar-weather/1.0", interrupt);
        assert!(http.client.is_ok(), "client construction must not fail");
        assert_eq!(http.timeout_secs, 8);
    }
}
