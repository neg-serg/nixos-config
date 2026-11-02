//! renoise-osc — send OSC to the Renoise built-in OSC server (UDP :9002).
//!
//! The CLI surface is a port of the previous Python sender, kept byte-for-byte
//! compatible: the same OSC encoding (including its padding quirk), the same
//! commands, the same messages and exit codes. Invoked as `renoise-reverb` or
//! `renoise-record` (symlinks installed by the package) it prepends the
//! matching subcommand, so one binary backs all three entry points.

use std::env;
use std::fs;
use std::io::Write;
use std::net::UdpSocket;
use std::path::PathBuf;
use std::process::{self, Command};
use std::thread;
use std::time::{Duration, Instant};

const DEFAULT_HOST: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 9002;

const DOC: &str = "\
renoise-osc — send OSC to the Renoise built-in OSC server (UDP :9002).

Usage:
  renoise-osc [--host H] [--port P] [--dry] <command> [args...]
  renoise-osc help [command]

Commands:
  status | eval '<lua>' | reverb [--track master|N] [--wet X]
  load '<plugin>'                     new instrument + VST (default Legend HZ)
  transport <start|stop|continue|panic|toggle>
  bpm <20..999> | lpb <1..255> | tpl <1..16>
  loop <pattern|block> <on|off> | loop-sequence <start> <end>
  track <idx|-1> mute|unmute|solo|volume|volume-db|post|post-db|pan [value]
  instr <idx|-1> volume-db|transpose <value> | macro <1..8> <0..1>
  device <track> <device> bypass <on|off>
  record [--out FILE] [--secs N] [--target NODE]
  <osc-pattern> [args...]             raw OSC message
--dry prints the OSC message instead of sending. Default port from env
RENOISE_OSC_PORT; protocol UDP (apply while Renoise is closed with
renoise-osc-config). See docs/howto/renoise-tidal-live.md.";

/// One OSC argument, in the shapes the CLI produces.
#[derive(Clone, Debug, PartialEq)]
enum Arg {
    Bool(bool),
    Float(f64),
    Int(i64),
    Str(String),
}

impl Arg {
    fn tag(&self) -> u8 {
        match self {
            Arg::Bool(true) => b'T',
            Arg::Bool(false) => b'F',
            Arg::Float(_) => b'f',
            Arg::Int(_) => b'i',
            Arg::Str(_) => b's',
        }
    }

    /// Python `repr` of the value, so dry runs read like they always did.
    fn py_repr(&self) -> String {
        match self {
            Arg::Bool(true) => "True".to_string(),
            Arg::Bool(false) => "False".to_string(),
            Arg::Float(v) => py_repr_float(*v),
            Arg::Int(v) => v.to_string(),
            Arg::Str(s) => py_repr_str(s),
        }
    }
}

/// `repr()` of a Python string: single quotes, unless the value holds a single
/// quote and no double quote (then Python switches to double quotes).
fn py_repr_str(s: &str) -> String {
    if s.contains('\'') && !s.contains('"') {
        return format!("\"{}\"", s.replace('\\', "\\\\"));
    }
    format!("'{}'", s.replace('\\', "\\\\").replace('\'', "\\'"))
}

/// `repr()` of a Python float: integral values keep their `.0`.
fn py_repr_float(v: f64) -> String {
    if v.is_finite() && v.fract() == 0.0 && v.abs() < 1e16 {
        format!("{v:.1}")
    } else {
        format!("{v}")
    }
}

/// OSC string: NUL padding to a multiple of four bytes.
///
/// The previous sender padded with `4 - len % 4` bytes, i.e. a string whose
/// length is already a multiple of four still gains four NULs. Renoise accepts
/// it, and keeping the quirk keeps every message byte-identical.
fn osc_string(bytes: &[u8]) -> Vec<u8> {
    let mut out = bytes.to_vec();
    let pad = 4 - (bytes.len() % 4);
    out.extend(std::iter::repeat_n(0u8, pad));
    out
}

