//! The nixie workbench: check the lamp's geometry, and draw it on the GPU
//! without a compositor in the way.
//!
//! `validate` reads the numbers out of the fragment shader and checks that the
//! lamp is one object on one axis — the arithmetic a fitter would do. `render`
//! and `sweep` are the off-screen Vulkan path: no Quickshell, no monitor, no
//! Python, so a configuration can be drawn and measured in milliseconds. The
//! geometry the tool lays out is the geometry NixieClock.qml lays out: the
//! numeral's 18 mm, the theme's margins and the theme's two row gaps.
//!
//! `theme set` is the comment-preserving patch helper for
//! `files/quickshell/Theme/greeter.jsonc`: it replaces one value and leaves the
//! rest of the file — comments included — byte for byte alone.

mod drawing;
mod geometry;
mod measure;
mod shader;
mod uniforms;
mod vulkan;

use anyhow::{anyhow, bail, Context, Result};
use clap::{ArgAction, Parser, Subcommand};
use std::path::{Path, PathBuf};

/// Where the shader lives when neither `--shader` nor the environment says.
const SHADER_FALLBACK: &str = "/etc/nixos/files/quickshell/greeter/shaders/nixie.frag";
/// Where the theme lives when neither `--theme` nor the environment says.
const THEME_FALLBACK: &str = "/etc/nixos/files/quickshell/Theme/greeter.jsonc";
/// The plan's measurement limits are written at the login screen's own
/// density, which is what `--scale 2` draws (see `measure::Limits`).
const REFERENCE_SCALE: f32 = 2.0;

#[derive(Parser)]
#[command(
    name = "nixie",
    version,
    about = "the nixie tube's geometry and its picture"
)]
struct Cli {
    /// The fragment shader the lamp is drawn by. Default: $NIXIE_SHADER, else
    /// the repo's file found from the current directory, else /etc/nixos.
    #[arg(long, global = true, value_name = "PATH")]
    shader: Option<PathBuf>,

    /// The theme the tube's tokens are read from. Default: $NIXIE_THEME, else
    /// the repo's file found from the current directory, else /etc/nixos.
    #[arg(long, global = true, value_name = "PATH")]
    theme: Option<PathBuf>,

    /// The wallpaper the glass bends. Default: $NIXIE_WALLPAPER, else
    /// $PREVIEW_WALLPAPER, else $XDG_CACHE_HOME/greeter-wallpaper, else
    /// ~/.cache/greeter-wallpaper; a gradient when there is none.
    #[arg(long, global = true, value_name = "PATH")]
    wallpaper: Option<PathBuf>,

    /// The Vulkan device index to use (default: $NIXIE_VK_DEVICE, else the best
    /// compute device: discrete > integrated > virtual > CPU).
    #[arg(long, global = true, value_name = "N")]
    device: Option<u32>,

    /// Override a theme token, e.g. --set nixieGlow=1.4. Repeatable; the names
    /// are the theme's (nixieTint, nixieTempK, ...) and `greeter.` is optional.
    #[arg(long = "set", global = true, value_name = "TOKEN=VALUE", action = ArgAction::Append)]
    sets: Vec<String>,

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
        /// How many device pixels per logical pixel the lamp is drawn at.
        #[arg(long, default_value_t = 2, value_parser = clap::value_parser!(u32).range(1..=8))]
        scale: u32,
        /// Fail when a measurement is outside the plan's limits.
        #[arg(long)]
        check: bool,
        /// Print one JSON object on stdout instead of the human table.
        #[arg(long)]
        json: bool,
    },
    /// Draw the tube off-screen and write a PNG.
    Render {
        /// Where the picture goes.
        #[arg(default_value = "/tmp/nixie.png")]
        out: PathBuf,
        /// Which cathode burns, 0..9; -1 leaves the tube dark.
        #[arg(long, default_value_t = 6, value_parser = clap::value_parser!(i32).range(-1..=9))]
        digit: i32,
        /// How many device pixels per logical pixel the picture is drawn at.
        #[arg(long, default_value_t = 2, value_parser = clap::value_parser!(u32).range(1..=8))]
        scale: u32,
        /// The discharge's strength, as the workbench's glow handle: 0 draws
        /// the lamp dark, which is how the glass alone is measured.
        #[arg(long, default_value_t = 1.0, value_parser = parse_glow)]
        glow: f32,
        /// How bright the room behind the tube is drawn: the login screen shows
        /// it through the card's dimmer (0.45), a photo of a lamp on a desk
        /// shows it as it is (1.0).
        #[arg(long, default_value_t = 1.0, value_parser = parse_room)]
        room: f32,
        /// Draw four tubes in one pass the way the login clock does, with these
        /// four digits (e.g. --row 1750). The row uses the clock's own gaps
        /// (tubeGap 5.5%, pairGap 20% of the numeral), so one pass is how the
        /// seam between two tubes is measured on the real row.
        #[arg(long, value_name = "DDDD")]
        row: Option<String>,
        /// Draw the same frame twice and fail if the two pictures differ in even
        /// one byte: an off-screen pass has to be bit-for-bit reproducible, or
        /// every number `sweep --check` prints is noise.
        #[arg(long)]
        verify: bool,
        /// Print one JSON object on stdout instead of the human lines.
        #[arg(long)]
        json: bool,
    },
    /// Patch a token's value in a JSONC theme file, preserving every comment.
    Theme {
        #[command(subcommand)]
        action: ThemeAction,
    },
}

#[derive(Subcommand)]
enum ThemeAction {
    /// Replace one existing key's value and touch nothing else.
    Set {
        /// The JSONC file to patch.
        #[arg(long, value_name = "PATH")]
        file: PathBuf,
        /// The token key, e.g. nixieGlow (quotes optional).
        #[arg(long)]
        key: String,
        /// The new value; a quoted string may be given with or without quotes.
        #[arg(long)]
        value: String,
        /// Write the patched file here (atomic temp + rename). Without `--to`
        /// nothing is written and the change is printed.
        #[arg(long, value_name = "PATH")]
        to: Option<PathBuf>,
        /// Never write, even with `--to`.
        #[arg(long)]
        dry_run: bool,
        /// Print the changed line (always printed in a dry run).
        #[arg(long)]
        diff: bool,
    },
}

