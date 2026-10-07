//! The nixie workbench: check the lamp's geometry, and (next) draw it on the
//! GPU without a compositor in the way.
//!
//! `validate` reads the numbers out of the fragment shader and checks that the
//! lamp is one object on one axis — the arithmetic a fitter would do. `render`
//! and `sweep` are the off-screen Vulkan path: no Quickshell, no monitor, no
//! Python, so a configuration can be drawn and measured in milliseconds.

mod drawing;
mod geometry;

use anyhow::Result;
use clap::{Parser, Subcommand};
use std::path::PathBuf;

/// Where the shader lives when nothing else is said.
const SHADER: &str = "/etc/nixos/files/quickshell/greeter/shaders/nixie.frag";

#[derive(Parser)]
#[command(name = "nixie", about = "the nixie tube's geometry and its picture")]
struct Cli {
    /// The fragment shader the lamp is drawn by.
    #[arg(long, global = true, default_value = SHADER)]
    shader: PathBuf,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Check the geometry: one axis, no gaps, no overlaps, real proportions.
    Validate,
    /// Draw the tube off-screen and write a PNG.
    Render {
        /// Where the picture goes.
        #[arg(default_value = "/tmp/nixie.png")]
        out: PathBuf,
        /// Which cathode burns, 0..9; -1 leaves the tube dark.
        #[arg(long, default_value_t = 6)]
        digit: i32,
        /// How many pixels of device scale the picture is drawn at.
        #[arg(long, default_value_t = 2)]
        scale: u32,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let src = std::fs::read_to_string(&cli.shader)?;
    let drawing = drawing::Drawing::read(&src)?;
    match cli.command {
        Command::Validate => {
            let report = geometry::check(&drawing);
            print!("{}", report.text());
            std::process::exit(if report.failed() == 0 { 0 } else { 1 });
        }
        Command::Render { out, digit, scale } => {
            println!(
                "render {} (digit {}, scale {}) — the Vulkan path is not written yet",
                out.display(),
                digit,
                scale
            );
        }
    }
    Ok(())
}
