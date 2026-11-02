// genlc — Genelec SAM monitor control via GLM USB adapter
// Rust rewrite of the Python genlc tool
//
// Protocol: HID USB (VID 0x1781 PID 0x0E39) → GNet frames:
//   [addr:1B] [cmd:1B] [data:0-N bytes] [CRC16/GSM:2B] [0x7E:1B]

use genlc::plan::{parse_plan, plan_frames};
use genlc::protocol;
use genlc::{client, daemon};

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;

#[derive(Parser)]
#[command(name = "genlc", version, about = "Genelec SAM loudspeaker control")]
struct Cli {
    #[arg(short = 'm', long, value_delimiter = ',')]
    monitors: Vec<String>,

    #[arg(long, default_value = "false")]
    debug: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the adapter daemon: leases, mute rounds and the status socket
    Daemon {
        /// Control socket (default: $XDG_RUNTIME_DIR/genlc.sock)
        socket: Option<std::path::PathBuf>,
    },
    /// Print the running daemon's state; exits 1 when no daemon answers
    Status {
        /// Print the raw JSON reply instead of the summary
        #[arg(long)]
        json: bool,
    },
    /// Set or step the volume; writes the state file and routes through the daemon
    /// when it is running, otherwise straight to the adapter
    Volume {
        /// Absolute level, e.g. -40, -40dB or 40%
        #[arg(value_name = "DB", allow_hyphen_values = true)]
        db: Option<String>,
        /// Step relative to the current level, in dB (clamped to -95..-20)
        #[arg(long = "by", value_name = "DB", allow_hyphen_values = true)]
        by: Option<f64>,
        /// Print the state file's value and exit
        #[arg(long)]
        show: bool,
        /// Print each new state-file value as it changes
        #[arg(long)]
        watch: bool,
        /// Poll interval for --watch, in milliseconds
        #[arg(long = "interval-ms", default_value_t = 150)]
        interval_ms: u64,
    },
    /// Mute (`on`), unmute (`off`) or flip (`toggle`) every monitor
    Mute {
        #[arg(value_name = "on|off|toggle", default_value = "on")]
        state: MuteState,
    },
    /// Unmute every monitor (same as `mute off`)
    Unmute,
    /// Probe the bus once and print the hardware id of a monitor that holds no
    /// lease ("every monitor is leased" when none answers)
    Probe,
    /// Apply a plan file: by default print the frames, with --commit send them
    Apply {
        /// The plan file (see the module docs for the line format)
        plan: std::path::PathBuf,
        /// Send the frames instead of printing them. Requires every session in the
        /// plan to be leased, which --take does first
        #[arg(long)]
        commit: bool,
        /// Lease unleased monitors before applying
        #[arg(long)]
        take: bool,
        /// Apply the single plan entry to the first monitor this run leased, instead of
        /// matching the session written in the file (session ids depend on lease order)
        #[arg(long)]
        first: bool,
    },
    /// Probe for monitors without a lease (report only), or lease them with --take;
    /// --now asks a running daemon for a probe cycle instead
    Lease {
        /// Send the lease frames. Without it the command only reports what the probe saw
        #[arg(long)]
        take: bool,
        /// Ask the running daemon to run its probe cycle now (no adapter access here)
        #[arg(long)]
        now: bool,
    },
    /// Discover devices on the GLM network
    Discover,
    /// Wake up all SAM monitors
    Wakeup,
    /// Shutdown all SAM monitors
    Shutdown,
    /// Decode GNet frames from a USB capture (stdin, one HID report per line) —
    /// works with `tshark -r cap.pcap -T fields -e usb.capdata`, no adapter needed
    Decode {
        /// Print only the summary: opcode histogram and, when the input carries
        /// `frame.time_epoch`, the intervals between frames (GLM's ~0.57 s cycle,
        /// the ~107 ms status-poll pairs).
        #[arg(long)]
        stats: bool,
        /// Split the capture into bursts (frames closer together than `--gap`) and
        /// print each burst's opcode sequence. A group-preset switch is exactly one
        /// such burst — the block a writer has to reproduce.
        #[arg(long)]
        sequences: bool,
        /// Burst separator in seconds. GLM's longest silence while running is 0.22 s
        /// and its idle cycle is ~0.56 s, so 0.25 s cuts between them.
        #[arg(long, default_value = "0.25", value_name = "SECONDS")]
        gap: f64,
        /// How many run-length tokens to print per burst before truncating. GLM's
        /// idle cycle repeats forever, so an untruncated burst is unreadable.
        #[arg(long, default_value = "40", value_name = "N")]
        max_tokens: usize,
    },
    /// Probe the adapter's own device status (was `status --addr`)
    Poll {
        #[arg(long = "addr", default_value = "0xFF")]
        addr: String,
    },
    /// Print diagnostics: hidraw devices, udev rules, adapter and discovery
    Diagnose,
}