fn parse_glow(raw: &str) -> Result<f32, String> {
    let value: f32 = raw.parse().map_err(|e| format!("{raw:?}: {e}"))?;
    if !(0.0..=16.0).contains(&value) || !value.is_finite() {
        return Err(format!("{raw:?} is outside the discharge's 0..16 range"));
    }
    Ok(value)
}

fn parse_room(raw: &str) -> Result<f32, String> {
    let value: f32 = raw.parse().map_err(|e| format!("{raw:?}: {e}"))?;
    if !(0.0..=2.0).contains(&value) || !value.is_finite() {
        return Err(format!("{raw:?} is outside the room's 0..2 range"));
    }
    Ok(value)
}

fn parse_row(raw: Option<&str>) -> Result<Option<[i32; 4]>> {
    let Some(raw) = raw else {
        return Ok(None);
    };
    let bytes = raw.as_bytes();
    if bytes.len() != 4 || !bytes.iter().all(u8::is_ascii_digit) {
        bail!("--row {raw:?}: want exactly four digits, e.g. --row 1750");
    }
    Ok(Some([
        (bytes[0] - b'0') as i32,
        (bytes[1] - b'0') as i32,
        (bytes[2] - b'0') as i32,
        (bytes[3] - b'0') as i32,
    ]))
}

/// The layout NixieClock.qml builds, in shader-space device pixels:
/// `numeralSize = round(nixieDigitSize * uiScale)`, `mmPerPx = numeralSize/18`,
/// the glass is 21 x 35 mm, the pad is `round(nixieTubeMargin * uiScale)`, and
/// the two gaps are `round(numeral * 0.055)` and `round(numeral * 0.20)`.
struct Layout {
    mm: f32,
    pad: f32,
    tile: [f32; 2],
    row: [f32; 2],
    tube_x: [f32; 4],
    thick: f32,
}

fn layout(tokens: &uniforms::Tokens, scale: u32) -> Layout {
    let s = scale as f32;
    let numeral = (tokens.digit_size * tokens.ui_scale).round().max(1.0);
    let mm_logical = numeral / 18.0;
    let mm = mm_logical * s;
    let pad = (tokens.tube_margin * tokens.ui_scale).round().max(0.0) * s;
    let glass_w = (21.0 * mm_logical).round().max(2.0) * s;
    let glass_h = (35.0 * mm_logical).round().max(2.0) * s;
    let tube_gap = (numeral * 0.055 * tokens.spacing).round().max(0.0) * s;
    let pair_gap = (numeral * 0.20 * tokens.spacing).round().max(0.0) * s;
    let row_w = 4.0 * glass_w + 2.0 * tube_gap + pair_gap + 2.0 * pad;
    let row_h = glass_h + 2.0 * pad;
    // the four centrelines, from NixieClock.qml's tubeX: the glass edges and
    // the two gaps are measured on the glass, then shifted into the item
    let half = glass_w / 2.0;
    let left = [
        half,
        half + glass_w + tube_gap,
        half + 2.0 * glass_w + tube_gap + pair_gap,
        half + 3.0 * glass_w + 2.0 * tube_gap + pair_gap,
    ];
    let mut tube_x = [0.0f32; 4];
    for (i, x) in left.iter().enumerate() {
        tube_x[i] = pad + x - row_w / 2.0;
    }
    Layout {
        mm,
        pad,
        tile: [glass_w + 2.0 * pad, glass_h + 2.0 * pad],
        row: [row_w, row_h],
        tube_x,
        thick: (0.9 * mm_logical).max(0.8) * s,
    }
}

/// The inputs a render needs, read and compiled once per invocation.
struct Scene {
    shader_path: PathBuf,
    theme_path: PathBuf,
    shader_hash: String,
    theme_hash: String,
    spv_path: PathBuf,
    spv_hash: String,
    block: uniforms::Block,
    tokens: uniforms::Tokens,
    device: Option<u32>,
}

#[allow(clippy::too_many_arguments)]
fn scene(
    src: &str,
    shader_path: &Path,
    theme_path: &Path,
    theme_src: &str,
    tokens: uniforms::Tokens,
    device: Option<u32>,
) -> Result<Scene> {
    let compute = shader::to_compute(src).context("rewriting the fragment shader for compute")?;
    let block =
        uniforms::Block::parse(&compute).context("parsing the shader's std140 uniform block")?;
    let spv_path = shader::compile(&compute)?;
    let spv = std::fs::read(&spv_path)
        .with_context(|| format!("reading SPIR-V {}", spv_path.display()))?;
    Ok(Scene {
        shader_path: shader_path.to_path_buf(),
        theme_path: theme_path.to_path_buf(),
        shader_hash: hash::sha256(src.as_bytes()),
        theme_hash: hash::sha256(theme_src.as_bytes()),
        spv_path,
        spv_hash: hash::sha256(&spv),
        block,
        tokens,
        device,
    })
}

fn device_from_env() -> Option<u32> {
    match std::env::var("NIXIE_VK_DEVICE") {
        Ok(raw) => match raw.parse() {
            Ok(index) => Some(index),
            Err(_) => {
                eprintln!("nixie: NIXIE_VK_DEVICE={raw:?} is not an index; using the best device");
                None
            }
        },
        Err(_) => None,
    }
}

/// What stands behind the tube, ready to hand to the GPU.
struct Wallpaper {
    patch: image::RgbaImage,
    hash: String,
    source: String,
}

impl Wallpaper {
    fn json(&self) -> String {
        format!(
            "{{\"source\":{},\"sha256\":{}}}",
            jstr(&self.source),
            jstr(&self.hash)
        )
    }
}

