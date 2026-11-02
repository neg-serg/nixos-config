//! questyle-ctl - inspect and talk to the Questyle QCC Dongle Pro2 (USB 0a12:4007).
//!
//! Port of `modules/hardware/audio/questyle/questyle-ctl.py`. The dongle is a
//! Bluetooth audio transmitter (QCC/CSR chip, vendor id 0a12). It shows up as:
//!   * a USB Audio card - what PipeWire uses, audio goes to the paired headset;
//!   * HID interface 0 - standard Consumer Control/Telephony (the dongle sends
//!     media-key presses to the host);
//!   * HID interface 1 - vendor page 0xFF00, the *proprietary* control channel:
//!       report id 1  : 62-byte output  (commands -> dongle)
//!       report id 5  : 254-byte output (extended/long commands)
//!       report id 2  : 16-byte input   (dongle -> host)
//!       report id 6  : 12-byte input
//!       report id 3/4: 62-byte feature (GET/SET_REPORT, dongle answers with EPIPE)
//!       report id 0xbb/0xcc: 63-byte in/out, 0xfd: 31-byte in/out
//!   * vendor-specific interface 6 (class 255/240, 2 bulk EPs) - unbound, unused.
//!
//! The vendor protocol itself is undocumented; `watch` records what the dongle
//! does say (press its button / connect a headset) and `raw` sends a frame by hand.
//!
//! Subcommands:
//!   info                     what the kernel/PipeWire currently see (safe)
//!   watch [-t N] [--log F]   dump vendor HID input reports (read-only, safe)
//!   raw HEX                  write one output report (report 1) - expert use
//!   feature RID [SIZE]       GET_REPORT on the vendor channel (read-only)
//!
//! No crates: hidraw ioctls, poll and localtime come straight from libc.

use std::ffi::{c_char, c_int, c_long, c_ulong, CStr};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const VID: u16 = 0x0A12;
const PID: u16 = 0x4007;
/// `HID_ID` as sysfs spells it (bus 0003 = USB, upper-case, 8-digit hex).
const HID_ID: &str = "0003:00000A12:00004007";
const HIDIOCGRDESCSIZE: c_ulong = 0x8004_4801;
const HIDIOCGRDESC: c_ulong = 0x9004_4802;
/// `O_NONBLOCK` on Linux.
const O_NONBLOCK: c_int = 0o4000;
const POLLIN: i16 = 0x0001;
const SIGPIPE: c_int = 13;

extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    fn signal(signum: c_int, handler: *const std::ffi::c_void) -> *const std::ffi::c_void;
    fn poll(fds: *mut PollFd, nfds: c_ulong, timeout: c_int) -> c_int;
    fn localtime_r(timep: *const i64, result: *mut Tm) -> *mut Tm;
    fn strerror(errnum: c_int) -> *mut c_char;
}

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}

/// glibc's `struct tm` on 64-bit Linux.
#[repr(C)]
struct Tm {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: *const c_char,
}

