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

fn proxy_args() -> Vec<String> {
    vec![
        "--once".to_string(),
        "--month".to_string(),
        "2026-11".to_string(),
        "--country".to_string(),
        "RU".to_string(),
        "--holidays-base".to_string(),
        "http://api.example/v3".to_string(),
        "--workdays-base".to_string(),
        "http://api.example/getdata".to_string(),
    ]
}

fn proxy_response(target: &str) -> Response {
    // Absolute-form through an HTTP proxy, origin-form inside a SOCKS tunnel.
    if target.contains("/v3/PublicHolidays/") {
        Response::json(HOLIDAYS)
    } else if target.contains("/getdata?") {
        Response::text(WORKDAYS)
    } else {
        Response::error(404)
    }
}

#[test]
fn http_proxy_is_used_for_plain_http_targets() {
    // The proxy receives the absolute-form request line and answers it.
    let proxy = Mock::start(|request| proxy_response(&request.target));
    let sandbox = Sandbox::new("http-proxy");
    let proxy_url = proxy.base().to_string();
    let output = sandbox.run(&proxy_args(), &[("HTTP_PROXY", proxy_url.as_str())]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let sample = parse_line(&lines(&output)[1]);
    assert_eq!(sample["ok"], true, "{}", sample);
    assert_eq!(
        sample["data"]["holidays"]
            .as_array()
            .expect("holidays")
            .len(),
        1,
        "the proxy was not used"
    );
    let targets: Vec<String> = proxy
        .requests()
        .into_iter()
        .map(|request| request.target)
        .collect();
    assert_eq!(
        targets,
        vec![
            "http://api.example/v3/PublicHolidays/2026/RU".to_string(),
            "http://api.example/getdata?year=2026&month=11&cc=RU".to_string()
        ]
    );
}

/// A minimal SOCKS5 server: no-auth greeting, CONNECT, then a canned HTTP
/// answer over the tunnel. It records the requested `host:port`, which proves
/// socks5h resolved the name proxy-side.
fn start_socks_server() -> (String, Arc<Mutex<Vec<String>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind socks listener");
    let address = listener.local_addr().expect("socks address");
    let seen = Arc::new(Mutex::new(Vec::new()));
    let record = Arc::clone(&seen);
    thread::spawn(move || {
        // The worker makes two requests (holidays, then workdays) and the
        // answers close each tunnel, so accept two connections.
        for _ in 0..2 {
            let Ok((mut stream, _)) = listener.accept() else {
                return;
            };
            if !serve_socks_tunnel(&mut stream, &record) {
                return;
            }
        }
    });
    (format!("socks5h://127.0.0.1:{}", address.port()), seen)
}

fn serve_socks_tunnel(stream: &mut std::net::TcpStream, record: &Arc<Mutex<Vec<String>>>) -> bool {
    let mut greeting = [0_u8; 2];
    if stream.read_exact(&mut greeting).is_err() {
        return false;
    }
    let mut methods = vec![0_u8; greeting[1] as usize];
    if stream.read_exact(&mut methods).is_err() {
        return false;
    }
    // Version 5, no authentication required.
    if stream.write_all(&[5, 0]).is_err() {
        return false;
    }
    let mut header = [0_u8; 4];
    if stream.read_exact(&mut header).is_err() {
        return false;
    }
    let host = match header[3] {
        3 => {
            let mut length = [0_u8; 1];
            if stream.read_exact(&mut length).is_err() {
                return false;
            }
            let mut name = vec![0_u8; length[0] as usize];
            if stream.read_exact(&mut name).is_err() {
                return false;
            }
            String::from_utf8_lossy(&name).into_owned()
        }
        1 => {
            let mut octets = [0_u8; 4];
            if stream.read_exact(&mut octets).is_err() {
                return false;
            }
            format!("{}.{}.{}.{}", octets[0], octets[1], octets[2], octets[3])
        }
        _ => return false,
    };
    let mut port = [0_u8; 2];
    if stream.read_exact(&mut port).is_err() {
        return false;
    }
    record
        .lock()
        .expect("socks record")
        .push(format!("{host}:{}", u16::from_be_bytes(port)));
    // Success, IPv4 0.0.0.0:0.
    if stream.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).is_err() {
        return false;
    }
    // Read the tunnelled HTTP request head, then answer it.
    let mut request = Vec::new();
    let mut byte = [0_u8; 1];
    while !request.ends_with(b"\r\n\r\n") {
        match stream.read(&mut byte) {
            Ok(0) | Err(_) => return false,
            Ok(_) => request.push(byte[0]),
        }
    }
    let request = String::from_utf8_lossy(&request);
    let target = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .unwrap_or_default();
    let response = proxy_response(target);
    let head = format!(
        "HTTP/1.1 {} OK\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        response.status,
        response.content_type,
        response.body.len()
    );
    if stream.write_all(head.as_bytes()).is_err() {
        return false;
    }
    stream.write_all(response.body.as_bytes()).is_ok()
}

#[test]
fn socks5h_all_proxy_resolves_the_host_on_the_proxy() {
    let (proxy_url, seen) = start_socks_server();
    let sandbox = Sandbox::new("socks-proxy");
    let output = sandbox.run(&proxy_args(), &[("ALL_PROXY", proxy_url.as_str())]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let sample = parse_line(&lines(&output)[1]);
    assert_eq!(sample["ok"], true, "{}", sample);
    assert_eq!(
        sample["data"]["workdays"],
        serde_json::json!([{"date": "2026-11-05", "code": 1}]),
        "the SOCKS proxy was not used"
    );
    let recorded = seen.lock().expect("socks record").clone();
    assert_eq!(
        recorded,
        vec!["api.example:80".to_string(), "api.example:80".to_string()]
    );
}
