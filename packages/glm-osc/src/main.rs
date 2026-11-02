//! glm-osc — OSC bridge to Genelec SAM monitors via `glm5d` (and `genlc`).
//!
//! Listens on UDP `127.0.0.1:9000` (`GLM_OSC_HOST`/`GLM_OSC_PORT`) and turns OSC
//! messages into adapter commands, so the monitors can be driven from a DAW, a
//! stream deck or a shell script without the official GLM app running:
//!
//!   /glm/volume <dB>          absolute volume (float dB)
//!   /glm/volume/ratio <0..1>  absolute volume as a linear ratio
//!   /glm/volume/up <dB>       relative up   (stateful)
//!   /glm/volume/down <dB>     relative down (stateful)
//!   /glm/mute <0|1>           set mute
//!   /glm/mute/toggle          toggle mute (stateful)
//!   /glm/power <1|0>          on / off
//!   /glm/power/toggle         toggle power (stateful)
//!   /glm/led <color> [pulse]  green|red|yellow|off, optional pulse
//!   /glm/status               replies /glm/status/reply with JSON
//!   /glm/discover             replies /glm/discover/reply
//!
//! Two backends, and the split between them is deliberate:
//!
//!   * `glm5d` (`src/bin/glm5d.rs` of packages/genlc-rs) owns the USB adapter
//!     and is the only process that keeps the monitors leased — it polls and
//!     re-leases about every 0.5 s, and a lease lapses ~2.5 s after it stops.
//!     Volume, mute and status therefore go through its Unix socket as one
//!     command per line (`volume <dB>`, `mute on|off`, `status` → one JSON
//!     line), so this bridge never opens the adapter behind the daemon's back.
//!   * `genlc` stays for `/glm/power`, `/glm/led` and `/glm/discover`: the
//!     daemon's protocol has no wakeup/shutdown, no LED `bypass` and no device
//!     discovery yet. Those three branches move over once it grows them, and
//!     then the CLI is left for diagnostics only.
//!   * Fallback: volume/mute also go to the CLI when the socket is missing or
//!     the connection drops (logged once, not per message), so a host without
//!     a running `glm5d` keeps working exactly as before that daemon existed.
//!
//! `genlc` stays an external program: it is the third-party implementation of
//! the GLM USB protocol, and reimplementing that would be a different project.
//! The server itself is Rust with no crates — OSC, the UDP loop, the daemon
//! line protocol and the state file are hand-rolled.
//!
//! Environment:
//!   GLM_DAEMON_SOCKET path to the glm5d control socket
//!                    (default `$XDG_RUNTIME_DIR/glm5d.sock`)
//!   GENLC_CLI      path to the genlc binary
//!   HIDAPI_LIB     LD_LIBRARY_PATH for hidapi (unset = inherit)
//!   GLM_OSC_STATE  JSON state file (volume/mute/power)

use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Write};
use std::net::{SocketAddr, UdpSocket};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Duration;

const DEFAULT_STATE_FILE: &str = "/tmp/glm-osc-state.json";
const DEFAULT_GENLC: &str = "/tmp/glm-osc-venv/bin/genlc";
const DEFAULT_HOST: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 9000;
const GENLC_TIMEOUT_SECONDS: u64 = 40;
/// A daemon reply is one line computed from an in-memory snapshot, so a couple
/// of seconds is already generous; a hung daemon must not stall an OSC message.
const DAEMON_TIMEOUT: Duration = Duration::from_secs(2);
const DEFAULT_RUNTIME_DIR: &str = "/run/user/1000";

fn env_or(name: &str, fallback: &str) -> String {
    match std::env::var(name) {
        Ok(value) if !value.is_empty() => value,
        _ => fallback.to_string(),
    }
}

// -- OSC ---------------------------------------------------------------

/// One OSC argument. The bridge only ever sees floats/ints and strings.
#[derive(Debug, Clone, PartialEq)]
pub enum Arg {
    Float(f32),
    Int(i32),
    Str(String),
}

impl Arg {
    fn as_f64(&self) -> Option<f64> {
        match self {
            Arg::Float(value) => Some(*value as f64),
            Arg::Int(value) => Some(*value as f64),
            Arg::Str(_) => None,
        }
    }

    fn as_text(&self) -> String {
        match self {
            Arg::Float(value) => format!("{value}"),
            Arg::Int(value) => value.to_string(),
            Arg::Str(text) => text.clone(),
        }
    }
}

