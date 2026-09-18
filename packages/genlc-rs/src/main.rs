// genlc — Genelec SAM monitor control via GLM USB adapter
// Rust rewrite of the Python genlc tool
//
// Protocol: HID USB (VID 0x1781 PID 0x0E39) → GNet frames:
//   [addr:1B] [cmd:1B] [data:0-N bytes] [CRC16/GSM:2B] [0x7E:1B]

mod protocol;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use std::str::FromStr;

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
    /// Set volume for all GLM devices
    SetVolume {
        /// Volume in dB (e.g., -40dB)
        #[arg(long = "volume", value_name = "VOLUME", allow_hyphen_values = true)]
        volume: String,
    },
    /// Mute all SAM monitors
    Mute,
    /// Unmute all SAM monitors
    Unmute,
    /// Toggle mute state
    SetMute,
    /// Discover devices on the GLM network
    Discover,
    /// Wake up all SAM monitors
    Wakeup,
    /// Shutdown all SAM monitors
    Shutdown,
    /// Poll device status
    Status {
        #[arg(long = "addr", default_value = "0xFF")]
        addr: String,
    },
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

/// Where genlc and the quickshell Genelec widget exchange the volume target.
///
/// Per-session state, so it belongs in XDG_RUNTIME_DIR (0700, wiped on logout)
/// rather than the fixed `/tmp/genlc-volume` it used to be: a world-writable
/// path with a predictable name is a symlink-attack surface and a collision
/// between users, and a value left over from yesterday's session would be read
/// as today's target. The shell scripts (glm-vol, genlc-media, glm-sync,
/// glm-adapter) resolve the same path with `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`.
fn state_file() -> Option<std::path::PathBuf> {
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())?;
    Some(std::path::Path::new(&runtime).join("genlc-volume"))
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let transport = protocol::HidTransport::open()?;
    let mut group = protocol::SamGroup::new(transport);

    match cli.command {
        Commands::SetVolume { volume } => {
            let db = parse_volume(&volume)?;
            eprintln!("Setting volume to {db:.2} dB");
            group.set_volume(db)?;
            // No XDG_RUNTIME_DIR (cron, a bare container, a shell without the
            // session environment) means there is no per-session state file to
            // sync through: the widget is not running either in that case, so
            // skipping the write is the honest outcome, not an error.
            if let Some(path) = state_file() {
                let _ = std::fs::write(path, format!("{:.1}", db));
            }
        }
        Commands::Discover => group.discover()?,
        Commands::Wakeup => group.wakeup()?,
        Commands::Shutdown => group.shutdown()?,
        Commands::Status { addr } => group.poll(parse_addr(&addr)?)?,
        Commands::Mute => group.mute()?,
        Commands::Unmute => group.unmute()?,
        Commands::SetMute => group.toggle_mute()?,
    }
    Ok(())
}
