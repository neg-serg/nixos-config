//! Minimal HTTP abstraction.
//!
//! Only three requests exist in the tool and each needs slightly different
//! failure handling:
//! - the Sourcegraph search stream must keep a partial body when the deadline
//!   expires (curl's `--max-time` leaves a valid prefix, the shell noted it);
//! - raw.githubusercontent.com candidates just fail and move on;
//! - the Shadertoy API distinguishes a transport failure from an HTTP error
//!   body, because the shell printed two different diagnostics.
//!
//! `HttpError::Transport` therefore carries the bytes read so far. Status
//! errors carry no body: `curl -f` discarded it, so the shell never saw one.

use std::io::Read;
use std::time::Duration;

#[derive(Debug)]
pub struct Request<'a> {
    pub url: &'a str,
    pub timeout: Duration,
    pub proxy: Option<&'a str>,
    pub headers: &'a [(&'a str, &'a str)],
}

#[derive(Debug)]
pub enum HttpError {
    /// Connection/TLS/timeout failure, possibly after a readable prefix.
    Transport { partial: Vec<u8>, message: String },
    /// HTTP status >= 400 (`curl -f`).
    Status { code: u16 },
}

pub trait Http {
    fn fetch(&self, request: &Request<'_>) -> Result<Vec<u8>, HttpError>;
}

/// reqwest with blocking I/O, rustls and SOCKS support.
pub struct ReqwestHttp;

impl ReqwestHttp {
    pub fn new() -> Self {
        Self
    }
}

impl Default for ReqwestHttp {
    fn default() -> Self {
        Self::new()
    }
}

impl Http for ReqwestHttp {
    fn fetch(&self, request: &Request<'_>) -> Result<Vec<u8>, HttpError> {
        let mut builder = reqwest::blocking::Client::builder()
            .timeout(request.timeout)
            // curl only followed redirects with -L, which the shell did not use.
            .redirect(reqwest::redirect::Policy::none());
        if let Some(proxy) = request.proxy {
            let proxy = reqwest::Proxy::all(proxy).map_err(|error| HttpError::Transport {
                partial: Vec::new(),
                message: error.to_string(),
            })?;
            builder = builder.proxy(proxy);
        }
        let client = builder.build().map_err(|error| HttpError::Transport {
            partial: Vec::new(),
            message: error.to_string(),
        })?;

        let mut http_request = client.get(request.url);
        for (name, value) in request.headers {
            http_request = http_request.header(*name, *value);
        }

        let mut response = http_request.send().map_err(|error| HttpError::Transport {
            partial: Vec::new(),
            message: error.to_string(),
        })?;
        let status = response.status();
        if !status.is_success() {
            return Err(HttpError::Status {
                code: status.as_u16(),
            });
        }

        let mut body = Vec::new();
        let mut chunk = [0u8; 16 * 1024];
        loop {
            match response.read(&mut chunk) {
                Ok(0) => return Ok(body),
                Ok(read) => body.extend_from_slice(&chunk[..read]),
                Err(error) => {
                    return Err(HttpError::Transport {
                        partial: body,
                        message: error.to_string(),
                    });
                }
            }
        }
    }
}
