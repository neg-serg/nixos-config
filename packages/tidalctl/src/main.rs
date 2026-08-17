// tidalctl — TidalCycles session controller.
//
// Manages the SuperDirt audio engine (sclang + scsynth) with the correct
// PipeWire-jack LD_LIBRARY_PATH, opens the editor, records output, and
// monitors the PipeWire graph — one binary instead of shell recipes.

use std::env;
use std::fs;
use std::io::IsTerminal;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, Subcommand};

const OSC_PORT: u16 = 57120;
const SC_PORT: u16 = 57110;
const STARTUP: &str = ".config/SuperCollider/superdirt_startup.scd";
const SCLANG_CONF: &str = ".config/SuperCollider/sclang_conf.yaml";

/// Minimal ANSI styling — no extra dependencies. Colors are emitted only when
/// stdout is a terminal and NO_COLOR is unset; piped output stays plain.
struct Style {
    color: bool,
}

impl Style {
    fn new() -> Self {
        let color = std::io::stdout().is_terminal() && env::var_os("NO_COLOR").is_none();
        Style { color }
    }

    fn paint(&self, code: &str, text: &str) -> String {
        if self.color {
            format!("\x1b[{code}m{text}\x1b[0m")
        } else {
            text.to_string()
        }
    }

    fn bold(&self, text: &str) -> String {
        self.paint("1", text)
    }
    fn dim(&self, text: &str) -> String {
        self.paint("2", text)
    }
    fn green(&self, text: &str) -> String {
        self.paint("32", text)
    }
    fn green_bold(&self, text: &str) -> String {
        self.paint("1;32", text)
    }
    fn yellow_bold(&self, text: &str) -> String {
        self.paint("1;33", text)
    }
    fn cyan_bold(&self, text: &str) -> String {
        self.paint("1;36", text)
    }
}

#[derive(Parser)]
#[command(
    name = "tidalctl",
    about = "TidalCycles session controller — engine, editor, recording, monitoring"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the SuperDirt engine (sclang + scsynth) in the background
    Start,
    /// Stop the engine
    Stop,
    /// Show engine status: processes, OSC ports, audio links
    Status,
    /// Open the Tidal workspace in nvim (creates ~/src/art/music/tidal on first use)
    Code,
    /// Create a new .tidal file and open it
    New { name: String },
    /// Record SuperDirt output to ~/src/art/music/tidal/recordings/
    Record,
    /// Live PipeWire monitor (pw-top)
    Monitor,
    /// Open the ZestBay patchbay (via distrobox Arch container)
    Patch,
    /// Start the engine and open the demo jam scene in nvim
    Demo,
}

fn home() -> Result<PathBuf> {
    env::var("HOME").map(PathBuf::from).context("HOME not set")
}

fn state_dir() -> Result<PathBuf> {
    let dir = home()?.join(".local/state/tidalctl");
    fs::create_dir_all(&dir).context("create state dir")?;
    Ok(dir)
}

fn pid_file() -> Result<PathBuf> {
    Ok(state_dir()?.join("engine.pid"))
}

fn log_file() -> Result<PathBuf> {
    Ok(state_dir()?.join("engine.log"))
}

fn read_pid() -> Result<Option<i32>> {
    let path = pid_file()?;
    if !path.exists() {
        return Ok(None);
    }
    let text = fs::read_to_string(&path).context("read pid file")?;
    let pid: i32 = text.trim().parse().context("parse pid file")?;
    Ok(Some(pid))
}

fn proc_alive(pid: i32) -> bool {
    PathBuf::from(format!("/proc/{pid}")).exists()
}

/// True once the engine log contains the marker printed by
/// superdirt_startup.scd after SuperDirt finished loading samples.
/// The OSC port alone is not a readiness signal: sclang binds 57120
/// (its language port) immediately, long before SuperDirt is up.
fn log_contains(needle: &str) -> bool {
    fs::read_to_string(log_file().unwrap_or_default())
        .map(|t| t.contains(needle))
        .unwrap_or(false)
}

/// Check whether a UDP port is bound (0.0.0.0 or 127.0.0.1) by scanning
/// /proc/net/udp{,6} — no extra deps, works without binding ourselves.
fn port_listening(port: u16) -> bool {
    let needle = format!(":{port:04X}");
    for table in ["/proc/net/udp", "/proc/net/udp6"] {
        if let Ok(text) = fs::read_to_string(table) {
            if text.lines().skip(1).any(|l| {
                l.split_whitespace()
                    .nth(1)
                    .is_some_and(|a| a.contains(&needle))
            }) {
                return true;
            }
        }
    }
    false
}