fn build_message(pattern: &str, args: &[Arg]) -> Vec<u8> {
    let mut tags = vec![b','];
    let mut payload = Vec::new();
    for arg in args {
        tags.push(arg.tag());
        match arg {
            Arg::Float(v) => payload.extend_from_slice(&(*v as f32).to_be_bytes()),
            Arg::Int(v) => payload.extend_from_slice(&(*v as i32).to_be_bytes()),
            Arg::Str(s) => payload.extend(osc_string(s.as_bytes())),
            Arg::Bool(_) => {}
        }
    }
    let mut msg = osc_string(pattern.as_bytes());
    msg.extend(osc_string(&tags));
    msg.extend(payload);
    msg
}

/// True when any UDP socket in `/proc/net/udp{6}` is bound to `port`.
///
/// The check is a plain substring search for `:PORT` in four uppercase hex
/// digits, exactly like the Python version.
fn udp_port_bound(port: u16) -> bool {
    let needle = format!(":{port:04X}");
    for table in ["/proc/net/udp", "/proc/net/udp6"] {
        let Ok(contents) = fs::read_to_string(table) else {
            continue;
        };
        for line in contents.lines().skip(1) {
            if line.contains(&needle) {
                return true;
            }
        }
    }
    false
}

fn renoise_running() -> bool {
    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.chars().all(|c| c.is_ascii_digit()) {
            continue;
        }
        let Ok(comm) = fs::read_to_string(entry.path().join("comm")) else {
            continue;
        };
        // Renoise's own comm is "renoise"; our wrappers share the prefix but
        // must not count as a running Renoise (the Python sender never matched
        // itself because its comm was "python3").
        let comm = comm.trim();
        if comm.starts_with("renoise") && !comm.starts_with("renoise-") {
            return true;
        }
    }
    false
}

fn start_renoise(port: u16, wait_secs: u64) -> bool {
    if udp_port_bound(port) {
        return true;
    }
    println!("renoise not running - starting it ...");
    let spawned = Command::new("renoise")
        .stdout(process::Stdio::null())
        .stderr(process::Stdio::null())
        .spawn();
    if let Err(exc) = spawned {
        eprintln!("failed to start renoise: {exc}");
        return false;
    }
    let deadline = Instant::now() + Duration::from_secs(wait_secs);
    while Instant::now() < deadline {
        if udp_port_bound(port) {
            return true;
        }
        thread::sleep(Duration::from_secs(1));
    }
    eprintln!(
        "renoise OSC UDP port {port} did not open within {wait_secs}s — check Preferences -> OSC (protocol UDP, port {port})."
    );
    false
}

/// Parse a number the way the Python CLI did: any failure is a usage error.
fn parse_num(value: &str, what: &str) -> Result<f64, i32> {
    match value.trim().parse::<f64>() {
        Ok(v) => Ok(v),
        Err(_) => {
            eprintln!("invalid {what}: '{value}'");
            Err(2)
        }
    }
}

fn bool_arg(value: &str, what: &str) -> Result<bool, i32> {
    match value.to_lowercase().as_str() {
        "on" | "true" | "1" | "yes" => Ok(true),
        "off" | "false" | "0" | "no" => Ok(false),
        _ => {
            eprintln!("invalid boolean for {what}: '{value}' (use on/off)");
            Err(2)
        }
    }
}

fn lua_reverb(track_sel: &str, wet: Option<f64>) -> String {
    let sel = if track_sel == "master" {
        "local s=renoise.song() local t for _,x in ipairs(s.tracks) do if x.type==2 then t=x end end"
            .to_string()
    } else {
        let idx = match track_sel.parse::<i64>() {
            Ok(idx) => idx,
            Err(_) => {
                eprintln!("ignoring non-numeric track selector: '{track_sel}'");
                1
            }
        };
        format!("local s=renoise.song() local t=s.tracks[{idx}]")
    };
    let mut lua = format!(
        "local ok,err=pcall(function() {sel} local d=nil for _,i in ipairs(t.available_device_infos) do if string.lower(i.name)=='reverb' then d=t:insert_device_at(i.path,#t.devices+1) break end end"
    );
    if let Some(wet) = wet {
        lua.push_str(&format!(
            " if d then for _,p in ipairs(d.parameters) do if p.name=='Send' then p.value={wet:.4} end end end"
        ));
    }
    lua.push_str(" end) if not ok then print('renoise-reverb error: '..tostring(err)) end");
    lua
}