fn main() {
    // Die quietly when the reader closes the pipe (`questyle-ctl info | head`):
    // Rust's default SIGPIPE handling turns the failed write into a panic.
    unsafe {
        signal(SIGPIPE, std::ptr::null());
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match parse_args(&args) {
        Ok(Some(cmd)) => run(cmd),
        Ok(None) => 0, // help was printed
        Err(()) => 2,
    };
    std::process::exit(code);
}

// --- hidraw -----------------------------------------------------------------

/// The HID interface carrying usage page 0xFF00 (the vendor channel).
fn is_vendor_channel(dev: &str) -> bool {
    match report_descriptor(dev) {
        Ok(d) => d.windows(3).any(|w| w == b"\x06\x00\xff"),
        Err(_) => false,
    }
}

fn report_descriptor(dev: &str) -> io::Result<Vec<u8>> {
    let file = File::open(dev)?;
    let fd = file.as_raw_fd();

    let mut size_buf = [0u8; 4];
    if unsafe { ioctl(fd, HIDIOCGRDESCSIZE, size_buf.as_mut_ptr()) } < 0 {
        return Err(io::Error::last_os_error());
    }
    let size = u32::from_ne_bytes(size_buf) as usize;

    let mut buf = vec![0u8; 4 + size];
    buf[..4].copy_from_slice(&(size as u32).to_ne_bytes());
    if unsafe { ioctl(fd, HIDIOCGRDESC, buf.as_mut_ptr()) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(buf[4..4 + size].to_vec())
}

/// `[(/dev/hidrawN, sysfs device path), ...]` for this dongle.
fn hidraw_nodes() -> Vec<(String, PathBuf)> {
    let mut names: Vec<String> = match fs::read_dir("/sys/class/hidraw") {
        Ok(rd) => rd
            .filter_map(Result::ok)
            .filter_map(|e| e.file_name().into_string().ok())
            .filter(|n| n.starts_with("hidraw"))
            .collect(),
        Err(_) => return Vec::new(),
    };
    names.sort();

    let mut out = Vec::new();
    for name in names {
        let base = Path::new("/sys/class/hidraw").join(&name);
        let uevent = match fs::read_to_string(base.join("device/uevent")) {
            Ok(s) => s,
            Err(_) => continue,
        };
        if !uevent.contains(HID_ID) {
            continue;
        }
        let device = base.join("device");
        let sysdev = fs::canonicalize(&device).unwrap_or(device);
        out.push((format!("/dev/{name}"), sysdev));
    }
    out
}

fn vendor_node() -> Option<String> {
    hidraw_nodes()
        .into_iter()
        .map(|(dev, _)| dev)
        .find(|dev| is_vendor_channel(dev))
}

// --- state readers ----------------------------------------------------------

fn read_trim(path: impl AsRef<Path>) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}

fn usb_info() -> Vec<String> {
    let mut lines = Vec::new();
    let entries = match fs::read_dir("/sys/bus/usb/devices") {
        Ok(rd) => rd
            .filter_map(Result::ok)
            .map(|e| e.path())
            .collect::<Vec<_>>(),
        Err(_) => return lines,
    };
    for dir in entries {
        let (idv, idp) = match (
            read_trim(dir.join("idVendor")),
            read_trim(dir.join("idProduct")),
        ) {
            (Some(v), Some(p)) => (v, p),
            _ => continue,
        };
        let ids = (
            u16::from_str_radix(&idv, 16).ok(),
            u16::from_str_radix(&idp, 16).ok(),
        );
        if ids != (Some(VID), Some(PID)) {
            continue;
        }
        let rd = |name: &str| read_trim(dir.join(name)).unwrap_or_else(|| "?".to_string());
        lines.push(format!("  sysfs path  : {}", dir.display()));
        lines.push(format!(
            "  product     : {} {}",
            rd("manufacturer"),
            rd("product")
        ));
        lines.push(format!(
            "  serial      : {}  rev {}",
            rd("serial"),
            rd("bcdDevice")
        ));
        lines.push(format!(
            "  speed       : {} Mbps, max power {}",
            rd("speed"),
            rd("bMaxPower")
        ));
        lines.push(format!(
            "  power/ctl   : autosuspend={}",
            rd("power/control")
        ));
    }
    lines
}

/// The ALSA card number and name of the dongle, from `/proc/asound/cards`.
fn alsa_card() -> Option<(u32, String)> {
    let cards = fs::read_to_string("/proc/asound/cards").ok()?;
    parse_alsa_cards(&cards)
}

fn parse_alsa_cards(cards: &str) -> Option<(u32, String)> {
    for line in cards.lines() {
        let line = line.trim_start();
        let Some((number, rest)) = line.split_once('[') else {
            continue;
        };
        let Ok(card) = number.trim().parse::<u32>() else {
            continue;
        };
        let Some((_id, rest)) = rest.split_once("]:") else {
            continue;
        };
        let Some(name) = rest.trim_start().strip_prefix("USB-Audio - ") else {
            continue;
        };
        let name = name.trim();
        if name.contains("QCC Dongle") || name.contains("Questyle") {
            return Some((card, name.to_string()));
        }
    }
    None
}

fn alsa_info(card: u32) -> Vec<String> {
    let stream = match fs::read_to_string(format!("/proc/asound/card{card}/stream0")) {
        Ok(s) => s,
        Err(_) => return vec!["  (no stream info)".to_string()],
    };
    parse_alsa_stream(&stream)
}

fn parse_alsa_stream(stream: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut state = String::new();
    let mut format = String::new();
    for line in stream.lines() {
        let s = line.trim();
        if s.starts_with("Status:") {
            state = s.to_string();
        } else if s.starts_with("Momentary freq") {
            lines.push(format!("  {s}"));
        } else if s.starts_with("Format:") {
            let value = s.split_once(':').map(|(_, v)| v.trim()).unwrap_or("");
            format = format!("{format} {value}").trim().to_string();
        }
    }
    let format = if format.is_empty() {
        "idle".to_string()
    } else {
        format
    };
    lines.insert(0, format!("  playback    : {state}  [{format}]"));
    lines
}

fn run_capture(prog: &str, args: &[&str], timeout: Duration) -> Option<String> {
    let mut child = Command::new(prog)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let start = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) => {
                if start.elapsed() >= timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return None;
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(_) => return None,
        }
    }
    let mut out = String::new();
    if let Some(mut stdout) = child.stdout.take() {
        let _ = stdout.read_to_string(&mut out);
    }
    Some(out)
}

