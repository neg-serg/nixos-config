//! Shared harness for the integration tests.
//!
//! Everything is local: a `TcpListener` on 127.0.0.1 plays every provider, the
//! cache lives under a temporary directory, and the worker is spawned with a
//! cleared environment (no proxy variables, no way to reach the internet). A
//! test that needs a behaviour a real service has (a 503, a truncated body, a
//! slow answer) asks the mock for it.

#![allow(dead_code)]

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Output, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// How long a test waits for one worker line or process exit before failing.
pub const TIMEOUT: Duration = Duration::from_secs(10);

// ---------------------------------------------------------------------------
// Temporary directories

static SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub fn new(label: &str) -> Self {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "pleamar-weather-it-{label}-{}-{nanos}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("test temp directory");
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn cache_file(&self) -> PathBuf {
        self.path.join("cache/pleamar/helpers/weather.json")
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

// ---------------------------------------------------------------------------
// A local HTTP server

#[derive(Clone, Debug)]
pub struct Request {
    /// The request target as sent: `/path?query`, or the absolute URL when an
    /// HTTP proxy is in front.
    pub target: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
}

impl Request {
    pub fn path(&self) -> &str {
        match self.target.find("://") {
            Some(scheme_end) => {
                let rest = &self.target[scheme_end + 3..];
                match rest.find('/') {
                    Some(slash) => &rest[slash..],
                    None => "/",
                }
            }
            None => &self.target,
        }
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(key, _)| key.eq_ignore_ascii_case(name))
            .map(|(_, value)| value.as_str())
    }
}

#[derive(Clone, Debug)]
pub struct Response {
    pub status: u16,
    pub body: String,
    pub content_type: &'static str,
}

impl Response {
    pub fn json(body: impl Into<String>) -> Self {
        Self {
            status: 200,
            body: body.into(),
            content_type: "application/json",
        }
    }

    pub fn text(body: impl Into<String>) -> Self {
        Self {
            status: 200,
            body: body.into(),
            content_type: "text/plain; charset=utf-8",
        }
    }

    pub fn error(status: u16) -> Self {
        Self {
            status,
            body: format!("upstream error {status}\n"),
            content_type: "text/plain",
        }
    }
}

pub struct Mock {
    base: String,
    requests: Arc<Mutex<Vec<Request>>>,
    stop: Arc<AtomicBool>,
    handle: Option<thread::JoinHandle<()>>,
}

impl Mock {
    pub fn start<F>(handler: F) -> Self
    where
        F: Fn(&Request) -> Response + Send + Sync + 'static,
    {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock server");
        listener
            .set_nonblocking(true)
            .expect("nonblocking listener");
        let port = listener.local_addr().expect("local addr").port();
        let requests: Arc<Mutex<Vec<Request>>> = Arc::new(Mutex::new(Vec::new()));
        let stop = Arc::new(AtomicBool::new(false));
        let handler = Arc::new(handler);

        let accept_requests = Arc::clone(&requests);
        let accept_stop = Arc::clone(&stop);
        let handle = thread::spawn(move || {
            while !accept_stop.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let _ = stream.set_nodelay(true);
                        let handler = Arc::clone(&handler);
                        let requests = Arc::clone(&accept_requests);
                        // One connection per thread: a handler that sleeps
                        // (the SIGTERM test) must not stall the accept loop.
                        thread::spawn(move || {
                            let _ = handle_connection(stream, &*handler, &requests);
                        });
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(2));
                    }
                    Err(_) => break,
                }
            }
        });

        Self {
            base: format!("http://127.0.0.1:{port}"),
            requests,
            stop,
            handle: Some(handle),
        }
    }

    pub fn base(&self) -> &str {
        &self.base
    }

    pub fn requests(&self) -> Vec<Request> {
        self.requests.lock().expect("request log").clone()
    }

    pub fn paths(&self) -> Vec<String> {
        self.requests()
            .into_iter()
            .map(|request| request.path().to_string())
            .collect()
    }

    /// Number of requests whose path starts with `prefix`.
    pub fn count(&self, prefix: &str) -> usize {
        self.paths()
            .into_iter()
            .filter(|path| path.starts_with(prefix))
            .count()
    }

    /// Block until at least `prefix` was requested `times` times.
    pub fn wait_for(&self, prefix: &str, times: usize, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if self.count(prefix) >= times {
                return true;
            }
            thread::sleep(Duration::from_millis(5));
        }
        false
    }
}

impl Drop for Mock {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn handle_connection<F>(
    stream: TcpStream,
    handler: &F,
    requests: &Arc<Mutex<Vec<Request>>>,
) -> std::io::Result<()>
where
    F: Fn(&Request) -> Response,
{
    stream.set_read_timeout(Some(Duration::from_secs(10)))?;
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut request_line = String::new();
    reader.read_line(&mut request_line)?;
    let mut headers = Vec::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed.is_empty() {
            break;
        }
        if let Some((name, value)) = trimmed.split_once(':') {
            headers.push((name.trim().to_string(), value.trim().to_string()));
        }
    }
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or_default().to_string();
    let target = parts.next().unwrap_or_default().to_string();
    let request = Request {
        method,
        target,
        headers,
    };
    requests.lock().expect("request log").push(request.clone());