fn lua_load_plugin(name: &str) -> String {
    let esc = name.replace('\\', "\\\\").replace('\'', "\\'");
    let lower = name.to_lowercase().replace('\'', "");
    format!(
        "local ok,err=pcall(function() local s=renoise.song() local inst=s:insert_instrument_at(#s.instruments+1) local path=nil for _,i in ipairs(inst.plugin_properties.available_plugin_infos) do if string.lower(i.name):find('{lower}',1,true) then path=i.path break end end if not path then error('plugin not found: {esc}') end inst.plugin_properties:load_plugin(path) s.selected_instrument_index=#s.instruments end) if not ok then print('renoise-load error: '..tostring(err)) end"
    )
}

fn lua_transport_toggle() -> String {
    "if renoise.transport.playing then renoise.transport:stop() else renoise.transport:start() end"
        .to_string()
}

fn track_op(name: &str) -> Option<(&'static str, usize)> {
    Some(match name {
        "mute" => ("mute", 0),
        "unmute" => ("unmute", 0),
        "solo" => ("solo", 0),
        "volume" => ("prefx_volume", 1),
        "volume-db" => ("prefx_volume_db", 1),
        "post" => ("postfx_volume", 1),
        "post-db" => ("postfx_volume_db", 1),
        "pan" => ("prefx_panning", 1),
        _ => return None,
    })
}

fn instr_op(name: &str) -> Option<&'static str> {
    Some(match name {
        "volume-db" => "volume_db",
        "transpose" => "transpose",
        _ => return None,
    })
}

fn topic_help(topic: &str) -> Option<&'static str> {
    Some(match topic {
        "record" => {
            "renoise-osc record [--out FILE] [--secs N] [--target NODE]\n  Default: ~/src/art/music/renoise/recordings/renoise-<ts>.wav on the\n  game-stereo sink (renoise-link feeds it); --target renoise captures\n  only Renoise. Offline render stays GUI: File -> Export Audio."
        }
        "loop" => "renoise-osc loop <pattern|block> <on|off>\nrenoise-osc loop-sequence <start> <end>",
        "transport" => "renoise-osc transport <start|stop|continue|panic|toggle>",
        _ => return None,
    })
}

struct Target {
    host: String,
    port: u16,
    dry: bool,
}

fn send(target: &Target, pattern: &str, args: &[Arg]) -> i32 {
    let msg = build_message(pattern, args);
    if target.dry {
        let list: Vec<String> = args.iter().map(Arg::py_repr).collect();
        println!(
            "[dry] {pattern} [{}] ({} bytes)",
            list.join(", "),
            msg.len()
        );
        return 0;
    }
    let socket = match UdpSocket::bind(("0.0.0.0", 0)) {
        Ok(socket) => socket,
        Err(exc) => {
            eprintln!("send to {}:{} failed: {exc}", target.host, target.port);
            return 1;
        }
    };
    if let Err(exc) = socket.send_to(&msg, (target.host.as_str(), target.port)) {
        eprintln!("send to {}:{} failed: {exc}", target.host, target.port);
        return 1;
    }
    println!(
        "{pattern} -> {}:{} ({} bytes)",
        target.host,
        target.port,
        msg.len()
    );
    0
}

fn cmd_status(target: &Target) -> i32 {
    let running = renoise_running();
    let bound = udp_port_bound(target.port);
    println!(
        "Renoise running:     {}",
        if running { "yes" } else { "no" }
    );
    println!(
        "OSC UDP {}:{}: {}",
        target.host,
        target.port,
        if bound { "bound" } else { "not bound" }
    );
    if !running && !bound {
        println!("start it with: renoise-osc load 'Legend HZ' (or just 'renoise')");
        return 1;
    }
    if running && !bound {
        eprintln!("Renoise is up but the OSC UDP port is closed — check Preferences -> OSC:");
        return 1;
    }
    0
}

