//! Proxy-environment tests, in their own test binary so the environment is
//! not shared with the other integration tests.
//!
//! curl honoured `ALL_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY` and `NO_PROXY`; the
//! worker's HTTP layer must do the same. Both tests prove it against a local
//! stand-in for the proxy — no real proxy, no real host.

mod support;

use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::thread;

use support::*;

#[test]
fn http_proxy_is_used_for_plain_http_targets() {
    // The proxy receives the absolute-form request line and answers it.
    let proxy = Mock::start(|request| {
        if request
            .target
            .starts_with("http://api.example/v1/forecast?latitude=59.9&longitude=30.7&")
        {
            Response::json(FORECAST)
        } else {
            Response::error(404)
        }
    });
    let directory = TempDir::new("http-proxy");
    let cache = directory.cache_file();
    let proxy_url = proxy.base().to_string();
    let args = vec![
        "--cache-file".to_string(),
        cache.to_string_lossy().into_owned(),
        "--once".to_string(),
        "--lat".to_string(),
        "59.9".to_string(),
        "--lon".to_string(),
        "30.7".to_string(),
        "--api-base".to_string(),
        "http://api.example/v1".to_string(),
        // One provider only: the fallback would dial the real wttr.in and
        // api.met.no (its bases are not overridden here) and this test is about
        // the proxy variable, not about the race between providers.
        "--no-fallback".to_string(),
        "--timeout".to_string(),
        "5".to_string(),
    ];
    let output = run(&args, &[("HTTP_PROXY", proxy_url.as_str())]);
    assert_eq!(output.status.code(), Some(0));
    let lines: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| line.to_string())
        .collect();
    let sample = parse_line(&lines[1]);
    assert_eq!(sample["ok"], true, "{}", lines[1]);
    assert_eq!(sample["data"]["provider"], "open-meteo");
    let target = proxy
        .requests()
        .first()
        .map(|request| request.target.clone())
        .expect("the proxy was not used");
    assert!(
        target.starts_with("http://api.example/v1/forecast?latitude=59.9&longitude=30.7&"),
        "{target}"
    );
}

/// A minimal SOCKS5 server: no-auth greeting, one CONNECT, then it serves a
/// canned HTTP response over the tunnel. It records the requested
/// `host:port`, which proves socks5h resolved the name proxy-side.
fn start_socks_server(body: &'static str) -> (String, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind socks listener");
    let address = listener.local_addr().expect("socks address");
    let seen = Arc::new(Mutex::new(Vec::new()));
    let record = Arc::clone(&seen);
    thread::spawn(move || {
        let Ok((mut stream, _)) = listener.accept() else {
            return;
        };
        let mut greeting = [0_u8; 2];
        if stream.read_exact(&mut greeting).is_err() {
            return;
        }
        let mut methods = vec![0_u8; greeting[1] as usize];
        if stream.read_exact(&mut methods).is_err() {
            return;
        }
        // Version 5, no authentication required.
        if stream.write_all(&[5, 0]).is_err() {
            return;
        }
        let mut header = [0_u8; 4];
        if stream.read_exact(&mut header).is_err() {
            return;
        }
        let host = match header[3] {
            3 => {
                let mut length = [0_u8; 1];
                if stream.read_exact(&mut length).is_err() {
                    return;
                }
                let mut name = vec![0_u8; length[0] as usize];
                if stream.read_exact(&mut name).is_err() {
                    return;
                }
                String::from_utf8_lossy(&name).into_owned()
            }
            1 => {
                let mut octets = [0_u8; 4];
                if stream.read_exact(&mut octets).is_err() {
                    return;
                }
                format!("{}.{}.{}.{}", octets[0], octets[1], octets[2], octets[3])
            }
            _ => return,
        };
        let mut port = [0_u8; 2];
        if stream.read_exact(&mut port).is_err() {
            return;
        }
        record
            .lock()
            .expect("socks record")
            .push(format!("{host}:{}", u16::from_be_bytes(port)));
        // Success, IPv4 0.0.0.0:0.
        if stream.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).is_err() {
            return;
        }
        // Read the tunnelled HTTP request head, then answer it.
        let mut request = Vec::new();
        let mut byte = [0_u8; 1];
        while !request.ends_with(b"\r\n\r\n") {
            match stream.read(&mut byte) {
                Ok(0) | Err(_) => return,
                Ok(_) => request.push(byte[0]),
            }
        }
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        );
        let _ = stream.write_all(response.as_bytes());
        let _ = stream.flush();
    });
    (format!("socks5h://127.0.0.1:{}", address.port()), seen)
}

#[test]
fn socks5h_all_proxy_resolves_the_host_on_the_proxy() {
    let (proxy_url, seen) = start_socks_server(FORECAST);
    let directory = TempDir::new("socks-proxy");
    let cache = directory.cache_file();
    let args = vec![
        "--cache-file".to_string(),
        cache.to_string_lossy().into_owned(),
        "--once".to_string(),
        "--lat".to_string(),
        "59.9".to_string(),
        "--lon".to_string(),
        "30.7".to_string(),
        // A name that does not resolve locally: only the proxy can reach it.
        "--api-base".to_string(),
        "http://api.example/v1".to_string(),
        // As above, and for a second reason: this SOCKS server serves exactly
        // one connection, so a concurrent fallback attempt would claim it.
        "--no-fallback".to_string(),
        "--timeout".to_string(),
        "5".to_string(),
    ];
    let output = run(&args, &[("ALL_PROXY", proxy_url.as_str())]);
    assert_eq!(output.status.code(), Some(0));
    let lines: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| line.to_string())
        .collect();
    let sample = parse_line(&lines[1]);
    assert_eq!(
        sample["ok"], true,
        "the SOCKS proxy was not used: {}",
        lines[1]
    );
    assert_eq!(sample["data"]["provider"], "open-meteo");
    let recorded = seen.lock().expect("socks record").clone();
    assert_eq!(recorded, vec!["api.example:80".to_string()]);
}
