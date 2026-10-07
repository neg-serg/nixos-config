//! The nixie workbench: check the lamp's geometry, and (next) draw it on the
//! GPU without a compositor in the way.
//!
//! `validate` reads the numbers out of the fragment shader and checks that the
//! lamp is one object on one axis — the arithmetic a fitter would do. `render`
//! and `sweep` are the off-screen Vulkan path: no Quickshell, no monitor, no
//! Python, so a configuration can be drawn and measured in milliseconds.

mod drawing;
mod geometry;
mod shader;
mod uniforms;
mod vulkan;

use anyhow::{anyhow, Result};
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

/// One tube, drawn off-screen: the same shader the login screen uses, turned
/// into a compute pass (see shader.rs) so nothing of the compositor is needed.
fn render(
    src: &str,
    drawing: &drawing::Drawing,
    out: &std::path::Path,
    digit: i32,
    scale: u32,
) -> Result<()> {
    // The frame is the drawing's own box plus the tube's pads, at `scale` device
    // pixels per logical pixel.
    let mm = 12.0 * scale as f32; // the scale a 21 mm lamp is drawn at
    let pad = 16.0 * scale as f32;
    let width = (drawing.box_w as f32 * mm + 2.0 * pad).round() as u32;
    let height = (drawing.box_h as f32 * mm + 2.0 * pad).round() as u32;

    let compute = shader::to_compute(src)?;
    let spv = std::path::Path::new("/tmp/nixie-glsl/nixie.comp.spv");
    shader::compile(&compute, spv)?;

    let wallpaper = wallpaper(width, height)?;
    let uniforms =
        uniforms::Uniforms::from_drawing(drawing, mm, [width as f32, height as f32], digit);
    let frame = vulkan::render(spv, &uniforms, &wallpaper, width, height)?;

    let image = image::RgbaImage::from_raw(frame.width, frame.height, frame.rgba)
        .ok_or_else(|| anyhow::anyhow!("the readback is not an image"))?;
    image.save(out)?;
    println!(
        "{}: {}x{} device px",
        out.display(),
        frame.width,
        frame.height
    );
    Ok(())
}

/// What stands behind the tube. The login screen hands the tube the wallpaper
/// with the card's dimmer on it; the workbench uses the same file when it is
/// there, and a plain gradient when it is not.
fn wallpaper(width: u32, height: u32) -> Result<image::RgbaImage> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/root".into());
    let path = std::path::PathBuf::from(home).join(".cache/greeter-wallpaper");
    if path.exists() {
        // the wallpaper the greeter uses is a JPEG; when this build has no
        // decoder for it, the workbench still draws, over a plain gradient
        let Ok(decoded) = image::open(&path) else {
            eprintln!(
                "nixie: cannot decode {} — drawing over a gradient",
                path.display()
            );
            return Ok(gradient(width, height));
        };
        let src = decoded.to_rgba8();
        let mut out = image::RgbaImage::new(width, height);
        // centre-crop the wallpaper into the frame, as the login screen does
        let scale = (src.width() as f32 / width as f32).max(src.height() as f32 / height as f32);
        let (w, h) = (
            (width as f32 * scale) as u32,
            (height as f32 * scale) as u32,
        );
        let cropped = image::imageops::resize(&src, w, h, image::imageops::FilterType::Triangle);
        let (ox, oy) = ((w - width) / 2, (h - height) / 2);
        for y in 0..height {
            for x in 0..width {
                let mut p = *cropped.get_pixel(x + ox, y + oy);
                // the card's dimmer: the login screen never shows it raw
                for c in 0..3 {
                    p[c] = (p[c] as f32 * 0.45) as u8;
                }
                out.put_pixel(x, y, p);
            }
        }
        return Ok(out);
    }
    Ok(gradient(width, height))
}

/// The plain backdrop: a soft vertical wash, enough for the glass to have
/// something to bend when the wallpaper is not available.
fn gradient(width: u32, height: u32) -> image::RgbaImage {
    let mut out = image::RgbaImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let u = x as f32 / width as f32;
            let v = y as f32 / height as f32;
            let grey = (30.0 + 40.0 * (1.0 - v) + 12.0 * u) as u8;
            out.put_pixel(
                x,
                y,
                image::Rgba([grey, grey, (grey as f32 * 1.1) as u8, 255]),
            );
        }
    }
    out
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
        Command::Render { out, digit, scale } => render(&src, &drawing, &out, digit, scale)?,
    }
    Ok(())
}