fn cmd_transport(target: &Target, action: &str) -> i32 {
    match action {
        "toggle" => send(
            target,
            "/renoise/evaluate",
            &[Arg::Str(lua_transport_toggle())],
        ),
        "start" | "stop" | "continue" | "panic" => {
            send(target, &format!("/renoise/transport/{action}"), &[])
        }
        _ => {
            eprintln!("usage: renoise-osc transport <start|stop|continue|panic|toggle>");
            2
        }
    }
}

fn cmd_timing(target: &Target, kind: &str, value: &str) -> i32 {
    let (lo, hi) = match kind {
        "bpm" => (20.0, 999.0),
        "lpb" => (1.0, 255.0),
        _ => (1.0, 16.0),
    };
    let v = match parse_num(value, kind) {
        Ok(v) => v,
        Err(code) => return code,
    };
    // `max(lo, min(hi, v))` with integer bounds: a clamped value is an int and
    // therefore goes out with OSC tag "i", an in-range value stays a float.
    let arg = if v < lo {
        Arg::Int(lo as i64)
    } else if v > hi {
        Arg::Int(hi as i64)
    } else {
        Arg::Float(v)
    };
    send(target, &format!("/renoise/song/{kind}"), &[arg])
}

fn cmd_loop(target: &Target, argv: &[String]) -> i32 {
    if argv.len() == 3 && argv[0] == "sequence" {
        let start = match parse_num(&argv[1], "start") {
            Ok(v) => v,
            Err(code) => return code,
        };
        let end = match parse_num(&argv[2], "end") {
            Ok(v) => v,
            Err(code) => return code,
        };
        return send(
            target,
            "/renoise/transport/loop/sequence",
            &[Arg::Float(start), Arg::Float(end)],
        );
    }
    if argv.len() == 2 {
        let path = match argv[0].as_str() {
            "pattern" => Some("loop/pattern"),
            "block" => Some("loop/block"),
            _ => None,
        };
        if let Some(path) = path {
            let on = match bool_arg(&argv[1], &argv[0]) {
                Ok(on) => on,
                Err(code) => return code,
            };
            return send(
                target,
                &format!("/renoise/transport/{path}"),
                &[Arg::Bool(on)],
            );
        }
    }
    eprintln!("{}", topic_help("loop").unwrap_or_default());
    2
}

fn cmd_track(target: &Target, argv: &[String]) -> i32 {
    if argv.len() < 2 {
        eprintln!("usage: renoise-osc track <idx|-1> <mute|unmute|solo|volume|volume-db|post|post-db|pan> [value]");
        return 2;
    }
    let (idx, op) = (&argv[0], &argv[1]);
    let Some((suffix, nvals)) = track_op(op) else {
        let ops = [
            "mute",
            "unmute",
            "solo",
            "volume",
            "volume-db",
            "post",
            "post-db",
            "pan",
        ];
        eprintln!("track ops: {}", ops.join(", "));
        return 2;
    };
    let vals = &argv[2..(2 + nvals).min(argv.len())];
    if vals.len() != nvals {
        eprintln!("track {op}: expected {nvals} value(s)");
        return 2;
    }
    let mut args = Vec::new();
    for v in vals {
        match parse_num(v, "value") {
            Ok(v) => args.push(Arg::Float(v)),
            Err(code) => return code,
        }
    }
    send(
        target,
        &format!("/renoise/song/track/{idx}/{suffix}"),
        &args,
    )
}