/// Append an OSC string: bytes, a NUL terminator, then padding to four bytes.
fn push_string(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(text.as_bytes());
    align(out);
}

fn align(bytes: &mut Vec<u8>) {
    bytes.push(0);
    while bytes.len() % 4 != 0 {
        bytes.push(0);
    }
}

pub fn encode(address: &str, args: &[Arg]) -> Vec<u8> {
    let mut out = Vec::new();
    push_string(&mut out, address);
    let mut tags = String::from(",");
    for arg in args {
        tags.push(match arg {
            Arg::Float(_) => 'f',
            Arg::Int(_) => 'i',
            Arg::Str(_) => 's',
        });
    }
    push_string(&mut out, &tags);
    for arg in args {
        match arg {
            Arg::Float(value) => out.extend_from_slice(&value.to_be_bytes()),
            Arg::Int(value) => out.extend_from_slice(&value.to_be_bytes()),
            Arg::Str(text) => push_string(&mut out, text),
        }
    }
    out
}

/// `(address, args)` of one OSC packet.
pub fn decode(packet: &[u8]) -> Option<(String, Vec<Arg>)> {
    let address_end = packet.iter().position(|byte| *byte == 0)?;
    let address = String::from_utf8_lossy(&packet[..address_end]).to_string();
    let mut offset = (address_end + 4) & !3;
    if packet.get(offset) != Some(&b',') {
        return Some((address, Vec::new()));
    }
    let tags_start = offset;
    let tags_end = packet[tags_start..]
        .iter()
        .position(|byte| *byte == 0)
        .map(|position| tags_start + position)?;
    let tags = String::from_utf8_lossy(&packet[tags_start + 1..tags_end]).to_string();
    offset = (tags_end + 4) & !3;
    let mut args = Vec::new();
    for tag in tags.chars() {
        match tag {
            'f' | 'i' => {
                if offset + 4 > packet.len() {
                    return None;
                }
                let mut word = [0u8; 4];
                word.copy_from_slice(&packet[offset..offset + 4]);
                offset += 4;
                args.push(if tag == 'f' {
                    Arg::Float(f32::from_be_bytes(word))
                } else {
                    Arg::Int(i32::from_be_bytes(word))
                });
            }
            's' => {
                let end = packet[offset..]
                    .iter()
                    .position(|byte| *byte == 0)
                    .map(|position| offset + position)?;
                args.push(Arg::Str(
                    String::from_utf8_lossy(&packet[offset..end]).to_string(),
                ));
                offset = (end + 4) & !3;
            }
            'T' => args.push(Arg::Int(1)),
            'F' => args.push(Arg::Int(0)),
            _ => break, // unsupported tag: stop here, keep what we have
        }
    }
    Some((address, args))
}

// -- state -------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct State {
    pub volume_db: f64,
    pub muted: bool,
    pub power: bool,
}

impl Default for State {
    fn default() -> State {
        State {
            volume_db: -20.0,
            muted: false,
            power: true,
        }
    }
}

fn state_file() -> PathBuf {
    PathBuf::from(env_or("GLM_OSC_STATE", DEFAULT_STATE_FILE))
}

/// A tiny JSON subset: the state is a flat object of numbers and booleans.
fn parse_state(text: &str) -> BTreeMap<String, String> {
    let mut fields = BTreeMap::new();
    let mut chars = text.chars().peekable();
    loop {
        while matches!(chars.peek(), Some(ch) if ch.is_whitespace() || *ch == ',' || *ch == '{' || *ch == '}')
        {
            chars.next();
        }
        let Some('"') = chars.peek() else { break };
        chars.next();
        let mut key = String::new();
        for ch in chars.by_ref() {
            if ch == '"' {
                break;
            }
            key.push(ch);
        }
        while matches!(chars.peek(), Some(ch) if ch.is_whitespace() || *ch == ':') {
            chars.next();
        }
        let mut value = String::new();
        if matches!(chars.peek(), Some('"')) {
            chars.next();
            for ch in chars.by_ref() {
                if ch == '"' {
                    break;
                }
                value.push(ch);
            }
        } else {
            while let Some(ch) = chars.peek() {
                if *ch == ',' || *ch == '}' {
                    break;
                }
                value.push(*ch);
                chars.next();
            }
        }
        fields.insert(key, value.trim().to_string());
    }
    fields
}