#[derive(Clone, Copy, clap::ValueEnum)]
enum MuteState {
    On,
    Off,
    /// Flip the state the daemon last reported (`genlc mute toggle`)
    Toggle,
}

fn parse_addr(s: &str) -> Result<u8> {
    u8::from_str_radix(s.trim_start_matches("0x"), 16).context("Invalid hex address")
}

fn parse_volume(s: &str) -> Result<f64> {
    let s = s.to_lowercase();
    let num = s.trim_end_matches("db").trim_end_matches('%');
    let v: f64 = num.parse().context("Invalid volume")?;
    if s.ends_with('%') {
        Ok(20.0 * (v / 100.0).log10())
    } else if v > -130.0 && v <= 0.0 {
        Ok(v)
    } else {
        anyhow::bail!("Volume must be -130..0 dB (or 0-100%), got: {v}")
    }
}

/// The volume target genlc shares with its readers: the pleamar Genelec plugin
/// watches this file, and `genlc volume --show` reads it back.
///
/// Per-session state, so it belongs in XDG_RUNTIME_DIR (0700, wiped on logout)
/// rather than the fixed `/tmp/genlc-volume` it used to be: a world-writable
/// path with a predictable name is a symlink-attack surface and a collision
/// between users, and a value left over from yesterday's session would be read
/// as today's target.
fn state_file() -> Option<std::path::PathBuf> {
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())?;
    Some(std::path::Path::new(&runtime).join("genlc-volume"))
}

/// Print each new value of the volume state file, one line per change.
///
/// Polling rather than inotify: the file is a few bytes, one open/read pair per
/// tick is free, and the plugin's previous `bash` loop already polled at 150 ms —
/// a watch library would be a new dependency for no measurable win. A missing
/// file is normal (a fresh session starts without one); an empty or unreadable
/// value is skipped, and the first read is always printed.
fn watch_volume_state(interval_ms: u64) -> Result<()> {
    let path = state_file().context("XDG_RUNTIME_DIR is not set: no volume state file to watch")?;
    let interval = std::time::Duration::from_millis(interval_ms.max(50));
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    let mut last = String::new();
    loop {
        if let Ok(text) = std::fs::read_to_string(&path) {
            let value = text.trim();
            if !value.is_empty() && value != last {
                writeln!(out, "{value}").context("writing the volume state line")?;
                out.flush().context("flushing the volume state line")?;
                last.clear();
                last.push_str(value);
            }
        }
        std::thread::sleep(interval);
    }
}

/// One HID report as bytes. Accepts what `tshark -T fields -e usb.capdata` prints
/// (`ff:1f:00:...`), the colon-free form (`usbhid.data`), and an optional `0x`
/// prefix — the capture side is not ours to standardise.
/// Split one input line into an optional timestamp and the HID report bytes.
/// `tshark -T fields -e frame.time_epoch -e usb.capdata` prefixes the epoch seconds
/// with a tab; without `-e frame.time_epoch` the line is just hex.
fn parse_line(line: &str) -> Result<(Option<f64>, Vec<u8>)> {
    let mut parts = line.split_whitespace();
    let first = parts.next().unwrap_or_default();
    match (parts.next(), first.parse::<f64>()) {
        (Some(rest), Ok(ts)) => Ok((Some(ts), parse_hex_report(rest)?)),
        _ => Ok((None, parse_hex_report(first)?)),
    }
}
fn parse_hex_report(line: &str) -> Result<Vec<u8>> {
    let cleaned: String = line
        .trim()
        .trim_start_matches("0x")
        .chars()
        .filter(|c| !matches!(c, ':' | ' ' | '-'))
        .collect();
    if cleaned.is_empty() || cleaned.len() % 2 != 0 {
        anyhow::bail!("expected an even number of hex digits, got {cleaned:?}");
    }
    (0..cleaned.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&cleaned[i..i + 2], 16)
                .with_context(|| format!("not hex: {:?}", &cleaned[i..i + 2]))
        })
        .collect()
}