fn mixer_info(card: u32) -> Vec<String> {
    let card = card.to_string();
    let out = match run_capture("amixer", &["-c", &card], Duration::from_secs(5)) {
        Some(o) => o,
        None => return vec!["  (amixer unavailable)".to_string()],
    };
    parse_mixer(&out)
}

fn parse_mixer(out: &str) -> Vec<String> {
    let mut keep = Vec::new();
    let mut name = String::new();
    for line in out.lines() {
        if line.starts_with("Simple mixer control") {
            let stripped = line.trim();
            name = match stripped.split('\'').nth(1) {
                Some(quoted) => quoted.to_string(),
                None => stripped.to_string(),
            };
        } else if line.contains("Playback")
            || line.contains("Capture")
            || line.trim_start().starts_with("Mono:")
        {
            keep.push(format!("  {name}: {}", line.trim()));
        }
    }
    if keep.is_empty() {
        vec!["  (no controls)".to_string()]
    } else {
        keep
    }
}

fn pipewire_info() -> Vec<String> {
    let status = match run_capture("wpctl", &["status"], Duration::from_secs(5)) {
        Some(o) => o,
        None => return vec!["  (wpctl unavailable)".to_string()],
    };
    parse_pipewire(
        &status,
        run_capture("pw-link", &["-l"], Duration::from_secs(5)).as_deref(),
    )
}

fn parse_pipewire(status: &str, links: Option<&str>) -> Vec<String> {
    let mut lines = Vec::new();
    for line in status.lines() {
        if line.contains("QCC") || line.contains("Mpow HC5") || line.contains("Questyle") {
            lines.push(format!("  {}", line.trim()));
        }
    }
    let routed: Vec<String> = links
        .unwrap_or("")
        .lines()
        .filter(|l| l.contains("alsa_output.usb-Questyle") || l.contains("Mpow"))
        .map(|l| l.trim().to_string())
        .collect();
    if !routed.is_empty() {
        lines.push("  links:".to_string());
        lines.extend(routed.iter().map(|l| format!("    {l}")));
    }
    if lines.is_empty() {
        vec!["  (device not in the current PipeWire graph)".to_string()]
    } else {
        lines
    }
}

// --- subcommands ------------------------------------------------------------

fn cmd_info() -> i32 {
    println!("USB");
    let usb = usb_info();
    if usb.is_empty() {
        println!("  (device not found - подключён?)");
    } else {
        for line in usb {
            println!("{line}");
        }
    }

    println!("HID interfaces");
    for (dev, _) in hidraw_nodes() {
        let role = if is_vendor_channel(&dev) {
            "vendor/proprietary control (page 0xFF00)"
        } else {
            "consumer control"
        };
        println!("  {dev:<14} {role}");
    }

    match alsa_card() {
        Some((card, name)) => {
            println!("ALSA card {card}: {name}");
            for line in alsa_info(card).into_iter().chain(mixer_info(card)) {
                println!("{line}");
            }
        }
        None => println!("ALSA: (card not found)"),
    }

    println!("PipeWire");
    for line in pipewire_info() {
        println!("{line}");
    }
    0
}

