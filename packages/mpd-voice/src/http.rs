//! A minimal HTTP/1.1 client for the loopback speech services.
//!
//! Both backends talk to services on this host (whisper on :8002, piper on
//! :8001), so the client covers exactly what they need: plain `http://`, a
//! request with `Content-Length`, and a response with either a
//! `Content-Length` or chunked framing. No TLS and no redirects — an `https`
//! URL is refused explicitly instead of silently mis-parsing.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
}

/// Parsed `http://host[:port]/path` URL.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Url {
    pub host: String,
    pub port: u16,
    pub path: String,
}

impl Url {
    pub fn parse(url: &str) -> Result<Url, String> {
        let rest = url
            .strip_prefix("http://")
            .ok_or_else(|| format!("unsupported URL (only http:// is handled): {url}"))?;
        let (authority, path) = match rest.find('/') {
            Some(index) => (&rest[..index], &rest[index..]),
            None => (rest, "/"),
        };
        let (host, port) = match authority.rsplit_once(':') {
            Some((host, port)) => (
                host.to_string(),
                port.parse::<u16>()
                    .map_err(|_| format!("bad port in URL: {url}"))?,
            ),
            None => (authority.to_string(), 80),
        };
        if host.is_empty() {
            return Err(format!("bad URL: {url}"));
        }
        Ok(Url {
            host,
            port,
            path: path.to_string(),
        })
    }
}

fn exchange(
    url: &Url,
    method: &str,
    headers: &[(&str, String)],
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    let address = (url.host.as_str(), url.port)
        .to_socket_addrs()
        .map_err(|exc| format!("cannot resolve {}: {exc}", url.host))?
        .next()
        .ok_or_else(|| format!("cannot resolve {}", url.host))?;
    let mut stream = TcpStream::connect_timeout(&address, timeout)
        .map_err(|exc| format!("cannot connect to {}:{}: {exc}", url.host, url.port))?;
    stream.set_read_timeout(Some(timeout)).ok();
    stream.set_write_timeout(Some(timeout)).ok();

    let mut request = format!("{method} {} HTTP/1.1\r\nHost: {}\r\n", url.path, url.host);
    request.push_str("Connection: close\r\n");
    for (name, value) in headers {
        request.push_str(&format!("{name}: {value}\r\n"));
    }
    request.push_str(&format!("Content-Length: {}\r\n\r\n", body.len()));
    stream
        .write_all(request.as_bytes())
        .and_then(|()| stream.write_all(body))
        .and_then(|()| stream.flush())
        .map_err(|exc| format!("cannot send request to {}:{}: {exc}", url.host, url.port))?;

    let mut reader = BufReader::new(stream);
    let mut status_line = String::new();
    reader
        .read_line(&mut status_line)
        .map_err(|exc| format!("cannot read the response status: {exc}"))?;
    let status = status_line
        .split_whitespace()
        .nth(1)
        .and_then(|code| code.parse::<u16>().ok())
        .ok_or_else(|| format!("bad status line: {}", status_line.trim()))?;

    let mut length: Option<usize> = None;
    let mut chunked = false;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() {
            break;
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some((name, value)) = line.split_once(':') {
            let name = name.trim().to_ascii_lowercase();
            let value = value.trim();
            match name.as_str() {
                "content-length" => length = value.parse().ok(),
                "transfer-encoding" if value.eq_ignore_ascii_case("chunked") => chunked = true,
                _ => {}
            }
        }
    }

    let mut body_out = Vec::new();
    if chunked {
        loop {
            let mut size_line = String::new();
            if reader.read_line(&mut size_line).is_err() {
                break;
            }
            let size_text = size_line.trim();
            if size_text.is_empty() {
                break;
            }
            let Ok(size) = usize::from_str_radix(size_text, 16) else {
                break;
            };
            if size == 0 {
                break;
            }
            let mut chunk = vec![0u8; size];
            if reader.read_exact(&mut chunk).is_err() {
                break;
            }
            body_out.extend_from_slice(&chunk);
            let mut crlf = [0u8; 2];
            let _ = reader.read_exact(&mut crlf);
        }
    } else if let Some(length) = length {
        body_out.resize(length, 0);
        let _ = reader.read_exact(&mut body_out);
    } else {
        let _ = reader.read_to_end(&mut body_out);
    }
    Ok(Response {
        status,
        body: body_out,
    })
}