pub fn load_state(path: &PathBuf) -> State {
    let Ok(text) = std::fs::read_to_string(path) else {
        return State::default();
    };
    let fields = parse_state(&text);
    let mut state = State::default();
    if let Some(value) = fields.get("volume_db").and_then(|value| value.parse().ok()) {
        state.volume_db = value;
    }
    if let Some(value) = fields.get("muted") {
        state.muted = value == "true";
    }
    if let Some(value) = fields.get("power") {
        state.power = value == "true";
    }
    state
}

pub fn save_state(path: &PathBuf, state: &State) {
    let body = format!(
        "{{\"volume_db\": {}, \"muted\": {}, \"power\": {}}}",
        state.volume_db, state.muted, state.power
    );
    let _ = std::fs::write(path, body);
}

// -- genlc -------------------------------------------------------------

fn genlc() -> String {
    env_or("GENLC_CLI", DEFAULT_GENLC)
}

struct GenlcOutput {
    ok: bool,
    stdout: String,
    stderr: String,
}

fn run_genlc(args: &[&str]) -> GenlcOutput {
    let mut command = Command::new(genlc());
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Ok(lib) = std::env::var("HIDAPI_LIB") {
        if !lib.is_empty() {
            command.env("LD_LIBRARY_PATH", lib);
        }
    }
    let Ok(mut child) = command.spawn() else {
        return GenlcOutput {
            ok: false,
            stdout: String::new(),
            stderr: "cannot spawn genlc".to_string(),
        };
    };
    let deadline =
        std::time::Instant::now() + std::time::Duration::from_secs(GENLC_TIMEOUT_SECONDS);
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let output = child.wait_with_output().ok();
                let (stdout, stderr) = match output {
                    Some(output) => (
                        String::from_utf8_lossy(&output.stdout).to_string(),
                        String::from_utf8_lossy(&output.stderr).to_string(),
                    ),
                    None => (String::new(), String::new()),
                };
                return GenlcOutput {
                    ok: status.success(),
                    stdout,
                    stderr,
                };
            }
            Ok(None) if std::time::Instant::now() >= deadline => {
                let _ = child.kill();
                return GenlcOutput {
                    ok: false,
                    stdout: String::new(),
                    stderr: "genlc timed out".to_string(),
                };
            }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(20)),
            Err(_) => {
                return GenlcOutput {
                    ok: false,
                    stdout: String::new(),
                    stderr: "genlc wait failed".to_string(),
                }
            }
        }
    }
}

fn tail(text: &str, limit: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= limit {
        return text.trim().to_string();
    }
    chars[chars.len() - limit..]
        .iter()
        .collect::<String>()
        .trim()
        .to_string()
}

fn json_escape(text: &str) -> String {
    text.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}

// -- glm5d -------------------------------------------------------------

fn daemon_socket() -> PathBuf {
    let fallback = format!(
        "{}/glm5d.sock",
        env_or("XDG_RUNTIME_DIR", DEFAULT_RUNTIME_DIR)
    );
    PathBuf::from(env_or("GLM_DAEMON_SOCKET", &fallback))
}

/// The raw JSON value text of `key` in the daemon's `status` line.
///
/// The daemon writes compact JSON with a fixed key set (`cycles`, `volume_db`,
/// `leases`, `telemetry`), so scanning for `"key":` and copying either a quoted
/// string, a balanced `{}`/`[]` block or a bare literal is enough — a full JSON
/// parser would be several hundred lines of crates-free code for no gain.
fn json_field(text: &str, key: &str) -> Option<String> {
    let needle = format!("\"{key}\":");
    let start = text.find(&needle)? + needle.len();
    let rest = &text[start..];
    let first = rest.chars().next()?;
    if first == '"' {
        let mut escaped = false;
        for (index, ch) in rest.char_indices().skip(1) {
            match ch {
                '\\' if !escaped => escaped = true,
                '"' if !escaped => return Some(rest[..=index].to_string()),
                _ => escaped = false,
            }
        }
        return None;
    }
    if first == '{' || first == '[' {
        let mut depth = 0usize;
        let mut in_string = false;
        let mut escaped = false;
        for (index, ch) in rest.char_indices() {
            if in_string {
                match ch {
                    '\\' if !escaped => escaped = true,
                    '"' if !escaped => in_string = false,
                    _ => escaped = false,
                }
            } else {
                match ch {
                    '"' => in_string = true,
                    '{' | '[' => depth += 1,
                    '}' | ']' => {
                        depth = depth.saturating_sub(1);
                        if depth == 0 {
                            return Some(rest[..=index].to_string());
                        }
                    }
                    _ => {}
                }
            }
        }
        return None;
    }
    let end = rest.find([',', '}']).unwrap_or(rest.len());
    Some(rest[..end].trim().to_string())
}

