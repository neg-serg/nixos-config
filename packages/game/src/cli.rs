//! CLI argument parsing via clap derive.

use clap::{Parser, Subcommand};

#[derive(Parser, Debug)]
#[command(name = "game", about = "Unified game launcher — CPU pinning, Gamescope presets, session launching")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Run a command with CPU pinning + optional gamemode (replaces game-run)
    Run {
        /// CPU set for pinning (e.g. "0-3,16-19", or "auto" for V-Cache auto-detect)
        #[arg(short = 'c', long = "cpus", default_value = "auto")]
        cpus: String,

        /// Disable gamemode
        #[arg(long = "no-gamemode")]
        no_gamemode: bool,

        /// Disable CPU pinning entirely
        #[arg(long = "no-pin")]
        no_pin: bool,

        /// Dry run: print command without executing
        #[arg(short = 'n', long = "dry-run")]
        dry_run: bool,

        /// Command to run (everything after --)
        #[arg(required = true, num_args = 1.., trailing_var_arg = true)]
        command: Vec<String>,
    },

    /// Run a command under gamescope with named presets (replaces gamescope-*)
    Scope {
        /// Named preset: quality, perf, hdr, targetfps, pinned, unity, skip
        #[arg(short = 'p', long = "preset")]
        preset: Option<String>,

        /// Override render scale (0.5-1.0)
        #[arg(long = "scale")]
        scale: Option<f64>,

        /// FSR sharpness (0-20)
        #[arg(long = "fsr-sharpness")]
        fsr_sharpness: Option<i32>,

        /// Enable HDR
        #[arg(long = "hdr")]
        hdr: bool,

        /// Disable adaptive sync / VRR
        #[arg(long = "no-vrr")]
        no_vrr: bool,

        /// Disable CPU pinning
        #[arg(long = "no-pin")]
        no_pin: bool,

        /// Dry run: print command without executing
        #[arg(short = 'n', long = "dry-run")]
        dry_run: bool,

        /// Command to run (everything after --)
        #[arg(required = true, num_args = 1.., trailing_var_arg = true)]
        command: Vec<String>,
    },

    /// Launch Steam Big Picture session in gamescope (replaces game-session)
    Session {
        /// Enable MangoHud overlay
        #[arg(long = "mangohud")]
        mangohud: bool,

        /// Disable HDR
        #[arg(long = "no-hdr")]
        no_hdr: bool,

        /// Disable CPU pinning
        #[arg(long = "no-pin")]
        no_pin: bool,

        /// Dry run: print command without executing
        #[arg(short = 'n', long = "dry-run")]
        dry_run: bool,
    },

    /// Run a desktop app inside gamescope (replaces gamescope-app)
    App {
        /// Resolution preset: 1080, 1440, 720, or WxH (e.g. 1600x900)
        #[arg(short = 'r', long = "resolution", default_value = "1080")]
        resolution: String,

        /// Upscale filter: nearest, fsr, nis, linear, pixel
        #[arg(short = 'f', long = "filter")]
        filter: Option<String>,

        /// Fullscreen mode
        #[arg(short = 'F', long = "fullscreen")]
        fullscreen: bool,

        /// Disable --expose-wayland
        #[arg(long = "no-wayland")]
        no_wayland: bool,

        /// FSR sharpness (0-20)
        #[arg(short = 'S', long = "sharpness", default_value = "3")]
        sharpness: i32,

        /// Disable CPU pinning
        #[arg(long = "no-pin")]
        no_pin: bool,

        /// Dry run: print command without executing
        #[arg(short = 'n', long = "dry-run")]
        dry_run: bool,

        /// Command to run (everything after --)
        #[arg(required = true, num_args = 1.., trailing_var_arg = true)]
        command: Vec<String>,
    },

    /// Show system info (CPU topology, monitor, gamemode)
    Info {
        /// JSON output
        #[arg(long = "json")]
        json: bool,
    },
}
