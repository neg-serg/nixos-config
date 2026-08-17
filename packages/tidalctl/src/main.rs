// tidalctl — TidalCycles session controller.
//
// Manages the SuperDirt audio engine (sclang + scsynth) with the correct
// PipeWire-jack LD_LIBRARY_PATH, opens the editor, records output, and
// monitors the PipeWire graph — one binary instead of shell recipes.

use std::env;
use std::fs;
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
    /// Open the Tidal workspace in nvim (creates ~/src/music/tidal on first use)
    Code,
    /// Create a new .tidal file and open it
    New { name: String },
    /// Record SuperDirt output to ~/src/music/tidal/recordings/
    Record,
    /// Live PipeWire monitor (pw-top)
    Monitor,
    /// Open the ZestBay patchbay (via distrobox Arch container)
    Patch,
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
    let mut child: Child = Command::new("sclang")
        .args(["-l", conf.to_str().unwrap(), startup.to_str().unwrap()])
        .env("LD_LIBRARY_PATH", "/run/current-system/sw/lib")
        .stdout(Stdio::from(log_handle.try_clone().context("clone log")?))
        .stderr(Stdio::from(log_handle))
        .spawn()
        .context("spawn sclang (is supercollider installed?)")?;

    fs::write(pid_file()?, child.id().to_string()).context("write pid file")?;

    // Wait for SuperDirt to open the OSC port (usually <2s).
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if port_listening(OSC_PORT) {
            println!("SuperDirt ready — listening on UDP {OSC_PORT}.");
            println!("Open the editor:  tidalctl code");
            return Ok(());
        }
        if let Some(status) = child.try_wait().context("wait sclang")? {
            bail!("sclang exited early with {status} — see {}", log.display());
        }
        thread::sleep(Duration::from_millis(200));
    }

    bail!(
        "engine did not open port {OSC_PORT} within 15s — see {}",
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
    let engine_up = port_listening(OSC_PORT);
    let server_up = port_listening(SC_PORT);
    let pid = read_pid()?;

    println!("TidalCycles engine status:");
    println!(
        "  sclang pid:      {}",
        match pid {
            Some(p) if proc_alive(p) => p.to_string(),
            _ => "not running".into(),
        }
    );
    println!(
        "  scsynth:         {}",
        if find_scsynth_pids().is_empty() {
            "not running"
        } else {
            "running"
        }
    );
    println!(
        "  OSC :{OSC_PORT} (SuperDirt): {}",
        if engine_up { "OPEN" } else { "closed" }
    );
    println!(
        "  OSC :{SC_PORT} (scsynth):    {}",
        if server_up { "OPEN" } else { "closed" }
    );

    match Command::new("pw-link").arg("-l").output() {
        Ok(out) => {
            let text = String::from_utf8_lossy(&out.stdout);
            let linked = text
                .lines()
                .filter(|l| l.contains("SuperCollider:out"))
                .count();
            println!("  audio links:     {linked} SuperCollider out ports linked");
        }
        Err(_) => println!("  audio links:     (pw-link unavailable)"),
    }

    if engine_up {
        println!("\nReady. Open the editor:  tidalctl code");
    } else {
        println!("\nEngine is down. Start it:  tidalctl start");
    }
    Ok(())
}

fn ensure_workspace() -> Result<PathBuf> {
    let dir = home()?.join("src/music/tidal");
    fs::create_dir_all(dir.join("samples")).context("create ~/src/music/tidal/samples")?;
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
    }
}