fn find_scsynth_pids() -> Vec<i32> {
    let mut out = Vec::new();
    if let Ok(entries) = fs::read_dir("/proc") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let Ok(pid) = name.to_string_lossy().parse::<i32>() else {
                continue;
            };
            let Ok(comm) = fs::read_to_string(format!("/proc/{pid}/comm")) else {
                continue;
            };
            // comm is truncated to 15 chars by the kernel (".scsynth-wrappe");
            // also match the nix wrapper name.
            if comm.trim().contains("scsynth") {
                out.push(pid);
            }
        }
    }
    out
}

/// Process uptime in seconds: (now − boot_time) − starttime/CLK_TCK, derived
/// from /proc/<pid>/stat field 22 and /proc/stat btime. None if unparseable.
fn proc_uptime_secs(pid: i32) -> Option<u64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    // comm (field 2) may contain spaces and parens — split after the last ')'.
    let close = stat.rfind(')')?;
    let fields: Vec<&str> = stat[close + 1..].split_whitespace().collect();
    // After "pid (comm)" the tokens restart at field 3 (state); starttime is
    // field 22 → index 19.
    let start_ticks: u64 = fields.get(19)?.parse().ok()?;
    let btime: u64 = fs::read_to_string("/proc/stat")
        .ok()?
        .lines()
        .find_map(|l| l.strip_prefix("btime "))
        .and_then(|v| v.trim().parse().ok())?;
    let clk_tck = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    if clk_tck <= 0 {
        return None;
    }
    // Millisecond precision avoids the up-to-1s error of flooring start_ticks/clk_tck.
    let start_ms = start_ticks as u128 * 1000 / clk_tck as u128;
    let start = UNIX_EPOCH + Duration::from_secs(btime) + Duration::from_millis(start_ms as u64);
    SystemTime::now()
        .duration_since(start)
        .ok()
        .map(|d| d.as_secs())
}

/// Compact human uptime: "45s", "12m 34s", "2h 14m", "3d 5h".
fn fmt_uptime(secs: u64) -> String {
    let d = secs / 86400;
    let h = (secs % 86400) / 3600;
    let m = (secs % 3600) / 60;
    let s = secs % 60;
    if d > 0 {
        format!("{d}d {h}h")
    } else if h > 0 {
        format!("{h}h {m}m")
    } else if m > 0 {
        format!("{m}m {s}s")
    } else {
        format!("{s}s")
    }
}

/// Send SIGTERM, escalate to SIGKILL if the process does not exit in ~2s.
fn terminate(pid: i32) {
    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }
    for _ in 0..20 {
        if !proc_alive(pid) {
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }
    unsafe {
        libc::kill(pid, libc::SIGKILL);
    }
}

fn start() -> Result<()> {
    // Refuse to double-start: if the OSC port is already open, the engine is up.
    if port_listening(OSC_PORT) {
        println!("Engine is already running (OSC port {OSC_PORT} is open).");
        return Ok(());
    }

    let home = home()?;
    let startup = home.join(STARTUP);
    let conf = home.join(SCLANG_CONF);
    let log = log_file()?;

    if !startup.exists() {
        bail!(
            "startup script not found: {} — run nixos-rebuild so nix-maid writes it",
            startup.display()
        );
    }

    let log_handle = fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&log)
        .context("open engine log")?;

    println!("TidalCycles: booting engine...");
    // Run sclang under pw-jack: PipeWire's JACK emulation is a libjack
    // replacement (LD_LIBRARY_PATH), not a jackd daemon — without it scsynth
    // fails to boot ("Cannot connect to server socket").
    let mut child: Child = Command::new("pw-jack")
        .arg("sclang")
        .args(["-l", conf.to_str().unwrap(), startup.to_str().unwrap()])
        .env("LD_LIBRARY_PATH", "/run/current-system/sw/lib")
        .stdout(Stdio::from(log_handle.try_clone().context("clone log")?))
        .stderr(Stdio::from(log_handle))
        .spawn()
        .context("spawn sclang (is supercollider installed?)")?;

    fs::write(pid_file()?, child.id().to_string()).context("write pid file")?;

    // Wait for SuperDirt to finish booting. The OSC port opens as soon as
    // sclang starts, so wait for the "SUPERDIRT READY" marker in the log
    // (sample loading takes ~30s for the full Dirt-Samples bank).
    let deadline = Instant::now() + Duration::from_secs(120);
    while Instant::now() < deadline {
        if log_contains("SUPERDIRT READY") {
            println!("SuperDirt ready — listening on UDP {OSC_PORT}.");
            println!("Open the editor:  tidalctl code");
            return Ok(());
        }
        if let Some(status) = child.try_wait().context("wait sclang")? {
            bail!("sclang exited early with {status} — see {}", log.display());
        }
        thread::sleep(Duration::from_millis(500));
    }

    bail!(
        "engine did not become ready within 120s — see {}",
        log.display()
    );
}