fn poll_read(fd: c_int, timeout_ms: c_int) -> bool {
    let mut pfd = PollFd {
        fd,
        events: POLLIN,
        revents: 0,
    };
    unsafe { poll(&mut pfd, 1, timeout_ms) > 0 }
}

fn now_hms() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let mut tm: Tm = unsafe { std::mem::zeroed() };
    let ok = unsafe { !localtime_r(&secs, &mut tm).is_null() };
    if !ok {
        return "00:00:00".to_string();
    }
    format!("{:02}:{:02}:{:02}", tm.tm_hour, tm.tm_min, tm.tm_sec)
}

fn cmd_watch(time: f64, log: Option<&str>) -> i32 {
    let Some(node) = vendor_node() else {
        eprintln!("vendor HID channel not found");
        return 1;
    };
    let file = match OpenOptions::new()
        .read(true)
        .custom_flags(O_NONBLOCK)
        .open(&node)
    {
        Ok(f) => f,
        Err(e) => {
            eprintln!("questyle-ctl: {node}: {e}");
            return 1;
        }
    };
    let mut log_file = match log {
        Some(path) => match OpenOptions::new().create(true).append(true).open(path) {
            Ok(f) => Some(f),
            Err(e) => {
                eprintln!("questyle-ctl: {path}: {e}");
                return 1;
            }
        },
        None => None,
    };

    println!(
        "watching {node} for {}s (read-only; press the dongle's button / connect a headset)",
        py_float(time)
    );
    let end = Instant::now() + Duration::from_secs_f64(time.max(0.0));
    let fd = file.as_raw_fd();
    let mut buf = [0u8; 512];
    while Instant::now() < end {
        if !poll_read(fd, 500) {
            continue;
        }
        let n = match (&file).read(&mut buf) {
            Ok(n) => n,
            Err(_) => continue,
        };
        if n == 0 {
            continue;
        }
        let line = format!(
            "[{}] rid={:#04x} len={} {}",
            now_hms(),
            buf[0],
            n - 1,
            hex_spaced(&buf[1..n])
        );
        println!("{line}");
        if let Some(f) = log_file.as_mut() {
            let _ = writeln!(f, "{line}");
        }
    }
    0
}

fn cmd_raw(hex: &str) -> i32 {
    let Some(node) = vendor_node() else {
        eprintln!("vendor HID channel not found");
        return 1;
    };
    let Some(mut payload) = parse_hex(hex) else {
        eprintln!("questyle-ctl: invalid hex bytes: {hex}");
        return 1;
    };
    if payload.is_empty() {
        eprintln!("empty payload");
        return 2;
    }
    // The report id comes from the descriptor; 1 = 62-byte output.
    if payload[0] == 0x00 {
        payload.insert(0, 1);
    }
    println!(
        "-> {node}: {} ({} bytes)",
        hex_spaced(&payload),
        payload.len()
    );
    let mut file = match OpenOptions::new().read(true).write(true).open(&node) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("questyle-ctl: {node}: {e}");
            return 1;
        }
    };
    match file.write(&payload) {
        Ok(n) => {
            println!("write() ok, {n} bytes");
            0
        }
        Err(e) => {
            eprintln!("questyle-ctl: write: {e}");
            1
        }
    }
}

/// The `_IOC` request for a HIDIOCGFEATURE of `size` bytes: 0xC0 (read+write,
/// HID type 'H') with the size in the argument field.
fn feature_request(size: usize) -> c_ulong {
    (0xC000_0000u64 | (((size + 1) as u64) << 16) | (0x48 << 8) | 0x07) as c_ulong
}