fn cmd_instr(target: &Target, argv: &[String]) -> i32 {
    if argv.len() < 2 {
        eprintln!(
            "usage: renoise-osc instr <idx|-1> <volume-db|transpose> <value> | macro <k> <val>"
        );
        return 2;
    }
    let (idx, op) = (&argv[0], &argv[1]);
    if op == "macro" {
        if argv.len() != 4 {
            eprintln!("usage: renoise-osc instr <idx> macro <1..8> <0..1>");
            return 2;
        }
        let k = match parse_num(&argv[2], "macro index") {
            Ok(v) => v as i64,
            Err(code) => return code,
        };
        if !(1..=8).contains(&k) {
            eprintln!("macro index must be 1..8");
            return 2;
        }
        let value = match parse_num(&argv[3], "value") {
            Ok(v) => v,
            Err(code) => return code,
        };
        return send(
            target,
            &format!("/renoise/song/instrument/{idx}/macro{k}"),
            &[Arg::Float(value)],
        );
    }
    let Some(suffix) = instr_op(op) else {
        eprintln!("instr ops: volume-db <db> | transpose <st> | macro <k> <val>");
        return 2;
    };
    if argv.len() != 3 {
        eprintln!("instr ops: volume-db <db> | transpose <st> | macro <k> <val>");
        return 2;
    }
    let value = match parse_num(&argv[2], "value") {
        Ok(v) => v,
        Err(code) => return code,
    };
    send(
        target,
        &format!("/renoise/song/instrument/{idx}/{suffix}"),
        &[Arg::Float(value)],
    )
}

fn cmd_device(target: &Target, argv: &[String]) -> i32 {
    if argv.len() != 4 || argv[2] != "bypass" {
        eprintln!("usage: renoise-osc device <track> <device> bypass <on|off>");
        return 2;
    }
    let on = match bool_arg(&argv[3], "bypass") {
        Ok(on) => on,
        Err(code) => return code,
    };
    send(
        target,
        &format!("/renoise/song/track/{}/device/{}/bypass", argv[0], argv[1]),
        &[Arg::Bool(on)],
    )
}

fn cmd_record(target: &Target, argv: &[String]) -> i32 {
    let mut out: Option<PathBuf> = None;
    let mut secs: Option<f64> = None;
    let mut sink = "playback.game-stereo".to_string();
    let mut i = 0;
    while i < argv.len() {
        match argv[i].as_str() {
            "--out" if i + 1 < argv.len() => {
                out = Some(PathBuf::from(&argv[i + 1]));
                i += 2;
            }
            "--secs" if i + 1 < argv.len() => {
                secs = match parse_num(&argv[i + 1], "--secs") {
                    Ok(v) => Some(v.max(0.0)),
                    Err(code) => return code,
                };
                i += 2;
            }
            "--target" if i + 1 < argv.len() => {
                sink = argv[i + 1].clone();
                i += 2;
            }
            other => {
                eprintln!("unknown record arg: {other}");
                return 2;
            }
        }
    }
    if target.dry {
        let shown = out
            .as_ref()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|| "<~/src/art/music/renoise/recordings/renoise-<ts>.wav>".to_string());
        let mut cmd = vec![
            "pw-record".to_string(),
            "--target".to_string(),
            sink.clone(),
            "--rate".to_string(),
            "48000".to_string(),
        ];
        if let Some(secs) = secs {
            cmd.push("-n".to_string());
            cmd.push(format!("{}", (secs * 48000.0) as i64));
        }
        cmd.push(shown);
        println!("[dry] {}", cmd.join(" "));
        return 0;
    }
    if !udp_port_bound(target.port) {
        eprintln!("renoise OSC not bound — is Renoise running? (renoise-osc status)");
        return 1;
    }
    let out = match out {
        Some(out) => out,
        None => {
            let outdir = home_dir().join("src/art/music/renoise/recordings");
            if let Err(exc) = fs::create_dir_all(&outdir) {
                eprintln!("cannot create {}: {exc}", outdir.display());
                return 1;
            }
            let stamp = Command::new("date")
                .arg("+%Y%m%d-%H%M%S")
                .output()
                .ok()
                .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
                .filter(|s| !s.is_empty())
                .unwrap_or_else(|| "now".to_string());
            outdir.join(format!("renoise-{stamp}.wav"))
        }
    };
    let mut cmd = Command::new("pw-record");
    cmd.arg("--target").arg(&sink).arg("--rate").arg("48000");
    if let Some(secs) = secs {
        // pw-record has no --duration; stop after N samples at 48 kHz.
        cmd.arg("-n").arg(format!("{}", (secs * 48000.0) as i64));
    }
    cmd.arg(&out);
    println!(
        "Recording Renoise ({sink}) -> {}{}",
        out.display(),
        if secs.is_some() {
            ""
        } else {
            "   Ctrl+C to stop."
        }
    );
    let status = cmd.status();
    match status {
        Ok(status) if status.success() => 0,
        Ok(status) => {
            eprintln!("pw-record exited with {}", status.code().unwrap_or(1));
            1
        }
        Err(exc) => {
            eprintln!("pw-record exited with {exc}");
            1
        }
    }
}