/// Line-protocol client for `glm5d`: one command per line, one reply line each.
///
/// The connection is kept between messages. When the socket is missing or the
/// connection breaks, the outage is logged once (not once per OSC message) and
/// every caller sees `None`, which is what makes the CLI fallback possible;
/// later messages retry, so the daemon wins again as soon as it is back, and
/// that recovery is logged once too.
struct Daemon {
    path: PathBuf,
    reader: Option<BufReader<UnixStream>>,
    writer: Option<UnixStream>,
    down: bool,
}

impl Daemon {
    fn new(path: PathBuf) -> Daemon {
        Daemon {
            path,
            reader: None,
            writer: None,
            down: false,
        }
    }

    fn drop_connection(&mut self, reason: &str) {
        self.reader = None;
        self.writer = None;
        if !self.down {
            self.down = true;
            println!(
                "glm5d unavailable at {} ({reason}); using the genlc CLI",
                self.path.display()
            );
        }
    }

    fn connect(&mut self) {
        let stream = match UnixStream::connect(&self.path) {
            Ok(stream) => stream,
            Err(exc) => return self.drop_connection(&exc.to_string()),
        };
        let _ = stream.set_read_timeout(Some(DAEMON_TIMEOUT));
        let _ = stream.set_write_timeout(Some(DAEMON_TIMEOUT));
        match stream.try_clone() {
            Ok(writer) => {
                self.reader = Some(BufReader::new(stream));
                self.writer = Some(writer);
            }
            Err(exc) => self.drop_connection(&format!("cannot duplicate socket: {exc}")),
        }
    }

    /// Send one command and return its reply line; `None` = daemon unreachable.
    fn command(&mut self, line: &str) -> Option<String> {
        if self.reader.is_none() {
            self.connect();
            self.reader.as_ref()?;
        }
        let written = self
            .writer
            .as_mut()
            .map(|writer| {
                writer
                    .write_all(format!("{line}\n").as_bytes())
                    .and_then(|()| writer.flush())
            })
            .unwrap_or_else(|| Err(std::io::Error::other("no connection")));
        if let Err(exc) = written {
            self.drop_connection(&format!("write failed: {exc}"));
            return None;
        }
        let mut reply = String::new();
        let read = self
            .reader
            .as_mut()
            .map(|reader| reader.read_line(&mut reply))
            .unwrap_or(Ok(0));
        match read {
            Ok(0) => {
                self.drop_connection("connection closed");
                None
            }
            Ok(_) => {
                if self.down {
                    self.down = false;
                    println!("glm5d reachable again at {}", self.path.display());
                }
                Some(reply.trim().to_string())
            }
            Err(exc) => {
                self.drop_connection(&format!("read failed: {exc}"));
                None
            }
        }
    }

    /// The `status` reply line, or `None` when the daemon cannot answer.
    fn status(&mut self) -> Option<String> {
        let reply = self.command("status")?;
        if !reply.starts_with('{') {
            println!("glm5d status failed: {}", tail(&reply, 200));
            return None;
        }
        Some(reply)
    }
}

// -- the bridge --------------------------------------------------------

pub struct Bridge {
    pub state: State,
    pub path: PathBuf,
    socket: Option<UdpSocket>,
    daemon: Daemon,
}

impl Bridge {
    pub fn new() -> Bridge {
        let path = state_file();
        let state = load_state(&path);
        Bridge {
            state,
            path,
            socket: None,
            daemon: Daemon::new(daemon_socket()),
        }
    }

    fn reply(&self, to: SocketAddr, address: &str, payload: &str) {
        if let Some(socket) = &self.socket {
            let _ = socket.send_to(&encode(address, &[Arg::Str(payload.to_string())]), to);
        }
    }