fn cmd_feature(rid: i64, size: usize, node_override: Option<&str>) -> i32 {
    let node = match node_override.map(str::to_string).or_else(vendor_node) {
        Some(n) => n,
        None => {
            eprintln!("vendor HID channel not found");
            return 1;
        }
    };
    let file = match OpenOptions::new().read(true).write(true).open(&node) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("questyle-ctl: {node}: {e}");
            return 1;
        }
    };
    let mut buf = vec![0u8; size + 1];
    buf[0] = (rid & 0xFF) as u8;
    let rc = unsafe { ioctl(file.as_raw_fd(), feature_request(size), buf.as_mut_ptr()) };
    if rc < 0 {
        let err = io::Error::last_os_error();
        eprintln!("feature {rid:#04x}: {}", os_error_string(&err));
        return 1;
    }
    println!("feature {rid:#04x}: {}", hex_spaced(&buf[1..]));
    0
}

fn os_error_string(err: &io::Error) -> String {
    match err.raw_os_error() {
        Some(n) => {
            let msg = unsafe {
                let ptr = strerror(n);
                if ptr.is_null() {
                    String::new()
                } else {
                    CStr::from_ptr(ptr).to_string_lossy().into_owned()
                }
            };
            format!("[Errno {n}] {msg}")
        }
        None => err.to_string(),
    }
}

// --- helpers ----------------------------------------------------------------

fn hex_spaced(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<Vec<_>>()
        .join(" ")
}

/// `bytes.fromhex`, plus the spaces and commas the Python version stripped.
fn parse_hex(text: &str) -> Option<Vec<u8>> {
    let cleaned: String = text
        .chars()
        .filter(|c| !c.is_ascii_whitespace() && *c != ',')
        .collect();
    if cleaned.len() % 2 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(cleaned.len() / 2);
    let bytes = cleaned.as_bytes();
    for pair in bytes.chunks(2) {
        let hi = (pair[0] as char).to_digit(16)?;
        let lo = (pair[1] as char).to_digit(16)?;
        out.push((hi * 16 + lo) as u8);
    }
    Some(out)
}

/// `str(float)` as Python prints it: `30.0`, not `30`.
fn py_float(value: f64) -> String {
    let text = format!("{value}");
    if text.contains(['.', 'e', 'E']) || text.contains("inf") || text.contains("NaN") {
        text
    } else {
        format!("{text}.0")
    }
}

fn parse_py_float(text: &str) -> Option<f64> {
    text.trim().parse::<f64>().ok()
}

/// `int(text, 0)`: decimal, `0x`/`0o`/`0b` prefixes, optional sign.
fn parse_int_base0(text: &str) -> Option<i64> {
    let text = text.trim();
    let (negative, body) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text.strip_prefix('+').unwrap_or(text)),
    };
    if body.is_empty() {
        return None;
    }
    let value = if let Some(hex) = body.strip_prefix("0x").or_else(|| body.strip_prefix("0X")) {
        i64::from_str_radix(hex, 16).ok()?
    } else if let Some(oct) = body.strip_prefix("0o").or_else(|| body.strip_prefix("0O")) {
        i64::from_str_radix(oct, 8).ok()?
    } else if let Some(bin) = body.strip_prefix("0b").or_else(|| body.strip_prefix("0B")) {
        i64::from_str_radix(bin, 2).ok()?
    } else if body.len() > 1 && body.starts_with('0') {
        return None; // Python rejects leading zeros without a prefix
    } else {
        body.parse::<i64>().ok()?
    };
    Some(if negative { -value } else { value })
}

// --- CLI --------------------------------------------------------------------

const PROG: &str = "questyle-ctl";

const TOP_USAGE: &str = "usage: questyle-ctl [-h] {info,watch,raw,feature} ...";

const TOP_HELP: &str = "\
usage: questyle-ctl [-h] {info,watch,raw,feature} ...

questyle-ctl - inspect & talk to the Questyle QCC Dongle Pro2 (USB 0a12:4007).

positional arguments:
  {info,watch,raw,feature}
    info                device/ALSA/PipeWire state (safe)
    watch               dump vendor HID input reports
    raw                 write a raw output report (report id 1)
    feature             GET_REPORT on the vendor channel

options:
  -h, --help            show this help message and exit
";

const INFO_HELP: &str = "\
usage: questyle-ctl info [-h]