fn home_dir() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn cmd_help(topic: Option<&str>) -> i32 {
    if let Some(topic) = topic {
        match topic_help(topic) {
            Some(text) => println!("{text}"),
            None => println!("no extended help for '{topic}'"),
        }
        println!();
    }
    // Python's `print(__doc__)` ends with a blank line: the docstring keeps
    // its trailing newline and print adds another one.
    println!("{DOC}\n");
    0
}

/// Raw OSC argument: numbers as floats, everything else as a string.
fn raw_arg(value: &str) -> Arg {
    match value.trim().parse::<f64>() {
        Ok(v) => Arg::Float(v),
        Err(_) => Arg::Str(value.to_string()),
    }
}

/// `[reverb|record]` when the binary was invoked through an alias symlink.
fn alias_prefix(argv0: &str) -> Option<&'static str> {
    let name = argv0.rsplit('/').next().unwrap_or(argv0);
    match name {
        "renoise-reverb" => Some("reverb"),
        "renoise-record" => Some("record"),
        _ => None,
    }
}

fn run(argv: &[String]) -> i32 {
    let mut host = env::var("RENOISE_OSC_HOST").unwrap_or_else(|_| DEFAULT_HOST.to_string());
    let mut port = env::var("RENOISE_OSC_PORT")
        .ok()
        .and_then(|p| p.trim().parse::<u16>().ok())
        .unwrap_or(DEFAULT_PORT);
    let mut dry = false;
    let mut rest: Vec<String> = Vec::new();
    let mut i = 0;
    while i < argv.len() {
        match argv[i].as_str() {
            "--host" if i + 1 < argv.len() => {
                host = argv[i + 1].clone();
                i += 2;
            }
            "--port" if i + 1 < argv.len() => {
                match argv[i + 1].trim().parse::<u16>() {
                    Ok(p) => port = p,
                    Err(_) => {
                        eprintln!("invalid --port value: '{}'", argv[i + 1]);
                        return 2;
                    }
                }
                i += 2;
            }
            "--dry" => {
                dry = true;
                i += 1;
            }
            "-h" | "--help" => return cmd_help(None),
            other => {
                rest.push(other.to_string());
                i += 1;
            }
        }
    }
    let target = Target { host, port, dry };
    if rest.is_empty() {
        return cmd_help(None);
    }
    let cmd = rest[0].clone();
    let tail = &rest[1..];
    match cmd.as_str() {
        "help" => cmd_help(tail.first().map(String::as_str)),
        "status" => cmd_status(&target),
        "eval" => send(&target, "/renoise/evaluate", &[Arg::Str(tail.join(" "))]),
        "reverb" => {
            let mut track_sel = "master".to_string();
            let mut wet: Option<f64> = None;
            let mut j = 0;
            while j < tail.len() {
                match tail[j].as_str() {
                    "--track" if j + 1 < tail.len() => {
                        track_sel = tail[j + 1].clone();
                        j += 2;
                    }
                    "--wet" if j + 1 < tail.len() => {
                        wet = match parse_num(&tail[j + 1], "--wet") {
                            Ok(v) => Some(v.clamp(0.0, 1.0)),
                            Err(code) => return code,
                        };
                        j += 2;
                    }
                    _ => j += 1,
                }
            }
            send(
                &target,
                "/renoise/evaluate",
                &[Arg::Str(lua_reverb(&track_sel, wet))],
            )
        }
        "load" => {
            let joined = tail.join(" ");
            let plugin = if joined.trim().is_empty() {
                "Legend HZ".to_string()
            } else {
                joined.trim().to_string()
            };
            if !start_renoise(target.port, 45) {
                return 1;
            }
            send(
                &target,
                "/renoise/evaluate",
                &[Arg::Str(lua_load_plugin(&plugin))],
            )
        }
        "transport" => match tail.first() {
            Some(action) => cmd_transport(&target, action),
            None => cmd_help(Some("transport")),
        },
        "bpm" | "lpb" | "tpl" => {
            if tail.len() != 1 {
                eprintln!("usage: renoise-osc {cmd} <value>");
                return 2;
            }
            cmd_timing(&target, &cmd, &tail[0])
        }
        "loop" => cmd_loop(&target, tail),
        "track" => cmd_track(&target, tail),
        "instr" => cmd_instr(&target, tail),
        "device" => cmd_device(&target, tail),
        "record" => cmd_record(&target, tail),
        _ => {
            let args: Vec<Arg> = tail.iter().map(|a| raw_arg(a)).collect();
            send(&target, &cmd, &args)
        }
    }
}