    pub fn volume(&mut self, db: f64) {
        // Absolute volume: the daemon owns the adapter, the CLI is the fallback
        // for a host where glm5d is not running (or just died).
        let (ok, detail) = match self.daemon.command(&format!("volume {db:.2}")) {
            Some(reply) => (reply.starts_with("ok"), tail(&reply, 200)),
            None => {
                let output = run_genlc(&["set-volume", "--volume", &format!("{db:.2}dB")]);
                (output.ok, tail(&output.stderr, 200))
            }
        };
        if ok {
            self.state.volume_db = db;
            save_state(&self.path, &self.state);
            println!("/glm/volume {db:.2}dB OK");
        } else {
            println!("/glm/volume FAIL: {detail}");
        }
    }

    pub fn volume_ratio(&mut self, ratio: f64) {
        let ratio = ratio.max(1e-4);
        self.volume(20.0 * ratio.log10());
    }

    pub fn volume_relative(&mut self, delta: f64) {
        self.volume(self.state.volume_db + delta);
    }

    pub fn mute(&mut self, on: bool) {
        let (ok, detail) = match self
            .daemon
            .command(&format!("mute {}", if on { "on" } else { "off" }))
        {
            Some(reply) => (reply.starts_with("ok"), tail(&reply, 200)),
            None => {
                let output = run_genlc(&[if on { "mute" } else { "unmute" }]);
                (output.ok, tail(&output.stderr, 200))
            }
        };
        if ok {
            self.state.muted = on;
            save_state(&self.path, &self.state);
            println!("/glm/mute {on} OK");
        } else {
            println!("/glm/mute FAIL: {detail}");
        }
    }

    pub fn mute_toggle(&mut self) {
        let on = !self.state.muted;
        self.mute(on);
    }

    pub fn power(&mut self, on: bool) {
        let output = run_genlc(&[if on { "wakeup" } else { "shutdown" }]);
        if output.ok {
            self.state.power = on;
            save_state(&self.path, &self.state);
            println!("/glm/power {on} OK");
        } else {
            println!("/glm/power FAIL: {}", tail(&output.stderr, 200));
        }
    }

    pub fn power_toggle(&mut self) {
        let on = !self.state.power;
        self.power(on);
    }

    pub fn led(&mut self, color: &str, pulse: bool) {
        let output = run_genlc(&[
            "bypass",
            "--led-color",
            color,
            if pulse {
                "--led-pulsing"
            } else {
                "--led-solid"
            },
        ]);
        let status = if output.ok {
            "OK".to_string()
        } else {
            format!("FAIL: {}", tail(&output.stderr, 200))
        };
        println!("/glm/led {color} {status}");
    }

    /// `/glm/status/reply`, served from the daemon's `status` JSON.
    ///
    /// The field names clients already parse stay (`ok`, `poll_rc`, `poll`,
    /// `error`, `state`); `poll` now carries the daemon's status line instead of
    /// `genlc poll` output, and the daemon's own view of the bus is added next
    /// to it: `cycles`, `volume_db`, `leases`, `telemetry`, plus `source` so a
    /// client can tell which backend answered. `state.volume_db` is refreshed
    /// from the daemon, so relative moves start from the level the adapter was
    /// actually told instead of a stale cache.
    pub fn status(&mut self, to: SocketAddr) {
        let (payload, source) = match self.daemon.status() {
            Some(line) => {
                let cycles = json_field(&line, "cycles").unwrap_or_else(|| "null".to_string());
                let volume = json_field(&line, "volume_db").unwrap_or_else(|| "null".to_string());
                let leases = json_field(&line, "leases").unwrap_or_else(|| "[]".to_string());
                let telemetry = json_field(&line, "telemetry").unwrap_or_else(|| "{}".to_string());
                if let Ok(volume_db) = volume.parse::<f64>() {
                    self.state.volume_db = volume_db;
                    save_state(&self.path, &self.state);
                }
                let reply = format!(
                    "{{\"ok\": true, \"poll_rc\": 0, \"poll\": \"{}\", \"state\": {{\"volume_db\": {}, \"muted\": {}, \"power\": {}}}, \"source\": \"daemon\", \"cycles\": {}, \"volume_db\": {}, \"leases\": {}, \"telemetry\": {}}}",
                    json_escape(&tail(&line, 2000)),
                    self.state.volume_db,
                    self.state.muted,
                    self.state.power,
                    cycles,
                    volume,
                    leases,
                    telemetry,
                );
                (reply, "daemon")
            }
            None => {
                // No daemon: the old genlc-poll answer, unchanged, so existing
                // clients and dashboards keep working on a daemon-less host.
                let output = run_genlc(&["poll", "--count", "1"]);
                let mut payload = format!(
                    "{{\"ok\": false, \"poll_rc\": {}, \"poll\": \"{}\"",
                    if output.ok { 0 } else { 1 },
                    json_escape(&tail(&output.stdout, 2000))
                );
                if !output.ok {
                    payload.push_str(&format!(
                        ", \"error\": \"{}\"",
                        json_escape(&tail(&output.stderr, 300))
                    ));
                }
                payload.push_str(&format!(
                    ", \"state\": {{\"volume_db\": {}, \"muted\": {}, \"power\": {}}}, \"source\": \"genlc\"}}",
                    self.state.volume_db, self.state.muted, self.state.power
                ));
                (payload, "genlc")
            }
        };
        self.reply(to, "/glm/status/reply", &payload);
        println!("/glm/status -> reply ({})", source);
    }

