//! glm-osc — OSC bridge to Genelec SAM monitors via `genlc`.
//!
//! Listens on UDP `127.0.0.1:9000` (`GLM_OSC_HOST`/`GLM_OSC_PORT`) and turns OSC
//! messages into `genlc` calls, so the monitors can be driven from a DAW, a
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
//! `genlc` stays an external program: it is the third-party implementation of
//! the GLM USB protocol, and reimplementing that would be a different project.
//! The server itself is Rust with no crates — OSC, the UDP loop and the state
//! file are hand-rolled.
//!
//! Environment:
//!   GENLC_CLI      path to the genlc binary
//!   HIDAPI_LIB     LD_LIBRARY_PATH for hidapi (unset = inherit)
//!   GLM_OSC_STATE  JSON state file (volume/mute/power)

use std::collections::BTreeMap;
use std::net::{SocketAddr, UdpSocket};
use std::path::PathBuf;
use std::process::{Command, Stdio};

const DEFAULT_STATE_FILE: &str = "/tmp/glm-osc-state.json";
const DEFAULT_GENLC: &str = "/tmp/glm-osc-venv/bin/genlc";
const DEFAULT_HOST: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 9000;
const GENLC_TIMEOUT_SECONDS: u64 = 40;

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

// -- the bridge --------------------------------------------------------

pub struct Bridge {
    pub state: State,
    pub path: PathBuf,
    socket: Option<UdpSocket>,
}

impl Bridge {
    pub fn new() -> Bridge {
        let path = state_file();
        let state = load_state(&path);
        Bridge {
            state,
            path,
            socket: None,
        }
    }

    fn reply(&self, to: SocketAddr, address: &str, payload: &str) {
        if let Some(socket) = &self.socket {
            let _ = socket.send_to(&encode(address, &[Arg::Str(payload.to_string())]), to);
        }
    }

    pub fn volume(&mut self, db: f64) {
        let output = run_genlc(&["set-volume", "--volume", &format!("{db:.2}dB")]);
        if output.ok {
            self.state.volume_db = db;
            save_state(&self.path, &self.state);
            println!("/glm/volume {db:.2}dB OK");
        } else {
            println!("/glm/volume FAIL: {}", tail(&output.stderr, 200));
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
        let output = run_genlc(&[if on { "mute" } else { "unmute" }]);
        if output.ok {
            self.state.muted = on;
            save_state(&self.path, &self.state);
            println!("/glm/mute {on} OK");
        } else {
            println!("/glm/mute FAIL: {}", tail(&output.stderr, 200));
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

    pub fn status(&mut self, to: SocketAddr) {
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
            ", \"state\": {{\"volume_db\": {}, \"muted\": {}, \"power\": {}}}}}",
            self.state.volume_db, self.state.muted, self.state.power
        ));
        self.reply(to, "/glm/status/reply", &payload);
        println!("/glm/status -> reply");
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
    println!("glm-osc listening on {host}:{port} (genlc: {})", genlc());
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
}
