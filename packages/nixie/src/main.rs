//! The nixie workbench: check the lamp's geometry, and (next) draw it on the
//! GPU without a compositor in the way.
//!
//! `validate` reads the numbers out of the fragment shader and checks that the
//! lamp is one object on one axis — the arithmetic a fitter would do. `render`
//! and `sweep` are the off-screen Vulkan path: no Quickshell, no monitor, no
//! Python, so a configuration can be drawn and measured in milliseconds.

mod drawing;
mod geometry;
mod measure;
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
    /// Draw every numeral and write a contact sheet plus the measurements.
    Sweep {
        /// Where the sheet goes.
        #[arg(default_value = "/tmp/nixie-sweep.png")]
        out: PathBuf,
        /// How many pixels of device scale each lamp is drawn at.
        #[arg(long, default_value_t = 2)]
        scale: u32,
        /// Fail when a measurement is outside the plan's limits.
        #[arg(long)]
        check: bool,
    },
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
        /// The discharge's strength, as the workbench's glow handle: 0 draws
        /// the lamp dark, which is how the glass alone is measured.
        #[arg(long, default_value_t = 1.0)]
        glow: f32,
        /// How bright the room behind the tube is drawn: the login screen shows
        /// it through the card's dimmer (0.45), a photo of a lamp on a desk shows
        /// it as it is (1.0).
        #[arg(long, default_value_t = 1.0)]
        room: f32,
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
    glow: f32,
    room: f32,
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

    let wallpaper = wallpaper(width, height, room)?;
    let mut uniforms =
        uniforms::Uniforms::from_drawing(drawing, mm, [width as f32, height as f32], digit);
    uniforms.glow = glow;
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

/// Every numeral, drawn on the same GPU pass, measured as it comes out, and
/// laid out as one sheet: any configuration of the lamp can be looked at and
/// judged in one run.
fn sweep(
    src: &str,
    drawing: &drawing::Drawing,
    out: &std::path::Path,
    scale: u32,
    check: bool,
) -> Result<()> {
    let mm = 12.0 * scale as f32;
    let pad = 16.0 * scale as f32;
    let width = (drawing.box_w as f32 * mm + 2.0 * pad).round() as u32;
    let height = (drawing.box_h as f32 * mm + 2.0 * pad).round() as u32;

    let compute = shader::to_compute(src)?;
    let spv = std::path::Path::new("/tmp/nixie-glsl/nixie.comp.spv");
    shader::compile(&compute, spv)?;
    let wall = wallpaper(width, height, 1.0)?;

    let mut sheet = image::RgbaImage::new(width * 10, height);
    let limits = measure::Limits::default();
    let mut failures = 0usize;
    println!("digit  wire white/hot   halo half   glass light   mesh contrast   ink top",);
    for digit in 0..10i32 {
        let uniforms =
            uniforms::Uniforms::from_drawing(drawing, mm, [width as f32, height as f32], digit);
        let frame = vulkan::render(spv, &uniforms, &wall, width, height)?;
        let measured = measure::measure(
            &frame.rgba,
            frame.width,
            (
                pad as u32,
                pad as u32,
                width - pad as u32,
                height - pad as u32,
            ),
        );
        println!(
            "  {}    {:>4} / {:<4}   {:>4} px    {:>6.1}%        {:>6.1}%      {:.0}%",
            digit,
            measured.wire_white_px,
            measured.wire_hot_px,
            measured.halo_half_px,
            measured.glass_own_light * 100.0,
            measured.cage_contrast * 100.0,
            measured.ink_top_share * 100.0
        );
        if check {
            for (name, ok, detail) in measured.checks(&limits) {
                if !ok {
                    println!("       FAIL {name}: {detail}");
                    failures += 1;
                }
            }
        }
        let tile = image::RgbaImage::from_raw(frame.width, frame.height, frame.rgba)
            .ok_or_else(|| anyhow!("the readback is not an image"))?;
        image::imageops::replace(&mut sheet, &tile, (digit as i64) * width as i64, 0);
    }
    // The glass itself: measured on the lamp with nothing lit, which is where
    // the plan's A3 measures it too — the discharge drowns everything else.
    let dark = uniforms::Uniforms::from_drawing(drawing, mm, [width as f32, height as f32], -1);
    let frame = vulkan::render(spv, &dark, &wall, width, height)?;
    let glass = measure::measure(
        &frame.rgba,
        frame.width,
        (
            pad as u32,
            pad as u32,
            width - pad as u32,
            height - pad as u32,
        ),
    );
    // Against a lit wire, not against this frame's own peak: on an unlit lamp
    // the peak is the glass itself, and dividing by it makes the glass look
    // worse the cleaner it gets. The wire's peak is 255 by construction.
    let own = glass.glass_own_light * glass.peak as f32 / 255.0;
    println!(
        "unlit lamp: glass adds {:.1}% of a lit wire (limit 8%), mesh contrast {:.1}%",
        own * 100.0,
        glass.cage_contrast * 100.0
    );
    if check && glass.cage_contrast < limits.cage_contrast {
        println!(
            "       FAIL the mesh is there: mesh contrast {:.1}%",
            glass.cage_contrast * 100.0
        );
        failures += 1;
    }
    if check && own > limits.glass_own_light {
        println!(
            "       FAIL the glass adds little of its own: {:.1}%",
            own * 100.0
        );
        failures += 1;
    }

    sheet.save(out)?;
    println!("{}: {}x{}", out.display(), sheet.width(), sheet.height());
    if failures > 0 {
        std::process::exit(1);
    }
    Ok(())
}

/// What stands behind the tube. The login screen hands the tube the wallpaper
/// with the card's dimmer on it; the workbench uses the same file when it is
/// there, and a plain gradient when it is not.
fn wallpaper(width: u32, height: u32, room: f32) -> Result<image::RgbaImage> {
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
            return Ok(gradient(width, height, room));
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
                    p[c] = (p[c] as f32 * room).min(255.0) as u8;
                }
                out.put_pixel(x, y, p);
            }
        }
        return Ok(out);
    }
    Ok(gradient(width, height, room))
}

/// The plain backdrop: a soft vertical wash, enough for the glass to have
/// something to bend when the wallpaper is not available.
fn gradient(width: u32, height: u32, room: f32) -> image::RgbaImage {
    let mut out = image::RgbaImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let u = x as f32 / width as f32;
            let v = y as f32 / height as f32;
            let grey = ((30.0 + 40.0 * (1.0 - v) + 12.0 * u) * room) as u8;
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
        Command::Render {
            out,
            digit,
            scale,
            glow,
            room,
        } => render(&src, &drawing, &out, digit, scale, glow, room)?,
        Command::Sweep { out, scale, check } => sweep(&src, &drawing, &out, scale, check)?,
    }
    Ok(())
}