/// Pull the GNet frame out of one HID report. Host reports carry their length in
/// the first byte (`0x80 + n`), adapter reports start with `0x3F` and end at the
/// `0x7E` flag; a leading zero is hidapi's report ID and is not bus data.
fn frame_from_report(report: &[u8]) -> Result<Vec<u8>> {
    let body = if report.first() == Some(&0) && report.len() > 1 {
        &report[1..]
    } else {
        report
    };
    match body.first() {
        Some(&header) if header & 0x80 != 0 => {
            let n = usize::from(header & 0x7F);
            if body.len() < n + 1 {
                anyhow::bail!(
                    "report claims {n} frame bytes but carries {} — expected a HID \
                     report: a 0x80+n header for host frames, 0x3F for adapter frames",
                    body.len() - 1
                );
            }
            Ok(body[1..=n].to_vec())
        }
        Some(&0x3F) => {
            let end = body
                .iter()
                .position(|&b| b == 0x7E)
                .with_context(|| "adapter report has no 0x7E flag")?;
            Ok(body[1..=end].to_vec())
        }
        Some(&other) => anyhow::bail!("unrecognised HID report header 0x{other:02X}"),
        None => anyhow::bail!("empty report"),
    }
}

/// Per-opcode tally plus the intervals a capture shows, so the first thing anyone
/// asks about a capture ("is GLM actually cycling?") is one command away.
#[derive(Default)]
struct CaptureStats {
    frames: usize,
    errors: usize,
    per_opcode: std::collections::BTreeMap<String, usize>,
    first_ts: Option<f64>,
    last_ts: Option<f64>,
    last_ts_per_opcode: std::collections::BTreeMap<u8, f64>,
    gaps_per_opcode: std::collections::BTreeMap<u8, Vec<f64>>,
}

impl CaptureStats {
    fn record(&mut self, opcode: u8, name: &str, ts: Option<f64>) {
        self.frames += 1;
        *self
            .per_opcode
            .entry(format!("{opcode:02X} {name}"))
            .or_insert(0) += 1;
        if let Some(ts) = ts {
            self.first_ts.get_or_insert(ts);
            self.last_ts = Some(ts);
            if let Some(prev) = self.last_ts_per_opcode.insert(opcode, ts) {
                self.gaps_per_opcode
                    .entry(opcode)
                    .or_default()
                    .push(ts - prev);
            }
        }
    }

    fn report(&self, out: &mut impl std::io::Write) -> std::io::Result<()> {
        writeln!(out, "-- {} frames, {} unreadable", self.frames, self.errors)?;
        if let (Some(first), Some(last)) = (self.first_ts, self.last_ts) {
            writeln!(out, "-- span {:.3} s", last - first)?;
        } else {
            return Ok(());
        }
        for (opcode, gaps) in &self.gaps_per_opcode {
            if gaps.len() < 2 {
                continue; // one interval says nothing about a cycle
            }
            let min = gaps.iter().cloned().fold(f64::INFINITY, f64::min);
            let max = gaps.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
            let mean = gaps.iter().sum::<f64>() / gaps.len() as f64;
            writeln!(
                out,
                "-- op {opcode:02X}: {} intervals, mean {:.3} s, min {:.3} s, max {:.3} s",
                gaps.len(),
                mean,
                min,
                max
            )?;
        }
        Ok(())
    }
}

/// Print the bursts a capture splits into, if the caller asked for them.
fn report_sequences(
    out: &mut impl std::io::Write,
    timeline: &[(f64, String)],
    sequences: bool,
    gap: f64,
    max_tokens: usize,
) -> Result<()> {
    if !sequences {
        return Ok(());
    }
    if timeline.is_empty() {
        writeln!(
            out,
            "-- sequences need timestamps: add `-e frame.time_epoch` to tshark"
        )?;
        return Ok(());
    }
    for burst in split_bursts(timeline, gap) {
        writeln!(out, "-- burst: {}", summarize_burst(&burst, max_tokens))?;
    }
    Ok(())
}

