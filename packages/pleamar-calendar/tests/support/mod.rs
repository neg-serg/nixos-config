//! Shared harness for the integration tests.
//!
//! Everything is local: `khal` is a temporary POSIX shell script on PATH, both
//! APIs are a `TcpListener` on 127.0.0.1, and HOME/TMPDIR/XDG dirs live under
//! a temporary directory. The worker is spawned with a cleared environment, so
//! no test can reach the internet or the user's real cache.

#![allow(dead_code)]

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, ExitStatus, Output, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// How long a test waits for one worker line or process exit before failing.
pub const TIMEOUT: Duration = Duration::from_secs(10);

pub const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"calendar\",\"version\":1,\"topics\":[\"calendar\"]}";

/// A nager.at answer: one November holiday and one outside the month.
pub const HOLIDAYS: &str = concat!(
    r#"[{"date":"2026-11-04","localName":"Den narodnogo edinstva","name":"Unity Day","#,
    r#""countryCode":"RU","fixed":true,"global":true,"counties":null,"launchYear":2005,"#,
    r#""types":["Public"]},"#,
    r#"{"date":"2026-12-31","localName":"New Year","name":"New Year","countryCode":"RU","#,
    r#""fixed":true,"global":true,"counties":null,"launchYear":null,"types":["Public"]}]"#
);

/// isdayoff.ru: one non-working day (the 5th) in a 30-day November.
pub const WORKDAYS: &str = "000010000000000000000000000000";

/// khal's answer with a header, both date spellings, an ANSI-coloured title,
/// a title containing pipes and a line that is not an event.
pub const EVENTS: &str = concat!(
    "Today, 2026-11-05\n",
    "2026-11-05|09:00|Standup|Work\n",
    "2026-11-06| 18:30 |Concert|a|b|Personal\n",
    "05.11.2026|10:00|\u{1b}[31mColoured\u{1b}[0m|Cal\n",
    "not an event\n",
    "2026-11-07|11:00|Only three|pipes\n",
);

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
            "pleamar-calendar-it-{label}-{}-{nanos}-{sequence}",
            std::process::id()
        ));
        fs::create_dir_all(&path).expect("test temp directory");
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

// ---------------------------------------------------------------------------
// The sandbox: fake khal on PATH, XDG dirs, a private TMPDIR

pub struct Sandbox {
    pub directory: TempDir,
    pub bin: PathBuf,
    pub home: PathBuf,
    pub tmp: PathBuf,
    pub data: PathBuf,
    pub cache: PathBuf,
    pub khal_log: PathBuf,
}

impl Sandbox {
    pub fn new(label: &str) -> Self {
        let directory = TempDir::new(label);
        let bin = directory.path().join("bin");
        let home = directory.path().join("home");
        let tmp = directory.path().join("tmp");
        let data = directory.path().join("data");
        let cache = directory.path().join("cache");
        for path in [&bin, &home, &tmp, &data, &cache] {
            fs::create_dir_all(path).expect("sandbox directory");
        }
        let khal_log = directory.path().join("khal.log");
        write_fake_khal(&bin.join("khal"));
        Self {
            directory,
            bin,
            home,
            tmp,
            data,
            cache,
            khal_log,
        }
    }

    pub fn state_path(&self) -> PathBuf {
        self.data.join("pleamar/Pill/state.json")
    }

    pub fn write_state(&self, document: &str) {
        let path = self.state_path();
        fs::create_dir_all(path.parent().expect("state parent")).expect("state dir");
        fs::write(path, document).expect("state file");
    }

    pub fn khal_calls(&self) -> Vec<String> {
        fs::read_to_string(&self.khal_log)
            .map(|text| text.lines().map(|line| line.to_string()).collect())
            .unwrap_or_default()
    }

    pub fn clear_khal_log(&self) {
        let _ = fs::remove_file(&self.khal_log);
    }

    fn configure(&self, command: &mut Command, extra_env: &[(&str, &str)]) {
        command
            .env_clear()
            // The worker itself needs no PATH entry; the fake khal is the only
            // command it looks up. /bin/sh comes from the script's shebang.
            .env("PATH", &self.bin)
            .env("HOME", &self.home)
            .env("TMPDIR", &self.tmp)
            .env("XDG_DATA_HOME", &self.data)
            .env("XDG_CACHE_HOME", &self.cache)
            .env("FAKE_KHAL_LOG", &self.khal_log)
            .env("FAKE_KHAL_MODE", "ok")
            .env("FAKE_KHAL_TEXT", EVENTS);
        for (name, value) in extra_env {
            command.env(name, value);
        }
    }

    pub fn run(&self, args: &[String], extra_env: &[(&str, &str)]) -> Output {
        let mut command = Command::new(env!("CARGO_BIN_EXE_pleamar-calendar"));
        command.args(args).stdin(Stdio::null());
        self.configure(&mut command, extra_env);
        command.output().expect("run worker")
    }

    pub fn interactive(&self, args: &[String], extra_env: &[(&str, &str)]) -> Interactive {
        let mut command = Command::new(env!("CARGO_BIN_EXE_pleamar-calendar"));
        command
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        self.configure(&mut command, extra_env);
        Interactive::start(command)
    }
}