/// The wallpaper patch, one `pInset` wider than the item on every side (that is
/// what the shader samples through pBackdrop). The greeter's cache file has no
/// extension, so the format is guessed from the bytes, never from the path; a
/// file that exists but does not decode is an error with the real cause, not a
/// silent gradient that makes every measurement a lie.
fn wallpaper(width: u32, height: u32, room: f32, explicit: Option<&Path>) -> Result<Wallpaper> {
    let path = match explicit {
        Some(path) => Some(path.to_path_buf()),
        None => wallpaper_from_env(),
    };
    let Some(path) = path else {
        eprintln!(
            "nixie: no wallpaper path (HOME and XDG_CACHE_HOME unset) — drawing over a gradient"
        );
        return Ok(gradient(width, height, room));
    };
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound && explicit.is_none() => {
            eprintln!(
                "nixie: {} not found — drawing over a gradient",
                path.display()
            );
            return Ok(gradient(width, height, room));
        }
        Err(e) => return Err(e).with_context(|| format!("reading wallpaper {}", path.display())),
    };
    if bytes.is_empty() {
        if explicit.is_none() {
            eprintln!(
                "nixie: {} is empty — drawing over a gradient",
                path.display()
            );
            return Ok(gradient(width, height, room));
        }
        bail!("wallpaper {} is empty", path.display());
    }
    let decoded = image::load_from_memory(&bytes).with_context(|| {
        format!(
            "decoding wallpaper {} ({} bytes)",
            path.display(),
            bytes.len()
        )
    })?;
    let src = decoded.to_rgba8();
    let mut patch = cover(&src, width, height);
    for pixel in patch.pixels_mut() {
        for c in 0..3 {
            pixel[c] = (pixel[c] as f32 * room).min(255.0) as u8;
        }
    }
    Ok(Wallpaper {
        patch,
        hash: hash::sha256(&bytes),
        source: path.display().to_string(),
    })
}

/// The greeter's order: its own override first, then XDG_CACHE_HOME, then HOME.
fn wallpaper_from_env() -> Option<PathBuf> {
    for key in ["NIXIE_WALLPAPER", "PREVIEW_WALLPAPER"] {
        if let Ok(value) = std::env::var(key) {
            if !value.is_empty() {
                return Some(PathBuf::from(value));
            }
        }
    }
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .filter(|value| !value.is_empty())
                .map(|home| PathBuf::from(home).join(".cache"))
        });
    base.map(|dir| dir.join("greeter-wallpaper"))
}

fn gradient(width: u32, height: u32, room: f32) -> Wallpaper {
    let mut out = image::RgbaImage::new(width, height);
    for y in 0..height {
        for x in 0..width {
            let u = x as f32 / width.max(1) as f32;
            let v = y as f32 / height.max(1) as f32;
            let grey = ((30.0 + 40.0 * (1.0 - v) + 12.0 * u) * room) as u8;
            out.put_pixel(
                x,
                y,
                image::Rgba([grey, grey, (grey as f32 * 1.1) as u8, 255]),
            );
        }
    }
    Wallpaper {
        patch: out,
        hash: hash::sha256(format!("gradient {width}x{height} room={room}").as_bytes()),
        source: "gradient".to_string(),
    }
}

/// Scale the picture to cover `width x height` and centre-crop it, like
/// `preserveAspectCrop`: the login screen never letterboxes the wallpaper.
fn cover(src: &image::RgbaImage, width: u32, height: u32) -> image::RgbaImage {
    let factor =
        (width as f32 / src.width().max(1) as f32).max(height as f32 / src.height().max(1) as f32);
    let rw = ((src.width() as f32 * factor).ceil() as u32)
        .max(width)
        .max(1);
    let rh = ((src.height() as f32 * factor).ceil() as u32)
        .max(height)
        .max(1);
    let resized = image::imageops::resize(src, rw, rh, image::imageops::FilterType::Triangle);
    let (ox, oy) = ((rw - width) / 2, (rh - height) / 2);
    image::imageops::crop_imm(&resized, ox, oy, width.max(1), height.max(1)).to_image()
}

/// The frame as the screen shows it: the tube's own light and the picture it
/// transmits, over the room behind it — the compositor's blend, so a
/// measurement sees what the eye would. The frame is the item; the wallpaper
/// patch extends `offset` px further on every side.
fn compose(frame: &image::RgbaImage, patch: &image::RgbaImage, offset: u32) -> image::RgbaImage {
    let mut out = image::RgbaImage::new(frame.width(), frame.height());
    for y in 0..frame.height() {
        for x in 0..frame.width() {
            let p = frame.get_pixel(x, y);
            let b = patch.get_pixel(x + offset, y + offset);
            let a = p[3] as f32 / 255.0;
            let mut q = [0u8; 4];
            for c in 0..3 {
                q[c] = (p[c] as f32 + (1.0 - a) * b[c] as f32).min(255.0) as u8;
            }
            q[3] = 255;
            out.put_pixel(x, y, image::Rgba(q));
        }
    }
    out
}

struct RenderOptions<'a> {
    out: &'a Path,
    digit: i32,
    scale: u32,
    glow: f32,
    room: f32,
    row: Option<[i32; 4]>,
    verify: bool,
    json: bool,
    wallpaper: Option<&'a Path>,
}