options:
  -h, --help  show this help message and exit
";

const WATCH_USAGE: &str = "usage: questyle-ctl watch [-h] [-t TIME] [--log LOG]";

const WATCH_HELP: &str = "\
usage: questyle-ctl watch [-h] [-t TIME] [--log LOG]

options:
  -h, --help       show this help message and exit
  -t, --time TIME
  --log LOG        append reports to this file
";

const RAW_USAGE: &str = "usage: questyle-ctl raw [-h] hex";

const RAW_HELP: &str = "\
usage: questyle-ctl raw [-h] hex

positional arguments:
  hex         hex bytes, e.g. '00 01 02 ...' (report id prepended if needed)

options:
  -h, --help  show this help message and exit
";

const FEATURE_USAGE: &str = "usage: questyle-ctl feature [-h] [--node NODE] rid [size]";

const FEATURE_HELP: &str = "\
usage: questyle-ctl feature [-h] [--node NODE] rid [size]

positional arguments:
  rid
  size

options:
  -h, --help   show this help message and exit
  --node NODE  override hidraw node
";

enum Cmd {
    Info,
    Watch {
        time: f64,
        log: Option<String>,
    },
    Raw {
        hex: String,
    },
    Feature {
        rid: i64,
        size: usize,
        node: Option<String>,
    },
}

fn error(usage: &str, prog: &str, message: &str) -> Result<Option<Cmd>, ()> {
    eprintln!("{usage}");
    eprintln!("{prog}: error: {message}");
    Err(())
}

fn is_help(arg: &str) -> bool {
    arg == "-h" || arg == "--help"
}

fn unrecognized(extras: &[String]) -> Result<Option<Cmd>, ()> {
    error(
        TOP_USAGE,
        PROG,
        &format!("unrecognized arguments: {}", extras.join(" ")),
    )
}

fn parse_args(args: &[String]) -> Result<Option<Cmd>, ()> {
    let Some(first) = args.first() else {
        return error(TOP_USAGE, PROG, "the following arguments are required: cmd");
    };
    if is_help(first) {
        print!("{TOP_HELP}");
        return Ok(None);
    }
    let rest = &args[1..];
    match first.as_str() {
        "info" => {
            if rest.iter().any(|a| is_help(a)) {
                print!("{INFO_HELP}");
                return Ok(None);
            }
            if !rest.is_empty() {
                return unrecognized(rest);
            }
            Ok(Some(Cmd::Info))
        }
        "watch" => parse_watch(rest),
        "raw" => parse_raw(rest),
        "feature" => parse_feature(rest),
        other => error(
            TOP_USAGE,
            PROG,
            &format!(
                "argument cmd: invalid choice: '{other}' (choose from 'info', 'watch', 'raw', 'feature')"
            ),
        ),
    }
}

fn take_value<'a>(
    rest: &'a [String],
    index: &mut usize,
    usage: &str,
    prog: &str,
    option: &str,
) -> Result<&'a str, ()> {
    *index += 1;
    match rest.get(*index) {
        Some(value) => Ok(value.as_str()),
        None => {
            eprintln!("{usage}");
            eprintln!("{prog}: error: argument {option}: expected one argument");
            Err(())
        }
    }
}

fn parse_watch(rest: &[String]) -> Result<Option<Cmd>, ()> {
    const PROG: &str = "questyle-ctl watch";
    let mut time = 30.0f64;
    let mut log: Option<String> = None;
    let mut i = 0;
    while i < rest.len() {
        let arg = rest[i].as_str();
        if is_help(arg) {
            print!("{WATCH_HELP}");
            return Ok(None);
        }
        if arg == "-t" || arg == "--time" {
            let value = take_value(rest, &mut i, WATCH_USAGE, PROG, "-t/--time")?;
            time = match parse_py_float(value) {
                Some(v) => v,
                None => {
                    return error(
                        WATCH_USAGE,
                        PROG,
                        &format!("argument -t/--time: invalid float value: '{value}'"),
                    )
                }
            };
        } else if let Some(value) = arg.strip_prefix("--time=") {
            time = match parse_py_float(value) {
                Some(v) => v,
                None => {
                    return error(
                        WATCH_USAGE,
                        PROG,
                        &format!("argument -t/--time: invalid float value: '{value}'"),
                    )
                }
            };
        } else if arg == "--log" {
            let value = take_value(rest, &mut i, WATCH_USAGE, PROG, "--log")?;
            log = Some(value.to_string());
        } else if let Some(value) = arg.strip_prefix("--log=") {
            log = Some(value.to_string());
        } else {
            return unrecognized(&rest[i..]);
        }
        i += 1;
    }
    Ok(Some(Cmd::Watch { time, log }))
}