fn stop() -> Result<()> {
    let mut stopped = false;

    if let Some(pid) = read_pid()? {
        if proc_alive(pid) {
            println!("Stopping engine (pid {pid})...");
            terminate(pid);
            stopped = true;
        }
        let _ = fs::remove_file(pid_file()?);
    }

    // scsynth is spawned by sclang; make sure it dies too.
    for pid in find_scsynth_pids() {
        println!("Stopping scsynth (pid {pid})...");
        terminate(pid);
        stopped = true;
    }

    if stopped {
        println!("TidalCycles: engine stopped.");
    } else {
        println!("Engine is not running.");
    }
    Ok(())
}

fn status() -> Result<()> {
    let style = Style::new();
    let engine_up = port_listening(OSC_PORT);
    let server_up = port_listening(SC_PORT);
    let superdirt_ready = engine_up && log_contains("SUPERDIRT READY");
    let pid = read_pid()?;
    let scsynth_pids = find_scsynth_pids();

    let header = "TidalCycles engine status";
    println!("{}", style.cyan_bold(header));
    println!("{}", style.dim(&"─".repeat(header.chars().count())));

    // One row per subsystem: aligned label, status dot, styled status text.
    let row = |label: &str, ok: bool, status: String| {
        println!(
            "  {label:<12}{} {status}",
            if ok {
                style.green("●")
            } else {
                style.dim("○")
            }
        );
    };

    // sclang: prefer the recorded pid; if the engine is up but no pid was
    // recorded (started outside tidalctl), say so instead of "not running".
    match pid {
        Some(p) if proc_alive(p) => row("sclang", true, style.green_bold(&p.to_string())),
        _ if engine_up => row("sclang", true, style.green_bold("running (pid unknown)")),
        _ => row("sclang", false, style.dim("not running")),
    }

    // Engine uptime, derived from the sclang process start time.
    let uptime = match pid {
        Some(p) if proc_alive(p) => proc_uptime_secs(p).map(fmt_uptime),
        _ => None,
    };
    let uptime_cell = if engine_up {
        match uptime {
            Some(up) => style.green_bold(&up),
            None => style.dim("unknown"),
        }
    } else {
        style.dim("—")
    };
    row("uptime", engine_up, uptime_cell);

    if scsynth_pids.is_empty() {
        row("scsynth", false, style.dim("not running"));
    } else {
        let pids = scsynth_pids
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(", ");
        row(
            "scsynth",
            true,
            format!(
                "{} {}",
                style.green_bold("running"),
                style.dim(&format!("(pid {pids})"))
            ),
        );
    }

    if superdirt_ready {
        row(
            "SuperDirt",
            true,
            style.green_bold(&format!("UDP {OSC_PORT} open")),
        );
    } else if engine_up {
        row(
            "SuperDirt",
            false,
            style.yellow_bold("loading samples… (UDP {OSC_PORT} open)"),
        );
    } else {
        row(
            "SuperDirt",
            false,
            style.dim(&format!("UDP {OSC_PORT} closed")),
        );
    }

    if server_up {
        row(
            "scsynth",
            true,
            style.green_bold(&format!("UDP {SC_PORT} open")),
        );
    } else {
        row(
            "scsynth",
            false,
            style.dim(&format!("UDP {SC_PORT} closed")),
        );
    }

    match Command::new("pw-link").arg("-l").output() {
        Ok(out) => {
            let text = String::from_utf8_lossy(&out.stdout);
            let linked = text
                .lines()
                .filter(|l| l.contains("SuperCollider:out"))
                .count();
            if linked > 0 {
                row(
                    "audio links",
                    true,
                    style.green_bold(&format!("{linked} SuperCollider out ports linked")),
                );
            } else {
                row(
                    "audio links",
                    false,
                    style.dim("no SuperCollider out ports linked"),
                );
            }
        }
        Err(_) => row("audio links", false, style.dim("(pw-link unavailable)")),
    }

    if superdirt_ready {
        println!(
            "\n{} Open the editor:  {}",
            style.green_bold("Ready."),
            style.bold("tidalctl code")
        );
    } else if engine_up {
        println!(
            "\n{} — samples still loading, try again shortly.",
            style.yellow_bold("Starting up…")
        );
    } else {
        println!(
            "\n{} Start it:  {}",
            style.yellow_bold("Engine is down."),
            style.bold("tidalctl start")
        );
    }
    Ok(())
}