/// Cut a timestamped timeline into bursts. Frames further apart than `gap` start a
/// new burst, which is how GLM's idle cycles separate from a settings block.
fn split_bursts(timeline: &[(f64, String)], gap: f64) -> Vec<Vec<(f64, String)>> {
    let mut bursts: Vec<Vec<(f64, String)>> = Vec::new();
    let mut current: Vec<(f64, String)> = Vec::new();
    for frame in timeline {
        if let Some(last) = current.last() {
            if frame.0 - last.0 > gap {
                bursts.push(std::mem::take(&mut current));
            }
        }
        current.push(frame.clone());
    }
    if !current.is_empty() {
        bursts.push(current);
    }
    bursts
}

/// `op@addr` sequence with runs collapsed, plus the burst's length and duration.
fn summarize_burst(burst: &[(f64, String)], max_tokens: usize) -> String {
    let mut runs: Vec<(String, usize)> = Vec::new();
    for (_, token) in burst {
        match runs.last_mut() {
            Some((last, count)) if last == token => *count += 1,
            _ => runs.push((token.clone(), 1)),
        }
    }
    let rendered: Vec<String> = runs
        .iter()
        .map(|(token, count)| {
            if *count == 1 {
                token.clone()
            } else {
                format!("{token}x{count}")
            }
        })
        .collect();
    let shown = rendered.len().min(max_tokens);
    let mut body = rendered[..shown].join(",");
    if rendered.len() > shown {
        body.push_str(&format!(", … ({} more runs)", rendered.len() - shown));
    }
    let duration = burst
        .last()
        .map(|(ts, _)| ts - burst[0].0)
        .unwrap_or_default();
    format!(
        "{:.3} s, {} frames, {duration:.3} s: {body}",
        burst[0].0,
        burst.len()
    )
}

/// `genlc decode`: annotate a capture on stdin. Reads the adapter's replies and the
/// host's requests alike, verifies every CRC, and names each opcode it knows.
fn run_decode(stats_only: bool, sequences: bool, gap: f64, max_tokens: usize) -> Result<()> {
    use std::io::{BufRead, Write};
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    let mut stats = CaptureStats::default();
    let mut timeline: Vec<(f64, String)> = Vec::new();
    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let (ts, report) = match parse_line(&line) {
            Ok(parsed) => parsed,
            Err(e) => {
                stats.errors += 1;
                if !stats_only {
                    writeln!(out, "bad line: {e}")?;
                }
                continue;
            }
        };
        let frame = match frame_from_report(&report) {
            Ok(frame) => frame,
            Err(e) => {
                stats.errors += 1;
                if !stats_only {
                    writeln!(out, "skip: {e}")?;
                }
                continue;
            }
        };
        match protocol::decode_frame(&frame) {
            Ok(decoded) => {
                let name = protocol::opcode_name(decoded.address, decoded.opcode, &decoded.data);
                if !stats_only {
                    // The timestamp matters when reading a capture by hand — GLM's
                    // cycle and its status-poll pairs are timing facts, and correlating
                    // a reply with the request it answers needs the epoch.
                    if let Some(ts) = ts {
                        write!(out, "{ts:.6} ")?;
                    }
                    writeln!(
                        out,
                        "addr={:02X} op={:02X} {:<20} data={:02X?}",
                        decoded.address, decoded.opcode, name, decoded.data
                    )?;
                }
                stats.record(decoded.opcode, name, ts);
                if sequences {
                    if let Some(ts) = ts {
                        timeline.push((
                            ts,
                            format!("{:02X}@{:02X}", decoded.opcode, decoded.address),
                        ));
                    }
                }
            }
            Err(e) => {
                stats.errors += 1;
                if !stats_only {
                    writeln!(out, "skip: {e}")?;
                }
            }
        }
    }
    stats.report(&mut out)?;
    report_sequences(&mut out, &timeline, sequences, gap, max_tokens)?;
    Ok(())
}