fn parse_raw(rest: &[String]) -> Result<Option<Cmd>, ()> {
    const PROG: &str = "questyle-ctl raw";
    if rest.iter().any(|a| is_help(a)) {
        print!("{RAW_HELP}");
        return Ok(None);
    }
    let positionals: Vec<&String> = rest.iter().filter(|a| !a.starts_with('-')).collect();
    match positionals.as_slice() {
        [] => error(RAW_USAGE, PROG, "the following arguments are required: hex"),
        [hex] if positionals.len() == 1 && rest.len() == 1 => Ok(Some(Cmd::Raw {
            hex: hex.to_string(),
        })),
        _ => unrecognized(&rest[1..]),
    }
}

fn parse_feature(rest: &[String]) -> Result<Option<Cmd>, ()> {
    const PROG: &str = "questyle-ctl feature";
    let mut rid: Option<i64> = None;
    let mut size: Option<usize> = None;
    let mut node: Option<String> = None;
    let mut i = 0;
    while i < rest.len() {
        let arg = rest[i].as_str();
        if is_help(arg) {
            print!("{FEATURE_HELP}");
            return Ok(None);
        }
        if arg == "--node" {
            let value = take_value(rest, &mut i, FEATURE_USAGE, PROG, "--node")?;
            node = Some(value.to_string());
        } else if let Some(value) = arg.strip_prefix("--node=") {
            node = Some(value.to_string());
        } else if arg.starts_with('-') {
            return unrecognized(&rest[i..]);
        } else if rid.is_none() {
            rid = match parse_int_base0(arg) {
                Some(v) => Some(v),
                None => {
                    return error(
                        FEATURE_USAGE,
                        PROG,
                        &format!("argument rid: invalid <lambda> value: '{arg}'"),
                    )
                }
            };
        } else if size.is_none() {
            size = match arg.parse::<usize>() {
                Ok(v) => Some(v),
                Err(_) => {
                    return error(
                        FEATURE_USAGE,
                        PROG,
                        &format!("argument size: invalid int value: '{arg}'"),
                    )
                }
            };
        } else {
            return unrecognized(&rest[i..]);
        }
        i += 1;
    }
    let Some(rid) = rid else {
        return error(
            FEATURE_USAGE,
            PROG,
            "the following arguments are required: rid",
        );
    };
    Ok(Some(Cmd::Feature {
        rid,
        size: size.unwrap_or(62),
        node,
    }))
}