    pub fn discover(&mut self, to: SocketAddr) {
        let output = run_genlc(&["discover"]);
        let mut payload = format!(
            "{{\"ok\": {}, \"output\": \"{}\"",
            output.ok,
            json_escape(&tail(&output.stdout, 2000))
        );
        if !output.ok {
            payload.push_str(&format!(
                ", \"error\": \"{}\"",
                json_escape(&tail(&output.stderr, 300))
            ));
        }
        payload.push('}');
        self.reply(to, "/glm/discover/reply", &payload);
        println!("/glm/discover -> reply");
    }

    /// Dispatch one decoded message.
    pub fn handle(&mut self, from: SocketAddr, address: &str, args: &[Arg]) {
        let number = |index: usize| args.get(index).and_then(Arg::as_f64);
        match address {
            "/glm/volume" => {
                if let Some(db) = number(0) {
                    self.volume(db);
                }
            }
            "/glm/volume/ratio" => {
                if let Some(ratio) = number(0) {
                    self.volume_ratio(ratio);
                }
            }
            "/glm/volume/up" => {
                if let Some(delta) = number(0) {
                    self.volume_relative(delta);
                }
            }
            "/glm/volume/down" => {
                if let Some(delta) = number(0) {
                    self.volume_relative(-delta);
                }
            }
            "/glm/mute" => {
                if let Some(on) = number(0) {
                    self.mute(on != 0.0);
                }
            }
            "/glm/mute/toggle" => self.mute_toggle(),
            "/glm/power" => {
                if let Some(on) = number(0) {
                    self.power(on != 0.0);
                }
            }
            "/glm/power/toggle" => self.power_toggle(),
            "/glm/led" => {
                let color = args.first().map(Arg::as_text).unwrap_or_default();
                let pulse = number(1).map(|value| value != 0.0).unwrap_or(false);
                self.led(&color, pulse);
            }
            "/glm/status" => self.status(from),
            "/glm/discover" => self.discover(from),
            other => println!("unhandled: {other} {args:?}"),
        }
    }
}