fn ensure_workspace() -> Result<PathBuf> {
    let dir = home()?.join("src/art/music/tidal");
    fs::create_dir_all(dir.join("samples")).context("create ~/src/art/music/tidal/samples")?;
    fs::create_dir_all(dir.join("recordings")).context("create recordings dir")?;
    Ok(dir)
}

fn code() -> Result<()> {
    let dir = ensure_workspace()?;
    let status = Command::new("nvim")
        .arg(&dir)
        .status()
        .context("spawn nvim")?;
    if !status.success() {
        bail!("nvim exited with {status}");
    }
    Ok(())
}

/// Start the engine (if needed) and open the demo jam scene.
fn demo() -> Result<()> {
    if !port_listening(OSC_PORT) {
        start()?;
    } else {
        println!("Engine already running (OSC port {OSC_PORT} is open).");
    }
    let dir = ensure_workspace()?;
    let scene = dir.join("demo.tidal");
    if !scene.exists() {
        bail!(
            "demo scene not found: {} — run nixos-rebuild so nix-maid writes it",
            scene.display()
        );
    }
    println!("Opening demo jam: {}", scene.display());
    let status = Command::new("nvim")
        .arg(&scene)
        .status()
        .context("spawn nvim")?;
    if !status.success() {
        bail!("nvim exited with {status}");
    }
    Ok(())
}

fn new_file(name: String) -> Result<()> {
    let dir = ensure_workspace()?;
    let safe: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '-'
            }
        })
        .collect();
    let path = dir.join(format!("{safe}.tidal"));
    if !path.exists() {
        fs::write(
            &path,
            "-- TidalCycles — press <C-CR> to launch, <M-CR> to send a line\n\
             d1 $ sound \"bd sn\"\n",
        )
        .with_context(|| format!("create {}", path.display()))?;
        println!("Created {}", path.display());
    }
    let status = Command::new("nvim")
        .arg(&path)
        .status()
        .context("spawn nvim")?;
    if !status.success() {
        bail!("nvim exited with {status}");
    }
    Ok(())
}

fn record() -> Result<()> {
    let dir = ensure_workspace()?;
    let out = Command::new("pw-link")
        .arg("-o")
        .output()
        .context("run pw-link")?;
    let text = String::from_utf8_lossy(&out.stdout);
    let target = text
        .lines()
        .map(str::trim)
        .find(|l| l.starts_with("SuperCollider:out"))
        .ok_or_else(|| {
            anyhow!("no SuperCollider:out port found — is the engine running? (tidalctl start)")
        })?;

    let ts = timestamp();
    let out_path = dir.join("recordings").join(format!("tidal-{ts}.wav"));
    println!("Recording SuperDirt ({target}) → {}", out_path.display());
    println!("Ctrl+C to stop.");
    let status = Command::new("pw-record")
        .args(["--target", target])
        .arg(&out_path)
        .status()
        .context("spawn pw-record")?;
    if !status.success() {
        bail!("pw-record exited with {status}");
    }
    Ok(())
}

fn monitor() -> Result<()> {
    let status = Command::new("pw-top").status().context("spawn pw-top")?;
    if !status.success() {
        bail!("pw-top exited with {status}");
    }
    Ok(())
}

fn patch() -> Result<()> {
    // ZestBay GUI patchbay runs inside the Arch distrobox container.
    let status = Command::new("distrobox-enter")
        .args(["arch-zestbay", "--", "zestbay"])
        .status()
        .context("spawn distrobox-enter (is the arch-zestbay container created?)")?;
    if !status.success() {
        bail!("zestbay exited with {status}");
    }
    Ok(())
}

/// Compact UTC timestamp (YYYYMMDD-HHMMSS) for recording filenames.
fn timestamp() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let t: libc::time_t = secs;
    unsafe {
        let tm = libc::gmtime(&t);
        if tm.is_null() {
            return secs.to_string();
        }
        let tm = &*tm;
        format!(
            "{:04}{:02}{:02}-{:02}{:02}{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    }
}

fn main() -> Result<()> {
    // Rust ignores SIGPIPE by default, which makes `tidalctl status | head`
    // panic on EPIPE instead of exiting quietly — restore the default so
    // piped output behaves like any other CLI.
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    let cli = Cli::parse();
    match cli.command {
        Commands::Start => start(),
        Commands::Stop => stop(),
        Commands::Status => status(),
        Commands::Code => code(),
        Commands::New { name } => new_file(name),
        Commands::Record => record(),
        Commands::Monitor => monitor(),
        Commands::Patch => patch(),
        Commands::Demo => demo(),
    }
}