/// The running daemon's state, or a clear error: `genlc status` is also the probe
/// the pleamar plugin uses to decide whether the daemon path is live.
fn status_command(json: bool) -> Result<()> {
    let socket = client::default_socket();
    let reply = client::round_trip(&socket, "status").map_err(|error| {
        anyhow::anyhow!("{error}\nstart the daemon with: systemctl --user start genlc")
    })?;
    if json {
        println!("{reply}");
        Ok(())
    } else {
        client::print_status(&reply, &socket)
    }
}

/// The state file's value, with the historical -40 fallback for a fresh session.
fn show_volume() -> Result<()> {
    let value = state_file()
        .and_then(|path| std::fs::read_to_string(path).ok())
        .map(|text| text.trim().to_string())
        .filter(|value| value.parse::<f64>().is_ok())
        .unwrap_or_else(|| "-40".into());
    println!("{value}");
    Ok(())
}

/// The level a relative step starts from: the daemon's last set, else the state
/// file, else -40. Clamped the way the media keys always were — a stale state must
/// never make the first notch louder than -20 dB.
fn current_level() -> f64 {
    let from_daemon = client::round_trip(&client::default_socket(), "status")
        .ok()
        .and_then(|json| client::scalar_field(&json, "volume_db").map(str::to_string))
        .and_then(|value| value.parse::<f64>().ok());
    let from_file = state_file()
        .and_then(|path| std::fs::read_to_string(path).ok())
        .and_then(|text| text.trim().parse::<f64>().ok());
    from_daemon
        .or(from_file)
        .unwrap_or(-40.0)
        .clamp(-95.0, -20.0)
}

fn resolve_volume_target(db: Option<&str>, by: Option<f64>) -> Result<f64> {
    match (db, by) {
        (Some(value), None) => parse_volume(value),
        (None, Some(step)) => Ok((current_level() + step).round().clamp(-95.0, -20.0)),
        _ => anyhow::bail!("volume needs a level (-40) or a step (--by -1)"),
    }
}

/// Set a level through the daemon when it is running, otherwise straight to the
/// adapter, and write the state file either way: it is the bar's and the plugin's
/// read-back channel, and it must agree with what the monitors were told.
fn set_volume_routed(db: f64) -> Result<()> {
    match client::round_trip(&client::default_socket(), &format!("volume {db}")) {
        Ok(reply) if !reply.starts_with("error") => {}
        Ok(reply) => anyhow::bail!("genlc daemon refused volume {db}: {reply}"),
        Err(_) => {
            let transport = protocol::HidTransport::open()?;
            protocol::SamGroup::new(transport).set_volume(db)?;
        }
    }
    if let Some(path) = state_file() {
        let _ = std::fs::write(path, format!("{db:.1}"));
    }
    println!("{db:.1} dB");
    Ok(())
}

/// `toggle` needs the daemon's own state: the adapter cannot be asked whether it is
/// muted, and keeping a second state file would recreate the split this CLI removed.
fn mute_command(state: MuteState) -> Result<()> {
    match state {
        MuteState::On => mute_routed(true),
        MuteState::Off => mute_routed(false),
        MuteState::Toggle => {
            let socket = client::default_socket();
            let reply = client::round_trip(&socket, "status").map_err(|error| {
                anyhow::anyhow!(
                    "mute toggle needs the daemon (its state is the only mute bit): {error}"
                )
            })?;
            let muted = matches!(client::scalar_field(&reply, "muted"), Some("true"));
            mute_routed(!muted)
        }
    }
}

fn mute_routed(on: bool) -> Result<()> {
    let word = if on { "on" } else { "off" };
    match client::round_trip(&client::default_socket(), &format!("mute {word}")) {
        Ok(reply) if !reply.starts_with("error") => {
            println!("{reply}");
            Ok(())
        }
        Ok(reply) => anyhow::bail!("genlc daemon refused mute {word}: {reply}"),
        Err(_) => {
            let transport = protocol::HidTransport::open()?;
            let group = protocol::SamGroup::new(transport);
            if on { group.mute() } else { group.unmute() }
        }
    }
}