/// One tube (or the whole row), drawn off-screen: the same shader the login
/// screen uses, turned into a compute pass (see shader.rs) so nothing of the
/// compositor is needed.
fn render(scene: &Scene, gpu: &vulkan::Gpu, opts: &RenderOptions<'_>) -> Result<()> {
    let l = layout(&scene.tokens, opts.scale);
    let (width_f, height_f) = match opts.row {
        Some(_) => (l.row[0], l.row[1]),
        None => (l.tile[0], l.tile[1]),
    };
    let width = width_f.round() as u32;
    let height = height_f.round() as u32;
    let pad = l.pad.round() as u32;
    let wall = wallpaper(width + 2 * pad, height + 2 * pad, opts.room, opts.wallpaper)?;
    let limits = measure::Limits::for_scale(opts.scale as f32 / REFERENCE_SCALE);
    let mut uniforms = uniforms::Uniforms::from_drawing(
        &scene.tokens,
        l.mm,
        l.pad,
        l.tile,
        l.thick,
        [width_f, height_f],
        opts.digit,
    );
    uniforms.glow = opts.glow;
    if let Some(digits) = opts.row {
        // the row: the item is the whole row, each tube keeps its own item, and
        // the shader loops over the four. The geometry is NixieClock.qml's.
        uniforms.tile = [l.tile[0], l.tile[1], l.pad, 1.0];
        uniforms.row_x = l.tube_x;
        for (slot, digit) in uniforms.row_digit.iter_mut().zip(digits) {
            *slot = digit as f32;
        }
        uniforms.row_flicker = [1.0; 4];
    }
    let ubo = uniforms.pack(&scene.block)?;
    let frame = vulkan::render(gpu, &scene.spv_path, &ubo, &wall.patch, width, height)?;
    let frame_hash = hash::sha256(&frame.rgba);

    // The stand's own reproducibility gate: the same uniforms, the same
    // wallpaper, the same pass — twice. A single byte of drift means a missing
    // barrier or a racing input, and every measurement `sweep --check` takes is
    // then untrustworthy. The zero threshold is on purpose.
    if opts.verify {
        let again = vulkan::render(gpu, &scene.spv_path, &ubo, &wall.patch, width, height)?;
        if again.rgba.len() != frame.rgba.len() {
            bail!(
                "the two renders are not even the same size: {} vs {} bytes",
                frame.rgba.len(),
                again.rgba.len()
            );
        }
        let mut differing = 0usize;
        let mut worst = 0u8;
        for (a, b) in frame.rgba.iter().zip(again.rgba.iter()) {
            let d = a.abs_diff(*b);
            if d != 0 {
                differing += 1;
                worst = worst.max(d);
            }
        }
        if differing != 0 {
            bail!(
                "the render is not reproducible: {differing} of {} channels differ, worst {worst}/255 \
                 (device {}, shader {}, theme {}, wallpaper {})",
                frame.rgba.len(),
                gpu.description(),
                short(&scene.shader_hash),
                short(&scene.theme_hash),
                short(&wall.hash)
            );
        }
        if !opts.json {
            println!(
                "verify: two renders are identical ({}x{} device px, {} channels, threshold 0, frame sha256 {})",
                frame.width,
                frame.height,
                frame.rgba.len(),
                frame_hash
            );
        }
    }

    let image = image::RgbaImage::from_raw(frame.width, frame.height, frame.rgba)
        .ok_or_else(|| anyhow!("the readback is not an image"))?;
    // As the screen shows it: the compositor lays the item over the room.
    let shown = compose(&image, &wall.patch, pad);
    shown
        .save(opts.out)
        .with_context(|| format!("writing PNG {}", opts.out.display()))?;

    let measured = if opts.row.is_none() {
        Some(measure::measure(
            shown.as_raw(),
            shown.width(),
            (
                pad,
                pad,
                width.saturating_sub(pad),
                height.saturating_sub(pad),
            ),
        ))
    } else {
        None
    };

    if opts.json {
        println!(
            "{{\"command\":\"render\",\"device\":{},\"shader\":{{\"path\":{},\"sha256\":{}}},\
             \"theme\":{{\"path\":{},\"sha256\":{}}},\"spv\":{{\"path\":{},\"sha256\":{}}},\
             \"wallpaper\":{},\"scale\":{},\"mm\":{},\"pad\":{},\"size\":[{},{}],\
             \"row\":{},\"row_x\":{},\"digit\":{},\"glow\":{},\"room\":{},\"verified\":{},\
             \"tokens\":{},\"output\":{},\"sha256\":{},\"measured\":{},\"limits\":{},\"checks\":{}}}",
            jstr(gpu.description()),
            jstr(&scene.shader_path.display().to_string()),
            jstr(&scene.shader_hash),
            jstr(&scene.theme_path.display().to_string()),
            jstr(&scene.theme_hash),
            jstr(&scene.spv_path.display().to_string()),
            jstr(&scene.spv_hash),
            wall.json(),
            opts.scale,
            jnum(l.mm),
            jnum(l.pad),
            width,
            height,
            match opts.row {
                Some(d) => format!("[{},{},{},{}]", d[0], d[1], d[2], d[3]),
                None => "null".to_string(),
            },
            if opts.row.is_some() {
                format!(
                    "[{},{},{},{}]",
                    jnum(l.tube_x[0]),
                    jnum(l.tube_x[1]),
                    jnum(l.tube_x[2]),
                    jnum(l.tube_x[3])
                )
            } else {
                "null".to_string()
            },
            opts.digit,
            jnum(opts.glow),
            jnum(opts.room),
            opts.verify,
            tokens_json(&scene.tokens),
            jstr(&opts.out.display().to_string()),
            jstr(&frame_hash),
            measured
                .as_ref()
                .map(measured_json)
                .unwrap_or_else(|| "null".to_string()),
            limits_json(&limits),
            match &measured {
                Some(m) => checks_json(&m.checks(&limits)),
                None => "null".to_string(),
            }
        );
    } else {
        println!(
            "{}: {}x{} device px (frame sha256 {})",
            opts.out.display(),
            frame.width,
            frame.height,
            frame_hash
        );
        if let Some(m) = &measured {
            println!(
                "  wire {}/{} px, halo {} px, glass {:.1}%, mesh {:.1}%",
                m.wire_white_px,
                m.wire_hot_px,
                m.halo_half_px,
                m.glass_own_light * 100.0,
                m.cage_contrast * 100.0
            );
        }
    }
    Ok(())
}