fn main() {
    let mut argv: Vec<String> = env::args().collect();
    let argv0 = argv.first().cloned().unwrap_or_default();
    let tail: Vec<String> = if let Some(prefix) = alias_prefix(&argv0) {
        let mut prefixed = vec![prefix.to_string()];
        prefixed.extend(argv.drain(1..));
        prefixed
    } else {
        argv.drain(1..).collect()
    };
    let code = run(&tail);
    // Flush stdout before exiting: `record` prints before handing the terminal
    // to pw-record, and the dry-run output must not be lost.
    let _ = std::io::stdout().flush();
    process::exit(code);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn osc_string_pads_with_a_full_word() {
        assert_eq!(osc_string(b"abc"), b"abc\0");
        assert_eq!(osc_string(b"abcd"), b"abcd\0\0\0\0");
    }

    #[test]
    fn message_matches_reference_bytes() {
        // /renoise/song/bpm with one float, encoded by the previous sender.
        let msg = build_message("/renoise/song/bpm", &[Arg::Float(120.0)]);
        let mut expected = Vec::new();
        expected.extend(osc_string(b"/renoise/song/bpm"));
        expected.extend(osc_string(b",f"));
        expected.extend_from_slice(&120.0f32.to_be_bytes());
        assert_eq!(msg, expected);
    }

    #[test]
    fn booleans_have_no_payload() {
        let msg = build_message("/x", &[Arg::Bool(true), Arg::Bool(false)]);
        assert_eq!(msg, b"/x\0\0,TF\0".to_vec());
    }

    #[test]
    fn strings_are_padded() {
        let msg = build_message("/x", &[Arg::Str("ab".into())]);
        assert_eq!(msg, b"/x\0\0,s\0\0ab\0\0".to_vec());
    }

    #[test]
    fn py_repr_matches_python() {
        assert_eq!(Arg::Float(1.0).py_repr(), "1.0");
        assert_eq!(Arg::Float(0.5).py_repr(), "0.5");
        assert_eq!(Arg::Bool(true).py_repr(), "True");
        assert_eq!(Arg::Str("a".into()).py_repr(), "'a'");
    }

    #[test]
    fn track_and_instr_tables_are_complete() {
        assert_eq!(track_op("pan"), Some(("prefx_panning", 1)));
        assert_eq!(track_op("mute"), Some(("mute", 0)));
        assert_eq!(track_op("nope"), None);
        assert_eq!(instr_op("volume-db"), Some("volume_db"));
        assert_eq!(instr_op("macro"), None);
    }

    #[test]
    fn alias_names_map_to_subcommands() {
        assert_eq!(
            alias_prefix("/nix/store/x/bin/renoise-reverb"),
            Some("reverb")
        );
        assert_eq!(
            alias_prefix("/nix/store/x/bin/renoise-record"),
            Some("record")
        );
        assert_eq!(alias_prefix("renoise-osc"), None);
    }
}