fn run(cmd: Cmd) -> i32 {
    match cmd {
        Cmd::Info => cmd_info(),
        Cmd::Watch { time, log } => cmd_watch(time, log.as_deref()),
        Cmd::Raw { hex } => cmd_raw(&hex),
        Cmd::Feature { rid, size, node } => cmd_feature(rid, size, node.as_deref()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uevent_matching_uses_the_full_hid_id() {
        let uevent = "DRIVER=hid-generic\nHID_ID=0003:00000A12:00004007\nHID_NAME=QCC Dongle\n";
        assert!(uevent.contains(HID_ID));
        let other = "HID_ID=0003:00001234:00005678\n";
        assert!(!other.contains(HID_ID));
    }

    #[test]
    fn alsa_cards_pick_the_dongle() {
        let cards = "\
 0 [HDSPe24048964  ]: HDSPe - RME AIO Pro_24048964
                      RME AIO Pro S/N 24048964 at 0xde900000 irq 183
 1 [QCC Dongle      ]: USB-Audio - QCC Dongle Pro2
                      QCC Dongle Pro2 at usb-0000:12:00.0-5.2
";
        assert_eq!(
            parse_alsa_cards(cards),
            Some((1, "QCC Dongle Pro2".to_string()))
        );
        assert_eq!(
            parse_alsa_cards(" 0 [Only  ]: USB-Audio - Webcam C920\n"),
            None
        );
    }

    #[test]
    fn alsa_stream_lines_match_the_python_output() {
        let stream = "\
QCC Dongle Pro2 at usb-0000:12:00.0-5.2, full speed : USB Audio

Playback:
  Status: Running
    Interface = 1
    Altset = 1
    Momentary freq = 48000 Hz (0x33.3333)
  Interface 1
    Altset 1
    Format: S16_LE
    Format: S24_3LE
";
        assert_eq!(
            parse_alsa_stream(stream),
            vec![
                "  playback    : Status: Running  [S16_LE S24_3LE]",
                "  Momentary freq = 48000 Hz (0x33.3333)",
            ]
        );
        assert_eq!(
            parse_alsa_stream("Playback:\n"),
            vec!["  playback    :   [idle]"]
        );
    }

    #[test]
    fn mixer_keeps_playback_and_capture_controls() {
        let out = "\
Simple mixer control 'PCM',0
  Capabilities: pvolume pswitch
  Playback channels: Front Left - Front Right
  Mono:
  Limits: Playback 0 - 64
";
        assert_eq!(
            parse_mixer(out),
            vec![
                "  PCM: Playback channels: Front Left - Front Right",
                "  PCM: Mono:",
                "  PCM: Limits: Playback 0 - 64",
            ]
        );
        assert_eq!(parse_mixer(""), vec!["  (no controls)"]);
    }

    #[test]
    fn pipewire_finds_the_dongle_and_its_links() {
        let status = "\
Audio
 ├─ Devices:
 │      46. QCC Dongle Pro2                  [alsa]
 └─ Clients:
";
        let links = "\
  12345 -> 67890  alsa_output.usb-Questyle_QCC_Dongle_Pro2-00.analog-stereo:playback_FL
  12345 -> 67890  mpv:output_FL
";
        assert_eq!(
            parse_pipewire(status, Some(links)),
            vec![
                "  │      46. QCC Dongle Pro2                  [alsa]",
                "  links:",
                "    12345 -> 67890  alsa_output.usb-Questyle_QCC_Dongle_Pro2-00.analog-stereo:playback_FL",
            ]
        );
        assert_eq!(
            parse_pipewire("Audio\n", None),
            vec!["  (device not in the current PipeWire graph)"]
        );
    }

    #[test]
    fn hex_accepts_spaces_and_commas() {
        assert_eq!(parse_hex("00 01 02"), Some(vec![0, 1, 2]));
        assert_eq!(parse_hex("00,01,02"), Some(vec![0, 1, 2]));
        assert_eq!(parse_hex("000102"), Some(vec![0, 1, 2]));
        assert_eq!(parse_hex("0"), None);
        assert_eq!(parse_hex("zz"), None);
        assert_eq!(parse_hex(""), Some(vec![]));
    }

    #[test]
    fn floats_print_like_python() {
        assert_eq!(py_float(30.0), "30.0");
        assert_eq!(py_float(7.5), "7.5");
        assert_eq!(py_float(0.25), "0.25");
    }

    #[test]
    fn ints_parse_with_base_prefixes() {
        assert_eq!(parse_int_base0("3"), Some(3));
        assert_eq!(parse_int_base0("0x03"), Some(3));
        assert_eq!(parse_int_base0("0b11"), Some(3));
        assert_eq!(parse_int_base0("0o3"), Some(3));
        assert_eq!(parse_int_base0("-0x10"), Some(-16));
        assert_eq!(parse_int_base0("010"), None);
        assert_eq!(parse_int_base0("zz"), None);
    }

    #[test]
    fn feature_request_is_the_python_ioctl() {
        // _ioctl_get_feature(62) = 0xC0000000 | (63 << 16) | 0x4807
        assert_eq!(feature_request(62), 0xC03F_4807);
        assert_eq!(feature_request(0), 0xC001_4807);
    }
}