struct SweepOptions<'a> {
    out: &'a Path,
    scale: u32,
    check: bool,
    json: bool,
    wallpaper: Option<&'a Path>,
}

struct SweepDigit {
    digit: i32,
    measured: measure::Measured,
    checks: Vec<(&'static str, bool, String)>,
}

/// Every numeral, drawn on the same device pass, measured as it comes out, and
/// laid out as one sheet: any configuration of the lamp can be looked at and
/// judged in one run.
fn sweep(scene: &Scene, gpu: &vulkan::Gpu, opts: &SweepOptions<'_>) -> Result<()> {
    let l = layout(&scene.tokens, opts.scale);
    let width = l.tile[0].round() as u32;
    let height = l.tile[1].round() as u32;
    let pad = l.pad.round() as u32;
    // the login screen's own dimmer: the sweep exists to gate the login's
    // pixels, and the plan's limits were measured on that dimmed picture
    let wall = wallpaper(width + 2 * pad, height + 2 * pad, 0.45, opts.wallpaper)?;
    let limits = measure::Limits::for_scale(opts.scale as f32 / REFERENCE_SCALE);

    let mut sheet = image::RgbaImage::new(width * 10, height);
    let mut failures = 0usize;
    let mut reports: Vec<SweepDigit> = Vec::new();
    if !opts.json {
        println!("digit  wire white/hot   halo half   glass light   mesh contrast   ink top");
    }
    for digit in 0..10i32 {
        let uniforms = uniforms::Uniforms::from_drawing(
            &scene.tokens,
            l.mm,
            l.pad,
            l.tile,
            l.thick,
            [width as f32, height as f32],
            digit,
        );
        let ubo = uniforms.pack(&scene.block)?;
        let frame = vulkan::render(gpu, &scene.spv_path, &ubo, &wall.patch, width, height)?;
        let tile = image::RgbaImage::from_raw(frame.width, frame.height, frame.rgba)
            .ok_or_else(|| anyhow!("the readback is not an image"))?;
        // The measurements are taken on the picture as it is shown, not on the
        // raw pass: the tube's transparent pixels are the room, and a median
        // taken over raw alpha would count them as black.
        let shown = compose(&tile, &wall.patch, pad);
        let measured = measure::measure(
            shown.as_raw(),
            shown.width(),
            (
                pad,
                pad,
                width.saturating_sub(pad),
                height.saturating_sub(pad),
            ),
        );
        let checks = measured.checks(&limits);
        if !opts.json {
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
            if opts.check {
                for (name, ok, detail) in &checks {
                    if !ok {
                        println!("       FAIL {name}: {detail}");
                    }
                }
            }
        }
        if opts.check {
            failures += checks.iter().filter(|(_, ok, _)| !ok).count();
        }
        reports.push(SweepDigit {
            digit,
            measured,
            checks,
        });
        image::imageops::replace(&mut sheet, &shown, (digit as i64) * width as i64, 0);
    }
    // The glass itself: measured on the lamp with nothing lit, which is where
    // the plan's A3 measures it too — the discharge drowns everything else.
    let dark = uniforms::Uniforms::from_drawing(
        &scene.tokens,
        l.mm,
        l.pad,
        l.tile,
        l.thick,
        [width as f32, height as f32],
        -1,
    );
    let ubo = dark.pack(&scene.block)?;
    let frame = vulkan::render(gpu, &scene.spv_path, &ubo, &wall.patch, width, height)?;
    let dark_tile = image::RgbaImage::from_raw(frame.width, frame.height, frame.rgba)
        .ok_or_else(|| anyhow!("the readback is not an image"))?;
    let dark_shown = compose(&dark_tile, &wall.patch, pad);
    let glass = measure::measure(
        dark_shown.as_raw(),
        dark_shown.width(),
        (
            pad,
            pad,
            width.saturating_sub(pad),
            height.saturating_sub(pad),
        ),
    );
    // Against a lit wire, not against this frame's own peak: on an unlit lamp
    // the peak is the glass itself, and dividing by it makes the glass look
    // worse the cleaner it gets. The wire's peak is 255 by construction.
    let own = glass.glass_own_light * glass.peak as f32 / 255.0;
    let mut unlit_checks: Vec<(&'static str, bool, String)> = Vec::new();
    unlit_checks.push((
        "the glass adds little of its own",
        own <= limits.glass_own_light,
        format!(
            "unlit glass adds {:.1}% of a lit wire (limit {:.0}%)",
            own * 100.0,
            limits.glass_own_light * 100.0
        ),
    ));
    unlit_checks.push((
        "the mesh is there",
        glass.cage_contrast >= limits.cage_contrast,
        format!("mesh contrast {:.1}%", glass.cage_contrast * 100.0),
    ));
    if opts.check {
        failures += unlit_checks.iter().filter(|(_, ok, _)| !ok).count();
    }
    if !opts.json {
        println!(
            "unlit lamp: glass adds {:.1}% of a lit wire (limit 8%), mesh contrast {:.1}%",
            own * 100.0,
            glass.cage_contrast * 100.0
        );
        if opts.check {
            for (name, ok, detail) in &unlit_checks {
                if !ok {
                    println!("       FAIL {name}: {detail}");
                }
            }
        }
    }

    sheet
        .save(opts.out)
        .with_context(|| format!("writing PNG {}", opts.out.display()))?;

    if opts.json {
        let digits: Vec<String> = reports
            .iter()
            .map(|r| {
                format!(
                    "{{\"digit\":{},\"measured\":{},\"checks\":{}}}",
                    r.digit,
                    measured_json(&r.measured),
                    checks_json(&r.checks)
                )
            })
            .collect();
        println!(
            "{{\"command\":\"sweep\",\"device\":{},\"shader\":{{\"path\":{},\"sha256\":{}}},\
             \"theme\":{{\"path\":{},\"sha256\":{}}},\"spv\":{{\"path\":{},\"sha256\":{}}},\
             \"wallpaper\":{},\"scale\":{},\"mm\":{},\"pad\":{},\"tile\":[{},{}],\
             \"limits\":{},\"tokens\":{},\"digits\":[{}],\"unlit\":{{\"measured\":{},\"own_light_of_wire\":{},\
             \"checks\":{}}},\"failures\":{},\"pass\":{},\"output\":{}}}",
            jstr(gpu.description()),
            jstr(&scene.shader_path.display().to_string()),
            jstr(&scene.shader_hash),
            jstr(&scene.theme_path.display().to_string()),
            jstr(&scene.theme_hash),
            jstr(&scene.spv_path.display().to_string()),
            jstr(&scene.spv_hash),
            wall.json(),
            opts.scale,
            jnum(l.mm),
            jnum(l.pad),
            width,
            height,
            limits_json(&limits),
            tokens_json(&scene.tokens),
            digits.join(","),
            measured_json(&glass),
            jnum(own),
            checks_json(&unlit_checks),
            failures,
            failures == 0,
            jstr(&opts.out.display().to_string())
        );
    } else {
        println!(
            "{}: {}x{}",
            opts.out.display(),
            sheet.width(),
            sheet.height()
        );
    }
    if failures > 0 {
        std::process::exit(1);
    }
    Ok(())
}

/// Patch one token in a JSONC file, preserving every other byte — comments
/// included. Returns the patched text, the old literal as the file wrote it,
/// the new literal, and the 1-based line the value sits on.
fn patch_jsonc(src: &str, key: &str, value: &str) -> Result<(String, String, String, usize)> {
    let needle = format!("\"{key}\"");
    let hits: Vec<usize> = src.match_indices(&needle).map(|(at, _)| at).collect();
    match hits.len() {
        0 => bail!(
            "the file does not contain {needle}; `theme set` only replaces an existing key \
             (add the token first)"
        ),
        1 => {}
        n => bail!("{needle} appears {n} times in the file; refusing to guess which one to patch"),
    }
    let after_key = hits[0] + needle.len();
    let colon = src[after_key..]
        .find(':')
        .ok_or_else(|| anyhow!("{needle} has no ':' after it"))?;
    let bytes = src.as_bytes();
    let mut start = after_key + colon + 1;
    while start < bytes.len() && bytes[start].is_ascii_whitespace() {
        start += 1;
    }
    if start >= bytes.len() {
        bail!("{needle} has no value after its ':'");
    }
    let end = if bytes[start] == b'"' {
        let mut j = start + 1;
        loop {
            if j >= bytes.len() {
                bail!("{needle} has an unterminated string value");
            }
            match bytes[j] {
                b'\\' => j += 2,
                b'"' => {
                    j += 1;
                    break;
                }
                _ => j += 1,
            }
        }
        j
    } else {
        let mut j = start;
        while j < bytes.len()
            && !matches!(bytes[j], b',' | b'}' | b']' | b'\n' | b'\r')
            && !(bytes[j] == b'/' && j + 1 < bytes.len() && bytes[j + 1] == b'/')
        {
            j += 1;
        }
        while j > start && bytes[j - 1].is_ascii_whitespace() {
            j -= 1;
        }
        j
    };
    let old = src[start..end].to_string();
    let new_literal = match bytes[start] {
        b'"' => {
            let bare = value
                .strip_prefix('"')
                .and_then(|v| v.strip_suffix('"'))
                .unwrap_or(value);
            format!("\"{}\"", escape_json_string(bare))
        }
        b't' | b'f' => match value {
            "true" | "false" => value.to_string(),
            _ => bail!("{needle} is a boolean; --value must be true or false"),
        },
        b'n' => {
            if value == "null" {
                "null".to_string()
            } else {
                bail!("{needle} is null; --value must be null")
            }
        }
        _ => {
            value
                .parse::<f64>()
                .map_err(|_| anyhow!("{needle} is a number; --value {value:?} is not"))?;
            value.to_string()
        }
    };
    let line = src[..start].bytes().filter(|b| *b == b'\n').count() + 1;
    let mut out = String::with_capacity(src.len() + new_literal.len());
    out.push_str(&src[..start]);
    out.push_str(&new_literal);
    out.push_str(&src[end..]);
    Ok((out, old, new_literal, line))
}

fn theme_set(action: &ThemeAction) -> Result<()> {
    let ThemeAction::Set {
        file,
        key,
        value,
        to,
        dry_run,
        diff,
    } = action;
    let src = std::fs::read_to_string(file)
        .with_context(|| format!("reading theme file {}", file.display()))?;
    let key = key.trim_matches('"');
    // A colour or an enum patch is checked before the file is touched: the
    // helper is the sanctioned way to edit the repo part, so it must not write
    // a value the shader-side reader would refuse.
    match key {
        "nixieTint" | "nixieGlowColor" | "nixieGlassColor" | "nixieCathodeColor" => {
            uniforms::colour(value).with_context(|| format!("theme set {key}"))?;
        }
        "nixieQuality" => match value.as_str() {
            "full" | "balanced" | "lite" => {}
            other => bail!("theme set {key}: {other:?} is not full, balanced or lite"),
        },
        _ => {}
    };
    let (patched, old, new_literal, line) = patch_jsonc(&src, key, value)?;
    if *diff || *dry_run || to.is_none() {
        println!(
            "{}:{}: \"{}\": {} -> {}",
            file.display(),
            line,
            key,
            old,
            new_literal
        );
    }
    match to {
        Some(to) if !*dry_run => {
            write_atomic(to, &patched)?;
            println!(
                "wrote {} (atomic rename; {} byte(s), comments preserved)",
                to.display(),
                patched.len()
            );
        }
        Some(to) => println!("dry run: {} not written", to.display()),
        None => println!(
            "dry run: {} not written (pass --to PATH to save)",
            file.display()
        ),
    }
    Ok(())
}

/// The menu contract's write path: a temp file next to the target, then rename.
fn write_atomic(to: &Path, contents: &str) -> Result<()> {
    let name = to
        .file_name()
        .ok_or_else(|| anyhow!("{} has no file name", to.display()))?;
    let tmp = to.with_file_name(format!(".{}.new", name.to_string_lossy()));
    std::fs::write(&tmp, contents).with_context(|| format!("writing {}", tmp.display()))?;
    if let Err(e) = std::fs::rename(&tmp, to) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e).with_context(|| format!("renaming {} to {}", tmp.display(), to.display()));
    }
    Ok(())
}