fn main() -> std::process::ExitCode {
    let host = env_or("GLM_OSC_HOST", DEFAULT_HOST);
    let port: u16 = env_or("GLM_OSC_PORT", &DEFAULT_PORT.to_string())
        .parse()
        .unwrap_or(DEFAULT_PORT);
    let socket = match UdpSocket::bind((host.as_str(), port)) {
        Ok(socket) => socket,
        Err(exc) => {
            eprintln!("glm-osc: cannot bind {host}:{port}: {exc}");
            return std::process::ExitCode::from(1);
        }
    };
    let mut bridge = Bridge::new();
    println!(
        "glm-osc listening on {host}:{port} (glm5d: {}, genlc: {})",
        daemon_socket().display(),
        genlc()
    );
    bridge.socket = Some(match socket.try_clone() {
        Ok(clone) => clone,
        Err(_) => socket,
    });
    let mut buffer = [0u8; 1472];
    loop {
        let (size, from) = match bridge
            .socket
            .as_ref()
            .expect("socket")
            .recv_from(&mut buffer)
        {
            Ok(packet) => packet,
            Err(exc) => {
                eprintln!("glm-osc: recv failed: {exc}");
                continue;
            }
        };
        if let Some((address, args)) = decode(&buffer[..size]) {
            bridge.handle(from, &address, &args);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc_round_trips_floats_ints_and_strings() {
        let packet = encode(
            "/glm/volume/up",
            &[Arg::Float(1.5), Arg::Int(-2), Arg::Str("green".to_string())],
        );
        assert_eq!(
            decode(&packet),
            Some((
                "/glm/volume/up".to_string(),
                vec![Arg::Float(1.5), Arg::Int(-2), Arg::Str("green".to_string())]
            ))
        );
        // Four-byte alignment is what makes the packet decodable at all.
        assert_eq!(packet.len() % 4, 0);
    }

    #[test]
    fn address_only_messages_decode() {
        let packet = encode("/glm/mute/toggle", &[]);
        assert_eq!(
            decode(&packet),
            Some(("/glm/mute/toggle".to_string(), Vec::new()))
        );
    }

    #[test]
    fn state_defaults_and_parses() {
        let dir = std::env::temp_dir().join(format!("glm-osc-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("state.json");
        assert_eq!(load_state(&path), State::default());
        std::fs::write(
            &path,
            r#"{"volume_db": -12.5, "muted": true, "power": false}"#,
        )
        .unwrap();
        let state = load_state(&path);
        assert_eq!(state.volume_db, -12.5);
        assert!(state.muted);
        assert!(!state.power);
        save_state(&path, &state);
        assert_eq!(load_state(&path), state);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn tails_are_truncated_for_logs() {
        assert_eq!(tail("short", 10), "short");
        assert_eq!(tail("0123456789", 4), "6789");
    }

    #[test]
    fn json_field_slices_the_daemon_status_line() {
        let line = r#"{"cycles":42,"volume_db":-24.5,"leases":[{"hardware_id":"127529","session":3}],"telemetry":{"03":"41 2E 81 00"}}"#;
        assert_eq!(json_field(line, "cycles").as_deref(), Some("42"));
        assert_eq!(json_field(line, "volume_db").as_deref(), Some("-24.5"));
        assert_eq!(
            json_field(line, "leases").as_deref(),
            Some(r#"[{"hardware_id":"127529","session":3}]"#)
        );
        assert_eq!(
            json_field(line, "telemetry").as_deref(),
            Some(r#"{"03":"41 2E 81 00"}"#)
        );
        // No volume yet is `null`, and a truncated frame must not panic.
        assert_eq!(
            json_field(r#"{"cycles":1,"volume_db":null}"#, "volume_db").as_deref(),
            Some("null")
        );
        assert_eq!(json_field(r#"{"leases":[{]"#, "leases"), None);
        assert_eq!(json_field(line, "nope"), None);
    }

    #[test]
    fn daemon_speaks_the_glm5d_line_protocol() {
        use std::os::unix::net::UnixListener;

        let dir = std::env::temp_dir().join(format!("glm-osc-daemon-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("glm5d.sock");
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path).unwrap();
        // The stub stands in for the daemon: same one-line-in/one-line-out protocol.
        let stub = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut writer = stream;
            let mut line = String::new();
            while reader.read_line(&mut line).unwrap_or(0) > 0 {
                let command = line.trim().to_string();
                line.clear();
                let reply = match command.as_str() {
                    "status" => {
                        r#"{"cycles":7,"volume_db":-31.5,"leases":[{"hardware_id":"127529","session":3}],"telemetry":{"03":"41 2E"}}"#
                    }
                    _ => "ok queued",
                };
                writeln!(writer, "{reply}").unwrap();
                writer.flush().unwrap();
            }
        });

        let mut daemon = Daemon::new(path.clone());
        assert_eq!(
            daemon.command("volume -31.50").as_deref(),
            Some("ok queued")
        );
        assert_eq!(daemon.command("mute on").as_deref(), Some("ok queued"));
        assert!(!daemon.down);
        let status = daemon.status().unwrap();
        assert_eq!(json_field(&status, "cycles").as_deref(), Some("7"));
        assert_eq!(json_field(&status, "volume_db").as_deref(), Some("-31.5"));
        drop(daemon);
        let _ = stub.join();

        // A host without the daemon must degrade to the CLI, not fail.
        std::fs::remove_file(&path).ok();
        let mut gone = Daemon::new(path.clone());
        assert!(gone.command("volume -20.00").is_none());
        assert!(gone.down);
        assert!(gone.status().is_none());
        std::fs::remove_dir_all(&dir).ok();
    }
}