    let response = handler(&request);
    let mut writer = stream;
    let head = format!(
        "HTTP/1.1 {} {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        response.status,
        reason(response.status),
        response.content_type,
        response.body.len()
    );
    writer.write_all(head.as_bytes())?;
    writer.write_all(response.body.as_bytes())?;
    writer.flush()?;
    Ok(())
}

fn reason(status: u16) -> &'static str {
    match status {
        200 => "OK",
        404 => "Not Found",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "Status",
    }
}

// ---------------------------------------------------------------------------
// The worker process

pub fn arguments(cache: &Path, base: &str) -> Vec<String> {
    vec![
        "--cache-file".to_string(),
        cache.to_string_lossy().into_owned(),
        "--api-base".to_string(),
        format!("{base}/v1"),
        "--geocoding-base".to_string(),
        format!("{base}/geo/v1"),
        "--wttr-base".to_string(),
        format!("{base}/wttr"),
        "--metno-base".to_string(),
        format!("{base}/metno"),
        "--timeout".to_string(),
        "3".to_string(),
    ]
}

fn configure(command: &mut Command, extra_env: &[(&str, &str)]) {
    command
        .env_clear()
        // Keep the worker away from the developer's real cache; every test
        // passes --cache-file, HOME is here only for the default-path tests.
        .env("HOME", "/nonexistent-pleamar-weather-home")
        .env("TMPDIR", std::env::temp_dir());
    for (name, value) in extra_env {
        command.env(name, value);
    }
}

pub fn run(args: &[String], extra_env: &[(&str, &str)]) -> Output {
    let mut command = Command::new(env!("CARGO_BIN_EXE_pleamar-weather"));
    command.args(args).stdin(Stdio::null());
    configure(&mut command, extra_env);
    command.output().expect("run worker")
}

pub struct Interactive {
    child: Child,
    stdin: Option<ChildStdin>,
    lines: Receiver<String>,
    stderr: Receiver<String>,
}

impl Interactive {
    pub fn start(args: &[String], extra_env: &[(&str, &str)]) -> Self {
        let mut command = Command::new(env!("CARGO_BIN_EXE_pleamar-weather"));
        command
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        configure(&mut command, extra_env);
        let mut child = command.spawn().expect("spawn worker");
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().expect("stdout");
        let child_stderr = child.stderr.take().expect("stderr");
        let (line_sender, lines) = mpsc::channel();
        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines().map_while(Result::ok) {
                if line_sender.send(line).is_err() {
                    break;
                }
            }
        });
        let (error_sender, stderr_lines) = mpsc::channel();
        thread::spawn(move || {
            let mut reader = BufReader::new(child_stderr);
            let mut buffer = String::new();
            let _ = reader.read_to_string(&mut buffer);
            let _ = error_sender.send(buffer);
        });
        Self {
            child,
            stdin,
            lines,
            stderr: stderr_lines,
        }
    }

    pub fn send(&mut self, line: &str) {
        let stdin = self.stdin.as_mut().expect("stdin open");
        writeln!(stdin, "{line}").expect("write command");
        stdin.flush().expect("flush command");
    }

    pub fn send_raw(&mut self, text: &str) {
        let stdin = self.stdin.as_mut().expect("stdin open");
        stdin.write_all(text.as_bytes()).expect("write raw");
        stdin.flush().expect("flush raw");
    }

    pub fn close_stdin(&mut self) {
        self.stdin.take();
    }

    pub fn next_line(&mut self) -> String {
        self.next_line_within(TIMEOUT)
            .expect("worker line before the timeout")
    }

    pub fn next_line_within(&mut self, timeout: Duration) -> Option<String> {
        self.lines.recv_timeout(timeout).ok()
    }

    /// Lines already buffered, without waiting (drains what arrived so far).
    pub fn drain(&mut self) -> Vec<String> {
        let mut lines = Vec::new();
        while let Ok(line) = self.lines.try_recv() {
            lines.push(line);
        }
        lines
    }

    pub fn wait_timeout(&mut self, timeout: Duration) -> Option<ExitStatus> {
        let deadline = Instant::now() + timeout;
        loop {
            match self.child.try_wait().expect("try_wait") {
                Some(status) => return Some(status),
                None if Instant::now() >= deadline => return None,
                None => thread::sleep(Duration::from_millis(5)),
            }
        }
    }

    pub fn signal_term(&mut self) {
        let pid = self.child.id();
        let status = Command::new("bash")
            .arg("-c")
            .arg(format!("kill -TERM {pid}"))
            .status()
            .expect("send SIGTERM");
        assert!(status.success(), "kill -TERM failed");
    }

    pub fn stderr(&mut self) -> String {
        self.stderr.recv_timeout(TIMEOUT).unwrap_or_default()
    }
}