fn escape_json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn jstr(value: &str) -> String {
    format!("\"{}\"", escape_json_string(value))
}

fn jnum(value: f32) -> String {
    if value.is_finite() {
        format!("{value}")
    } else {
        "null".to_string()
    }
}

fn measured_json(m: &measure::Measured) -> String {
    format!(
        "{{\"wire_white_px\":{},\"wire_hot_px\":{},\"halo_half_px\":{},\
         \"glass_own_light\":{},\"cage_contrast\":{},\"ink_top_share\":{},\
         \"ink_bbox\":[{},{},{},{}],\"peak\":{}}}",
        m.wire_white_px,
        m.wire_hot_px,
        m.halo_half_px,
        jnum(m.glass_own_light),
        jnum(m.cage_contrast),
        jnum(m.ink_top_share),
        m.ink_bbox.0,
        m.ink_bbox.1,
        m.ink_bbox.2,
        m.ink_bbox.3,
        m.peak
    )
}

fn checks_json(checks: &[(&'static str, bool, String)]) -> String {
    let items: Vec<String> = checks
        .iter()
        .map(|(name, ok, detail)| {
            format!(
                "{{\"name\":{},\"ok\":{},\"detail\":{}}}",
                jstr(name),
                ok,
                jstr(detail)
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

fn limits_json(limits: &measure::Limits) -> String {
    format!(
        "{{\"wire_white_px\":{},\"wire_hot_px\":{},\"halo_half_px\":[{},{}],\
         \"glass_own_light\":{},\"cage_contrast\":{}}}",
        limits.wire_white_px,
        limits.wire_hot_px,
        limits.halo_half_px.0,
        limits.halo_half_px.1,
        jnum(limits.glass_own_light),
        jnum(limits.cage_contrast)
    )
}

/// The resolved token values a run used — `--set` overrides included — so a
/// script can record what produced the frame without re-reading the theme.
fn tokens_json(t: &uniforms::Tokens) -> String {
    let hex = |c: [f32; 4]| -> String {
        let b = |v: f32| (v.clamp(0.0, 1.0) * 255.0).round() as u8;
        format!(
            "#{:02x}{:02x}{:02x}{:02x}",
            b(c[3]),
            b(c[0]),
            b(c[1]),
            b(c[2])
        )
    };
    format!(
        "{{\"nixieDigitSize\":{},\"uiScale\":{},\"nixieTubeMargin\":{},\"nixieSpacing\":{},\
         \"nixieGlow\":{},\"nixieWire\":{},\"nixieTempK\":{},\"nixieExposure\":{},\
         \"nixieFlickerMs\":{},\"nixieShimmer\":{},\"nixieShimmerMs\":{},\"nixieJitter\":{},\
         \"nixieAge\":{},\"nixieStack\":{},\"nixieHighlight\":{},\"nixieWarmth\":{},\
         \"nixieTint\":{},\"nixieGlowColor\":{},\"nixieGlassColor\":{},\"nixieCathodeColor\":{},\
         \"nixieTintWallpaper\":{},\"nixieViewAngle\":{},\"nixieViewDistance\":{},\"nixieViewPitch\":{},\
         \"nixieQuality\":{},\"nixieFlicker\":{},\"nixie24h\":{},\"nixieLeadingZero\":{},\
         \"nixieBase\":{}}}",
        jnum(t.digit_size),
        jnum(t.ui_scale),
        jnum(t.tube_margin),
        jnum(t.spacing),
        jnum(t.glow),
        jnum(t.wire),
        jnum(t.temp),
        jnum(t.exposure),
        jnum(t.flicker_ms),
        jnum(t.shimmer),
        jnum(t.shimmer_ms),
        jnum(t.jitter),
        jnum(t.age),
        jnum(t.stack),
        jnum(t.highlight),
        jnum(t.warmth),
        jstr(&hex(t.tint)),
        jstr(&hex(t.glow_color)),
        jstr(&hex(t.glass_color)),
        jstr(&hex(t.cathode_color)),
        jnum(t.tint_wallpaper),
        jnum(t.view_angle),
        jnum(t.view_distance),
        jnum(t.view_pitch),
        jstr(&t.quality),
        t.flicker,
        t.h24,
        t.leading_zero,
        t.base
    )
}

fn short(hash: &str) -> &str {
    hash.get(..8).unwrap_or(hash)
}

/// A path relative to the repo: the environment wins, then the nearest ancestor
/// of the current directory that has the file, then the installed fallback.
fn resolve_repo_file(relative: &str, env: &str, fallback: &str) -> PathBuf {
    if let Ok(value) = std::env::var(env) {
        if !value.is_empty() {
            return PathBuf::from(value);
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        let mut dir = Some(cwd.as_path());
        while let Some(d) = dir {
            let candidate = d.join(relative);
            if candidate.is_file() {
                return candidate;
            }
            dir = d.parent();
        }
    }
    PathBuf::from(fallback)
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let shader_path = cli.shader.clone().unwrap_or_else(|| {
        resolve_repo_file(
            "files/quickshell/greeter/shaders/nixie.frag",
            "NIXIE_SHADER",
            SHADER_FALLBACK,
        )
    });
    let theme_path = cli.theme.clone().unwrap_or_else(|| {
        resolve_repo_file(
            "files/quickshell/Theme/greeter.jsonc",
            "NIXIE_THEME",
            THEME_FALLBACK,
        )
    });
    let src = std::fs::read_to_string(&shader_path)
        .with_context(|| format!("reading shader {}", shader_path.display()))?;
    let theme_src = std::fs::read_to_string(&theme_path)
        .with_context(|| format!("reading theme {}", theme_path.display()))?;
    let mut tokens = uniforms::Tokens::read(&theme_src)
        .with_context(|| format!("reading tokens from {}", theme_path.display()))?;
    for raw in &cli.sets {
        let (key, value) = raw
            .split_once('=')
            .ok_or_else(|| anyhow!("--set {raw:?}: want TOKEN=VALUE, e.g. --set nixieGlow=1.4"))?;
        if key.is_empty() {
            bail!("--set {raw:?}: the token name is empty");
        }
        tokens
            .apply(key, value)
            .with_context(|| format!("applying --set {raw}"))?;
    }
    let drawing = drawing::Drawing::read(&src, tokens.wire as f64)
        .context("reading the lamp's drawing out of the shader")?;

    match &cli.command {
        Command::Validate => {
            let report = geometry::check(&drawing);
            print!("{}", report.text());
            std::process::exit(if report.failed() == 0 { 0 } else { 1 });
        }
        Command::Theme { action } => theme_set(action),
        Command::Render {
            out,
            digit,
            scale,
            glow,
            room,
            row,
            verify,
            json,
        } => {
            // validate the row before compiling the shader or touching Vulkan
            let row = parse_row(row.as_deref())?;
            let scene = scene(
                &src,
                &shader_path,
                &theme_path,
                &theme_src,
                tokens,
                cli.device.or_else(device_from_env),
            )?;
            let gpu = vulkan::Gpu::new(scene.device)?;
            let result = render(
                &scene,
                &gpu,
                &RenderOptions {
                    out,
                    digit: *digit,
                    scale: *scale,
                    glow: *glow,
                    room: *room,
                    row,
                    verify: *verify,
                    json: *json,
                    wallpaper: cli.wallpaper.as_deref(),
                },
            );
            result
        }
        Command::Sweep {
            out,
            scale,
            check,
            json,
        } => {
            let scene = scene(
                &src,
                &shader_path,
                &theme_path,
                &theme_src,
                tokens,
                cli.device.or_else(device_from_env),
            )?;
            let gpu = vulkan::Gpu::new(scene.device)?;
            sweep(
                &scene,
                &gpu,
                &SweepOptions {
                    out,
                    scale: *scale,
                    check: *check,
                    json: *json,
                    wallpaper: cli.wallpaper.as_deref(),
                },
            )
        }
    }
}

/// A small SHA-256, so a run can say which inputs it measured.
///
/// The workbench prints the hash of the shader, the theme and the wallpaper it
/// actually read: two runs that print the same hashes saw the same inputs, and
/// the run-to-run noise cannot hide in an input that changed underneath. The
/// crate deliberately keeps its dependency list short, so the hash is here
/// rather than in a crate. It is inline because the flake only packages the
/// files git tracks, and a new module file would need a commit to be built.
mod hash {
    /// SHA-256 of `data`, lowercase hex.
    pub fn sha256(data: &[u8]) -> String {
        const K: [u32; 64] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
            0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
            0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
            0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
            0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
            0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
            0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
            0xc67178f2,
        ];
        let mut h: [u32; 8] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
            0x5be0cd19,
        ];
        // the message, padded to a whole number of 512-bit blocks
        let bit_len = (data.len() as u64).wrapping_mul(8);
        let mut msg = Vec::with_capacity(data.len() + 72);
        msg.extend_from_slice(data);
        msg.push(0x80);
        while msg.len() % 64 != 56 {
            msg.push(0);
        }
        msg.extend_from_slice(&bit_len.to_be_bytes());

        for chunk in msg.chunks_exact(64) {
            let mut w = [0u32; 64];
            for (i, word) in chunk.chunks_exact(4).enumerate() {
                w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
            }
            for i in 16..64 {
                let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
                let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
                w[i] = w[i - 16]
                    .wrapping_add(s0)
                    .wrapping_add(w[i - 7])
                    .wrapping_add(s1);
            }
            let (mut a, mut b, mut c, mut d) = (h[0], h[1], h[2], h[3]);
            let (mut e, mut f, mut g, mut hh) = (h[4], h[5], h[6], h[7]);
            for i in 0..64 {
                let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
                let ch = (e & f) ^ ((!e) & g);
                let t1 = hh
                    .wrapping_add(s1)
                    .wrapping_add(ch)
                    .wrapping_add(K[i])
                    .wrapping_add(w[i]);
                let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
                let maj = (a & b) ^ (a & c) ^ (b & c);
                let t2 = s0.wrapping_add(maj);
                hh = g;
                g = f;
                f = e;
                e = d.wrapping_add(t1);
                d = c;
                c = b;
                b = a;
                a = t1.wrapping_add(t2);
            }
            h[0] = h[0].wrapping_add(a);
            h[1] = h[1].wrapping_add(b);
            h[2] = h[2].wrapping_add(c);
            h[3] = h[3].wrapping_add(d);
            h[4] = h[4].wrapping_add(e);
            h[5] = h[5].wrapping_add(f);
            h[6] = h[6].wrapping_add(g);
            h[7] = h[7].wrapping_add(hh);
        }
        let mut out = String::with_capacity(64);
        for word in h {
            out.push_str(&format!("{word:08x}"));
        }
        out
    }

    #[cfg(test)]
    mod tests {
        use super::sha256;

        #[test]
        fn known_vectors() {
            assert_eq!(
                sha256(b""),
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            );
            assert_eq!(
                sha256(b"abc"),
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            );
            // one byte past the 55-byte boundary, so the padding spills into a second block
            assert_eq!(
                sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
            );
        }
    }
}