/// Everything the old `genlc-diagnose` shell script printed, without the interpreter.
fn diagnose() -> Result<()> {
    println!("=== Genelec GLM adapter diagnostics ===");
    println!("genlc      {}", env!("CARGO_PKG_VERSION"));
    let mut hidraw: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(entries) = std::fs::read_dir("/dev") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            if name.to_string_lossy().starts_with("hidraw") {
                hidraw.push(entry.path());
            }
        }
    }
    if hidraw.is_empty() {
        println!("hidraw     none under /dev");
    } else {
        for path in &hidraw {
            let mode = std::fs::metadata(path)
                .map(|meta| format!("{:03o}", meta.permissions().mode() & 0o777))
                .unwrap_or_else(|_| "???".into());
            println!("hidraw     {} mode {mode}", path.display());
        }
    }
    let rules = [
        "/etc/udev/rules.d/99-genelec.rules",
        "/etc/udev/rules.d/99-genlc.rules",
    ];
    match rules
        .iter()
        .find(|path| std::path::Path::new(path).exists())
    {
        Some(path) => println!("udev       {path}"),
        None => println!("udev       no 99-genelec/99-genlc rule"),
    }
    match protocol::HidTransport::open() {
        Ok(transport) => {
            let group = protocol::SamGroup::new(transport);
            match group.discover() {
                Ok(()) => println!("discover   ok"),
                Err(error) => println!("discover   failed: {error}"),
            }
        }
        Err(error) => println!("adapter    not available: {error}"),
    }
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    // `decode` works on a capture file and must not need the adapter: opening the
    // HID device first used to make it fail on any machine without the hardware.
    if let Commands::Decode {
        stats,
        sequences,
        gap,
        max_tokens,
    } = cli.command
    {
        return run_decode(stats, sequences, gap, max_tokens);
    }
    // A dry-run plan is a pure computation and must not require the adapter — the same
    // reason `decode` runs before the transport opens.
    if let Commands::Apply {
        ref plan,
        commit: false,
        ..
    } = cli.command
    {
        let text = std::fs::read_to_string(plan)
            .with_context(|| format!("reading plan {}", plan.display()))?;
        let plans = parse_plan(&text)?;
        let mut planned = 0usize;
        for monitor_plan in &plans {
            for frame in plan_frames(monitor_plan) {
                let encoded = frame.encode();
                let hex: Vec<String> = encoded.iter().map(|b| format!("{b:02X}")).collect();
                println!("{:02X}: {}", monitor_plan.session, hex.join(" "));
                planned += 1;
            }
        }
        println!("{planned} frames planned (dry run; pass --commit --take to send)");
        return Ok(());
    }
    // Commands that must decide their transport before the adapter is opened: the
    // daemon may own it. `volume`/`mute` go through the socket when it answers and
    // fall back to the adapter only when it does not.
    match &cli.command {
        Commands::Daemon { socket } => return daemon::run(socket.clone()),
        Commands::Status { json } => return status_command(*json),
        Commands::Volume {
            db,
            by,
            show,
            watch,
            interval_ms,
        } => {
            if *show {
                return show_volume();
            }
            if *watch {
                return watch_volume_state(*interval_ms);
            }
            let target = resolve_volume_target(db.as_deref(), *by)?;
            return set_volume_routed(target);
        }
        Commands::Mute { state } => return mute_command(*state),
        Commands::Unmute => return mute_routed(false),
        Commands::Diagnose => return diagnose(),
        Commands::Lease { now: true, .. } => {
            let reply = client::round_trip(&client::default_socket(), "lease")
                .map_err(|error| anyhow::anyhow!("lease --now needs the daemon: {error}"))?;
            println!("{reply}");
            return Ok(());
        }
        _ => {}
    }
    let transport = protocol::HidTransport::open()?;
    let group = protocol::SamGroup::new(transport);

    match cli.command {
        Commands::Probe => match group.probe()? {
            Some(id) => println!(
                "monitor answered: hardware id {:02X} {:02X} {:02X}",
                id[0], id[1], id[2]
            ),
            None => println!("no unleased monitor answered (every monitor holds a lease)"),
        },
        Commands::Apply {
            plan,
            commit: _,
            take,
            first,
        } => {
            let text = std::fs::read_to_string(&plan)
                .with_context(|| format!("reading plan {}", plan.display()))?;
            let plans = parse_plan(&text)?;
            if !take {
                anyhow::bail!(
                    "--commit needs --take: this run must lease the monitors it writes to"
                );
            }
            let leased = group.take_leases()?;
            if leased.is_empty() {
                anyhow::bail!("no monitor could be leased; nothing to apply to");
            }
            let mut plans = plans;
            if first {
                if plans.len() != 1 {
                    anyhow::bail!("--first needs a plan with exactly one session entry");
                }
                plans[0].session = leased[0].session;
            }
            let mut sent = 0usize;
            for monitor_plan in &plans {
                // Refuse to write into a session this run did not lease: those frames
                // would land on whatever other monitor holds it.
                if !leased.iter().any(|l| l.session == monitor_plan.session) {
                    anyhow::bail!(
                        "session {:02X} is not leased by this run (leased: {:02X?})",
                        monitor_plan.session,
                        leased.iter().map(|l| l.session).collect::<Vec<_>>()
                    );
                }
                let mut acks = 0usize;
                for frame in plan_frames(monitor_plan) {
                    group.send(&frame)?;
                    // The bus allows one request in flight and a monitor answers within
                    // ~7 ms; blasting 27 frames back to back lost most of the acks in the
                    // 2026-11-02 hardware test, so pace them and collect what comes back.
                    std::thread::sleep(std::time::Duration::from_millis(12));
                    if let Some(reply) = group.try_receive() {
                        if reply.get(1) == Some(&0x09) {
                            acks += 1;
                        }
                    }
                }
                println!("  {acks}/{} acknowledged", plan_frames(monitor_plan).len());
                sent += plan_frames(monitor_plan).len();
                println!(
                    "applied {} frames to session {:02X}",
                    plan_frames(monitor_plan).len(),
                    monitor_plan.session
                );
            }
            println!("{sent} frames sent");
        }
        Commands::Lease { take, now: _ } => {
            if take {
                let leased = group.take_leases()?;
                if leased.is_empty() {
                    println!("no unleased monitor answered: every monitor holds a lease");
                }
                for lease in leased {
                    println!(
                        "leased {:02X} {:02X} {:02X} on session {:02X}",
                        lease.hardware_id[0],
                        lease.hardware_id[1],
                        lease.hardware_id[2],
                        lease.session
                    );
                }
            } else {
                match group.probe()? {
                    Some(id) => println!(
                        "an unleased monitor answered ({:02X} {:02X} {:02X}); rerun with --take to lease it",
                        id[0], id[1], id[2]
                    ),
                    None => println!("no unleased monitor answered: every monitor holds a lease"),
                }
            }
        }
        Commands::Discover => group.discover()?,
        Commands::Wakeup => group.wakeup()?,
        Commands::Shutdown => group.shutdown()?,
        Commands::Poll { addr } => group.poll(parse_addr(&addr)?)?,
        Commands::Decode { .. }
        | Commands::Daemon { .. }
        | Commands::Status { .. }
        | Commands::Volume { .. }
        | Commands::Mute { .. }
        | Commands::Unmute
        | Commands::Diagnose => unreachable!("handled before the adapter is opened"),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    const CID_VOLUME: u8 = 0x1F;

    #[test]
    fn splits_idle_cycles_from_a_settings_burst() {
        let timeline: Vec<(f64, String)> = [
            (0.000, "FE@FF"),
            (0.002, "7E@01"),
            (0.010, "1F@FF"),
            (0.400, "FE@FF"),
            (0.402, "7E@01"),
            (0.404, "10@02"),
            (0.410, "10@02"),
            (0.420, "40@02"),
        ]
        .iter()
        .map(|(ts, tok)| (*ts, tok.to_string()))
        .collect();
        let bursts = split_bursts(&timeline, 0.25);
        assert_eq!(bursts.len(), 2);
        assert_eq!(bursts[0].len(), 3);
        assert_eq!(bursts[1].len(), 5);
        assert_eq!(
            summarize_burst(&bursts[1], 40),
            "0.400 s, 5 frames, 0.020 s: FE@FF,7E@01,10@02x2,40@02"
        );
        // truncation keeps the header and says how much was cut
        assert!(summarize_burst(&bursts[1], 2).ends_with("… (2 more runs)"));
    }

    #[test]
    fn parses_a_plan_and_builds_glms_block_shape() {
        let plan = parse_plan(
            "# demo\nsession 02 288 0x7fffff 85 0,2,0,1\npeq 02 3 0.828,-0.775,0.717,1.884,-1.106\n",
        )
        .unwrap();
        assert_eq!(plan.len(), 1);
        assert_eq!(plan[0].delay_samples, 288);
        assert_eq!(plan[0].level_word, 0x7FFFFF);
        assert_eq!(plan[0].routing, Some([0, 2, 0, 1]));
        assert_eq!(plan[0].peq.len(), 1);
        // opener + delay + level + companion + 20 PEQ + crossover + 3D + routing
        assert_eq!(plan_frames(&plan[0]).len(), 27);
    }

    #[test]
    fn refuses_a_plan_that_targets_the_bus_instead_of_a_monitor() {
        assert!(parse_plan("session ff 0 0x7fffff 85\n").is_err());
        assert!(parse_plan("session 01 0 0x7fffff 85\n").is_err());
        assert!(parse_plan("peq 02 3 1,0,0,0,0\n").is_err()); // peq before its session
        assert!(parse_plan("session 02 0 0x7fffff 85\nsession 02 0 0x7fffff 85\n").is_err());
        assert!(parse_plan("session 02 0 0x7fffff 85 0,2,0\n").is_err()); // 3 routing bytes
        assert!(parse_plan("").is_err());
    }

    #[test]
    fn splits_an_optional_timestamp_and_counts_intervals() {
        let (ts, bytes) = parse_line("1759470000.500 88:ff:1f:00:31:07:2c:5a:7e").unwrap();
        assert_eq!(ts, Some(1759470000.5));
        // the report keeps its 0x88 header byte: 9 bytes, not 8
        assert_eq!(bytes.len(), 9);
        assert_eq!(bytes[0], 0x88);
        let (no_ts, _) = parse_line("88ff1f0031072c5a7e").unwrap();
        assert_eq!(no_ts, None);

        let mut stats = CaptureStats::default();
        stats.record(CID_VOLUME, "volume", Some(1.0));
        stats.record(CID_VOLUME, "volume", Some(1.57));
        stats.record(CID_VOLUME, "volume", Some(2.14));
        let gaps = &stats.gaps_per_opcode[&CID_VOLUME];
        assert_eq!(gaps.len(), 2);
        assert!((gaps[0] - 0.57).abs() < 1e-9);
    }

    #[test]
    fn parses_both_tshark_hex_flavours() {
        let colon = parse_hex_report("ff:1f:00:31:07:2c:5a:7e").unwrap();
        let plain = parse_hex_report("ff1f0031072c5a7e").unwrap();
        assert_eq!(colon, plain);
        assert_eq!(colon.len(), 8);
        assert!(parse_hex_report("ff1f0").is_err());
        assert!(parse_hex_report("zz").is_err());
    }

    #[test]
    fn pulls_a_host_frame_out_of_a_padded_report() {
        // 0x88 = 0x80 + 8 frame bytes, then the frame, then padding
        let mut report = vec![0x88];
        report.extend([0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x7E]);
        report.extend(std::iter::repeat_n(0u8, 55));
        let frame = frame_from_report(&report).unwrap();
        assert_eq!(frame, vec![0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x7E]);
        let decoded = protocol::decode_frame(&frame).unwrap();
        assert_eq!(
            protocol::opcode_name(decoded.address, decoded.opcode, &decoded.data),
            "volume"
        );
    }

    #[test]
    fn pulls_an_adapter_frame_out_of_a_padded_report() {
        // 0x3F header, the escaped no-answer frame, padding
        let mut report = vec![0x3F, 0x01, 0x7D, 0x5E, 0x53, 0x97, 0x7E];
        report.extend(std::iter::repeat_n(0u8, 57));
        let frame = frame_from_report(&report).unwrap();
        let decoded = protocol::decode_frame(&frame).unwrap();
        assert_eq!(decoded.address, 0x01);
        assert_eq!(decoded.opcode, 0x7E);
    }

    #[test]
    fn rejects_a_report_that_is_not_a_frame() {
        assert!(frame_from_report(&[]).is_err());
        assert!(frame_from_report(&[0x12, 0x34]).is_err());
        assert!(frame_from_report(&[0x3F, 0x01, 0x02]).is_err()); // no 0x7E flag
    }
}