impl Drop for Interactive {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

// ---------------------------------------------------------------------------
// Provider fixtures

pub const GEOCODE: &str = concat!(
    r#"{"generationtime_ms":0.5,"results":[{"id":498817,"name":"Saint Petersburg","#,
    r#""latitude":59.93863,"longitude":30.31413,"country":"Russia","admin1":"City of Saint Petersburg","#,
    r#""timezone":"Europe/Moscow"}],"query":{"name":"Saint Petersburg"}}"#
);

pub const FORECAST: &str = concat!(
    r#"{"latitude":59.93863,"longitude":30.31413,"generationtime_ms":0.11,"utc_offset_seconds":0,"#,
    r#""timezone":"GMT","timezone_abbreviation":"GMT","elevation":10.0,"#,
    r#""current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","weather_code":"wmo code","#,
    r#""wind_speed_10m":"m/s","wind_direction_10m":"°","is_day":"","relative_humidity_2m":"%","surface_pressure":"hPa"},"#,
    r#""current":{"time":"2026-11-02T12:00","interval":900,"temperature_2m":6.3,"weather_code":3,"#,
    r#""wind_speed_10m":3.40,"wind_direction_10m":231,"is_day":0,"relative_humidity_2m":81,"surface_pressure":1027.4},"#,
    r#""daily_units":{"time":"iso8601","temperature_2m_max":"°C","temperature_2m_min":"°C","weathercode":"wmo code"},"#,
    r#""daily":{"time":["2026-11-02","2026-11-03"],"temperature_2m_max":[7.9,7.0],"#,
    r#""temperature_2m_min":[5.6,4.0],"weathercode":[3,53]}}"#
);

pub const METNO: &str = concat!(
    r#"{"type":"Feature","geometry":{"type":"Point","coordinates":[30.31413,59.93863,10]},"#,
    r#""properties":{"meta":{"updated_at":"2026-11-02T12:00:00Z","units":{"air_temperature":"celsius"}},"#,
    r#""timeseries":["#,
    r#"{"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":{"air_temperature":7.9}},"#,
    r#""next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"},"details":{"precipitation_amount":0.0}}}},"#,
    r#"{"time":"2026-11-02T18:00:00Z","data":{"instant":{"details":{"air_temperature":5.6}},"#,
    r#""next_6_hours":{"summary":{"symbol_code":"rain"}}}},"#,
    r#"{"time":"2026-11-03T12:00:00Z","data":{"instant":{"details":{"air_temperature":7.0}},"#,
    r#""next_1_hours":{"summary":{"symbol_code":"cloudy"}}}}"#,
    r#"]}}"#
);

pub const WTTR: &str = "Partly cloudy|+3°C|81%|↑8km/h|Partly cloudy|1009|29.80|0";

/// Mock server answer for the geocoding path and a healthy Open-Meteo.
///
/// The fallback pair answers `503` on purpose: the two providers are raced
/// (`Worker::fetch_providers`), so a mock where both succeed hands the test
/// whichever payload the scheduler ran first — and the two documents are not
/// interchangeable. A test that wants the fallback passes its own handler.
pub fn provider_response(request: &Request) -> Response {
    if request.path().starts_with("/geo/v1/search?") {
        Response::json(GEOCODE)
    } else if request.path().starts_with("/v1/forecast?") {
        Response::json(FORECAST)
    } else {
        Response::error(503)
    }
}

/// A cache document written by hand, so tests can choose its age.
pub fn cache_document(
    city: &str,
    latitude: &str,
    longitude: &str,
    geocoded_at: i64,
    fetched_at: i64,
    provider: &str,
) -> String {
    format!(
        concat!(
            r#"{{"city":{},"latitude":{},"longitude":{},"geocoded_at":{},"fetched_at":{},"payload":"#,
            r#"{{"city":{},"latitude":{},"longitude":{},"provider":"{}","fetched_at":{},"age_s":0,"#,
            r#""cached":false,"current":{{"temp_c":5.0,"weather_code":3,"wind_ms":2.0,"wind_dir_deg":90,"#,
            r#""is_day":1,"humidity_pct":70,"pressure_hpa":1010.0}},"#,
            r#""daily":[{{"date":"2026-11-02","tmax_c":7.0,"tmin_c":5.0,"weather_code":3}}]}}}}"#
        ),
        json_string(city),
        latitude,
        longitude,
        geocoded_at,
        fetched_at,
        json_string(city),
        latitude,
        longitude,
        provider,
        fetched_at,
    )
}

pub fn json_string(value: &str) -> String {
    serde_json::to_string(value).expect("json string")
}

pub fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

pub fn write_cache(path: &Path, document: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("cache parent");
    }
    fs::write(path, document).expect("cache file");
}

/// Parse a JSON line, panicking with the line on malformed input.
pub fn parse_line(line: &str) -> serde_json::Value {
    serde_json::from_str(line).unwrap_or_else(|error| panic!("bad JSON line: {error}: {line}"))
}