fn write_fake_khal(path: &Path) {
    // `$4` is the first date argument: khal list --format FORMAT FIRST LAST.
    // A mode is chosen per test through the environment.
    let script = concat!(
        "#!/bin/sh\n",
        "printf '%s\\n' \"$*\" >> \"${FAKE_KHAL_LOG:-/dev/null}\"\n",
        "mode=${FAKE_KHAL_MODE:-ok}\n",
        "if [ \"$mode\" = fail ]; then\n",
        "  printf '%s\\n' \"${FAKE_KHAL_STDERR:-}\" >&2\n",
        "  exit \"${FAKE_KHAL_CODE:-3}\"\n",
        "fi\n",
        "if [ \"$mode\" = retry ]; then\n",
        "  case \"$4\" in\n",
        "    *.*.*) printf '%s\\n' \"${FAKE_KHAL_TEXT:-}\" ;;\n",
        "    *) printf 'critical: cannot parse\\n' >&2; exit 1 ;;\n",
        "  esac\n",
        "  exit 0\n",
        "fi\n",
        "if [ \"$mode\" = critical-first ]; then\n",
        "  case \"$4\" in\n",
        "    *.*.*) printf '%s\\n' \"${FAKE_KHAL_TEXT:-}\" ;;\n",
        "    *) printf 'critical: warning\\n' >&2; printf 'discarded\\n'; exit 0 ;;\n",
        "  esac\n",
        "  exit 0\n",
        "fi\n",
        "printf '%s\\n' \"${FAKE_KHAL_TEXT:-}\"\n",
    );
    fs::write(path, script).expect("fake khal");
    let mut permissions = fs::metadata(path)
        .expect("fake khal metadata")
        .permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(path, permissions).expect("fake khal mode");
}

// ---------------------------------------------------------------------------
// A local HTTP server

#[derive(Clone, Debug)]
pub struct Request {
    pub target: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
}

impl Request {
    /// `/path?query`, or the path part of an absolute proxy target.
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

/// The default provider: both APIs answer their fixtures.
pub fn provider_response(request: &Request) -> Response {
    if request.path().starts_with("/v3/PublicHolidays/") {
        Response::json(HOLIDAYS)
    } else if request.path().starts_with("/getdata?") {
        Response::text(WORKDAYS)
    } else {
        Response::error(404)
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
                        // One connection per thread: a handler that sleeps (the
                        // SIGTERM test) must not stall the accept loop.
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

    pub fn count(&self, prefix: &str) -> usize {
        self.paths()
            .into_iter()
            .filter(|path| path.starts_with(prefix))
            .count()
    }

    /// Block until `prefix` was requested `times` times.
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
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "Status",
    }
}

// ---------------------------------------------------------------------------
// Worker arguments and fixtures

/// `--cache-dir` plus both base URLs pointed at the local mock.
pub fn arguments(cache: &Path, base: &str) -> Vec<String> {
    vec![
        "--cache-dir".to_string(),
        cache.to_string_lossy().into_owned(),
        "--holidays-base".to_string(),
        format!("{base}/v3"),
        "--workdays-base".to_string(),
        format!("{base}/getdata"),
    ]
}

pub fn cache_file(cache: &Path, month: &str) -> PathBuf {
    cache.join(format!("calendar-{month}.json"))
}

pub fn holidays_cache_file(cache: &Path, year: &str, country: &str) -> PathBuf {
    cache.join(format!("holidays-{year}-{country}.json"))
}

pub fn workdays_cache_file(cache: &Path, year: &str, month: &str, country: &str) -> PathBuf {
    cache.join(format!("workdays-{year}-{month}-{country}.txt"))
}

pub fn write_file(path: &Path, text: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("file parent");
    }
    fs::write(path, text).expect("fixture file");
}

pub fn file_mode(path: &Path) -> u32 {
    fs::metadata(path).expect("metadata").permissions().mode() & 0o777
}

/// Set the modification time (the caches' TTLs are mtime-based).
pub fn set_mtime(path: &Path, seconds: i64) {
    let file = fs::OpenOptions::new()
        .write(true)
        .open(path)
        .expect("open for mtime");
    let time = if seconds >= 0 {
        UNIX_EPOCH + Duration::from_secs(seconds as u64)
    } else {
        UNIX_EPOCH - Duration::from_secs((-seconds) as u64)
    };
    file.set_modified(time).expect("set mtime");
}

pub fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

pub fn lines(output: &Output) -> Vec<String> {
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| line.to_string())
        .collect()
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

pub fn parse_line(line: &str) -> serde_json::Value {
    serde_json::from_str(line).unwrap_or_else(|error| panic!("bad JSON line: {error}: {line}"))
}

pub fn assert_recent_ms(value: &serde_json::Value, field: &str, tolerance_ms: u64) {
    let observed = value[field]
        .as_u64()
        .unwrap_or_else(|| panic!("{field} is not a number"));
    let now = now_ms();
    assert!(
        observed.abs_diff(now) <= tolerance_ms,
        "{field}={observed} is not near {now}"
    );
}

// ---------------------------------------------------------------------------
// The interactive worker process

pub struct Interactive {
    child: Child,
    stdin: Option<ChildStdin>,
    lines: Receiver<String>,
    stderr: Receiver<String>,
}

impl Interactive {
    fn start(mut command: Command) -> Self {
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

    /// `kill -SIG PID`, the same hard stop a scene uses.
    pub fn signal(&self, signal: &str) {
        let pid = self.child.id();
        let status = Command::new("/bin/sh")
            .arg("-c")
            .arg(format!("kill -{signal} {pid}"))
            .status()
            .expect("send signal");
        assert!(status.success(), "kill -{signal} failed");
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

/// The process umask, so a cache-mode assertion can expect the shell
/// redirect's 0666 & ~umask rather than a hard-coded 0644.
pub fn current_umask() -> u32 {
    let output = Command::new("/bin/sh")
        .arg("-c")
        .arg("umask")
        .output()
        .expect("read umask");
    u32::from_str_radix(String::from_utf8_lossy(&output.stdout).trim(), 8).expect("parse umask")
}

pub fn expected_file_mode() -> u32 {
    0o666 & !current_umask()
}
