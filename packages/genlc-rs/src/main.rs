// genlc — Genelec SAM monitor control via GLM USB adapter
// Rust rewrite of the Python genlc tool
//
// Protocol: HID USB (VID 0x1781 PID 0x0E39) → GNet frames:
//   [addr:1B] [cmd:1B] [data:0-N bytes] [CRC16/GSM:2B] [0x7E:1B]

mod protocol;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

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

fn main() -> Result<()> {
    let cli = Cli::parse();
    let transport = protocol::HidTransport::open()?;
    let mut group = protocol::SamGroup::new(transport);

    match cli.command {
        Commands::SetVolume { volume } => {
            let db = parse_volume(&volume)?;
            eprintln!("Setting volume to {db:.2} dB");
            group.set_volume(db)?;
            let _ = std::fs::write("/tmp/genlc-volume", format!("{:.1}", db));
        }
        Commands::Mute => group.mute()?,
        Commands::Unmute => group.unmute()?,
        Commands::SetMute => group.toggle_mute()?,
        Commands::Discover => group.discover()?,
        Commands::Wakeup => group.wakeup()?,
        Commands::Shutdown => group.shutdown()?,
    }
    Ok(())
}