pub fn get(url: &str, timeout: Duration) -> Result<Response, String> {
    let url = Url::parse(url)?;
    exchange(&url, "GET", &[], &[], timeout)
}

pub fn post(
    url: &str,
    content_type: &str,
    body: &[u8],
    timeout: Duration,
) -> Result<Response, String> {
    let url = Url::parse(url)?;
    exchange(
        &url,
        "POST",
        &[("Content-Type", content_type.to_string())],
        body,
        timeout,
    )
}

/// Percent-free JSON string escaping for the small payloads we send.
pub fn json_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out
}

/// Value of one top-level string field of a JSON object.
///
/// The speech endpoints answer `{"text": "..."}` or `{"data": [...]}`, so a
/// full parser would be dead weight; the scan tracks string state and brace
/// depth so a nested field cannot be mistaken for the top-level one.
pub fn json_string_field(document: &str, field: &str) -> Option<String> {
    let chars: Vec<char> = document.chars().collect();
    let mut index = 0;
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;
    let mut current_key = String::new();
    let mut key_ready = false;
    while index < chars.len() {
        let ch = chars[index];
        if in_string {
            if escaped {
                current_key.push(ch);
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
                if depth == 1 && !key_ready {
                    key_ready = true;
                }
            } else if depth == 1 && !key_ready {
                current_key.push(ch);
            }
            index += 1;
            continue;
        }
        match ch {
            '"' => {
                in_string = true;
                if key_ready {
                    // This is the value string of the key we just read.
                    if current_key == field {
                        let (value, next) = read_json_string(&chars, index)?;
                        return Some(value).filter(|_| next > index);
                    }
                    key_ready = false;
                    current_key.clear();
                } else {
                    current_key.clear();
                }
            }
            '{' => depth += 1,
            '}' => depth = depth.saturating_sub(1),
            ',' => {
                if depth == 1 {
                    key_ready = false;
                    current_key.clear();
                }
            }
            _ => {}
        }
        index += 1;
    }
    None
}

fn read_json_string(chars: &[char], start: usize) -> Option<(String, usize)> {
    let mut out = String::new();
    let mut index = start + 1;
    while index < chars.len() {
        match chars[index] {
            '"' => return Some((out, index + 1)),
            '\\' => {
                index += 1;
                let escaped = *chars.get(index)?;
                out.push(match escaped {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    'u' => ' ',
                    other => other,
                });
            }
            ch => out.push(ch),
        }
        index += 1;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls_split_into_host_port_and_path() {
        assert_eq!(
            Url::parse("http://127.0.0.1:8002/v1/models").unwrap(),
            Url {
                host: "127.0.0.1".to_string(),
                port: 8002,
                path: "/v1/models".to_string()
            }
        );
        assert_eq!(
            Url::parse("http://localhost").unwrap(),
            Url {
                host: "localhost".to_string(),
                port: 80,
                path: "/".to_string()
            }
        );
        assert!(Url::parse("https://example.com/x").is_err());
    }

    #[test]
    fn json_field_is_found() {
        assert_eq!(
            json_string_field(r#"{"text": " next track "}"#, "text").as_deref(),
            Some(" next track ")
        );
        assert_eq!(
            json_string_field(r#"{"data": [{"id": "stub"}]}"#, "text"),
            None
        );
        assert_eq!(
            json_string_field(r#"{"a": "x", "text": "y"}"#, "text").as_deref(),
            Some("y")
        );
        assert_eq!(
            json_string_field(r#"{"text": "a\"b"}"#, "text").as_deref(),
            Some("a\"b")
        );
    }

    #[test]
    fn json_escape_handles_quotes_and_unicode() {
        assert_eq!(json_escape("a\"b"), "a\\\"b");
        assert_eq!(json_escape("Зиновия"), "Зиновия");
    }
}
