//! blizzard — black-metal blizzard animated WebP generator.
//!
//! Rust port of `files/fastfetch/make_blizzard.py`: same CLI, same palettes,
//! same dithering kernels, same snow simulation. The image pipeline
//! (Pillow blur/resize/draw/alpha-composite) and the Mersenne Twister seeding
//! are reproduced from the Python runtime so a given seed produces the same
//! flakes and the same skull texture.

mod blizzard;
mod color;
mod dither;
mod pillow;
mod rng;

use std::process::exit;

use dither::Dither;

const REF: &str = "/home/neg/pic/necro/8a8c0e082df595deed2ef785f73c3476.jpg";
const DEFAULT_FRAMES: usize = 24;
const DEFAULT_SEED: i64 = 7;
const FRAME_DURATION_MS: i32 = 46;

/// Long options accepted by the CLI, in argparse's declaration order. They are
/// also matched by unique prefix, like argparse does.
const LONG_OPTIONS: [&str; 13] = [
    "--help",
    "--dither",
    "--palette",
    "--color",
    "--size",
    "--shader",
    "--accum",
    "--storm",
    "--wind",
    "--frames",
    "--seed",
    "--out",
    "--ref",
];

const USAGE: &str = "usage: blizzard [-h] [--dither {fs,atkinson,sierra,stucki,bayer,noise,none}]
                [--palette {ash,ember,ice}] [--color COLOR] [--size SIZE]
                [--shader {none,invert,rgb,invert:rgb}] [--accum ACCUM]
                [--storm STORM] [--wind WIND] [--frames FRAMES] [--seed SEED]
                [--out OUT] [--ref REF]";

fn fail_usage(message: &str) -> ! {
    eprintln!("{USAGE}");
    eprintln!("blizzard: error: {message}");
    exit(2)
}

fn fail(message: &str) -> ! {
    eprintln!("blizzard: {message}");
    exit(1)
}

fn print_help() {
    println!("{USAGE}");
    println!();
    println!("Black-metal blizzard generator (animated WebP) from a reference image.");
    println!();
    println!("options:");
    println!("  -h, --help            show this help message and exit");
    println!("  --dither {{fs,atkinson,sierra,stucki,bayer,noise,none}}");
    println!("  --palette {{ash,ember,ice}}");
    println!("  --color COLOR         custom base color #RRGGBB -> builds its own gradient");
    println!("  --size SIZE           output resolution WxH (default 640x806)");
    println!("  --shader {{none,invert,rgb,invert:rgb}}");
    println!("  --accum ACCUM         snow accumulation amount (0 = off)");
    println!("  --storm STORM");
    println!("  --wind WIND");
    println!("  --frames FRAMES       default {DEFAULT_FRAMES}");
    println!("  --seed SEED           default {DEFAULT_SEED}");
    println!("  --out OUT             output path (default ~/.local/share/fastfetch/logos/blizzard.webp)");
    println!("  --ref REF             reference image (default {REF})");
}

struct Options {
    dither: String,
    palette: String,
    color: String,
    size: Option<String>,
    shader: String,
    accum: f64,
    storm: f64,
    wind: f64,
    frames: usize,
    seed: i64,
    out: String,
    reference: String,
}

impl Default for Options {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_default();
        Self {
            dither: "fs".to_string(),
            palette: "ash".to_string(),
            color: String::new(),
            size: None,
            shader: "none".to_string(),
            accum: 0.0,
            storm: 1.0,
            wind: 1.0,
            frames: DEFAULT_FRAMES,
            seed: DEFAULT_SEED,
            out: format!("{home}/.local/share/fastfetch/logos/blizzard.webp"),
            reference: REF.to_string(),
        }
    }
}

struct ArgStream {
    items: std::vec::IntoIter<String>,
}

impl ArgStream {
    fn next_value(&mut self, inline: Option<String>, name: &str) -> String {
        if let Some(value) = inline {
            return value;
        }
        match self.items.next() {
            Some(value) => value,
            None => fail_usage(&format!("argument {name}: expected one argument")),
        }
    }
}

fn resolve_option(name: &str) -> String {
    if LONG_OPTIONS.contains(&name) {
        return name.to_string();
    }
    let matches: Vec<&str> = LONG_OPTIONS
        .iter()
        .filter(|option| option.starts_with(name))
        .copied()
        .collect();
    match matches.len() {
        1 => matches[0].to_string(),
        0 => fail_usage(&format!("unrecognized arguments: {name}")),
        _ => fail_usage(&format!(
            "ambiguous option: {name} could match {}",
            matches.join(", ")
        )),
    }
}

fn parse_args() -> Options {
    let mut options = Options::default();
    let mut stream = ArgStream {
        items: std::env::args().skip(1).collect::<Vec<_>>().into_iter(),
    };

    while let Some(arg) = stream.items.next() {
        let (raw_name, inline) = match arg.split_once('=') {
            Some((name, value)) => (name.to_string(), Some(value.to_string())),
            None => (arg, None),
        };
        let name = if raw_name == "-h" || raw_name == "--help" {
            raw_name
        } else {
            resolve_option(&raw_name)
        };
        match name.as_str() {
            "-h" | "--help" => {
                print_help();
                exit(0);
            }
            "--dither" => {
                let value = stream.next_value(inline, "--dither");
                if Dither::parse(&value).is_none() {
                    fail_usage(&format!(
                        "argument --dither: invalid choice: {value:?} (choose from 'fs', 'atkinson', 'sierra', 'stucki', 'bayer', 'noise', 'none')"
                    ));
                }
                options.dither = value;
            }
            "--palette" => {
                let value = stream.next_value(inline, "--palette");
                if !color::PALETTE_NAMES.contains(&value.as_str()) {
                    fail_usage(&format!(
                        "argument --palette: invalid choice: {value:?} (choose from 'ash', 'ember', 'ice')"
                    ));
                }
                options.palette = value;
            }
            "--color" => options.color = stream.next_value(inline, "--color"),
            "--size" => options.size = Some(stream.next_value(inline, "--size")),
            "--shader" => {
                let value = stream.next_value(inline, "--shader");
                if !["none", "invert", "rgb", "invert:rgb"].contains(&value.as_str()) {
                    fail_usage(&format!(
                        "argument --shader: invalid choice: {value:?} (choose from 'none', 'invert', 'rgb', 'invert:rgb')"
                    ));
                }
                options.shader = value;
            }
            "--accum" => {
                let value = stream.next_value(inline, "--accum");
                options.accum = value.parse::<f64>().unwrap_or_else(|_| {
                    fail_usage(&format!("argument --accum: invalid float value: {value:?}"))
                });
            }
            "--storm" => {
                let value = stream.next_value(inline, "--storm");
                options.storm = value.parse::<f64>().unwrap_or_else(|_| {
                    fail_usage(&format!("argument --storm: invalid float value: {value:?}"))
                });
            }
            "--wind" => {
                let value = stream.next_value(inline, "--wind");
                options.wind = value.parse::<f64>().unwrap_or_else(|_| {
                    fail_usage(&format!("argument --wind: invalid float value: {value:?}"))
                });
            }
            "--frames" => {
                let value = stream.next_value(inline, "--frames");
                let frames = value.parse::<i64>().unwrap_or_else(|_| {
                    fail_usage(&format!("argument --frames: invalid int value: {value:?}"))
                });
                if frames < 1 {
                    fail("--frames must be at least 1");
                }
                options.frames = frames as usize;
            }
            "--seed" => {
                let value = stream.next_value(inline, "--seed");
                options.seed = value.parse::<i64>().unwrap_or_else(|_| {
                    fail_usage(&format!("argument --seed: invalid int value: {value:?}"))
                });
            }
            "--out" => options.out = stream.next_value(inline, "--out"),
            "--ref" => options.reference = stream.next_value(inline, "--ref"),
            _ => fail_usage(&format!("unrecognized arguments: {name}")),
        }
    }
    options
}

fn parse_size(value: &str) -> (usize, usize) {
    let (width, height) = value
        .split_once('x')
        .unwrap_or_else(|| fail(&format!("invalid --size {value:?}: expected WxH")));
    let width = width
        .parse::<usize>()
        .unwrap_or_else(|_| fail(&format!("invalid --size {value:?}: expected WxH")));
    let height = height
        .parse::<usize>()
        .unwrap_or_else(|_| fail(&format!("invalid --size {value:?}: expected WxH")));
    if width == 0 || height == 0 {
        fail(&format!(
            "invalid --size {value:?}: dimensions must be positive"
        ));
    }
    (width, height)
}

fn encode_webp(frames: &[Vec<u8>], width: u32, height: u32, out: &str) -> Result<usize, String> {
    let mut config =
        webp::WebPConfig::new().map_err(|_| "libwebp config init failed".to_string())?;
    config.quality = 92.0;
    config.method = 6;
    config.lossless = 0;
    config.alpha_quality = 100;

    let mut encoder = webp::AnimEncoder::new(width, height, &config);
    encoder.set_loop_count(0);
    for (index, frame) in frames.iter().enumerate() {
        encoder.add_frame(webp::AnimFrame::from_rgb(
            frame,
            width,
            height,
            index as i32 * FRAME_DURATION_MS,
        ));
    }
    let memory = encoder
        .try_encode()
        .map_err(|err| format!("WebP encoding failed: {err:?}"))?;
    std::fs::write(out, &memory[..]).map_err(|err| format!("cannot write {out}: {err}"))?;
    Ok(memory.len())
}

fn main() {
    let options = parse_args();

    if options.frames > i32::MAX as usize / FRAME_DURATION_MS as usize {
        fail("--frames is too large");
    }

    let (width, height) = match &options.size {
        Some(size) => parse_size(size),
        None => (640, 806),
    };

    let (stops, palette_label);
    if options.color.is_empty() {
        stops = color::palette(&options.palette);
        palette_label = options.palette.clone();
    } else {
        stops = color::build_gradient(&options.color).unwrap_or_else(|err| fail(&err));
        palette_label = "custom".to_string();
    }

    let norm =
        blizzard::load_norm(&options.reference, width, height).unwrap_or_else(|err| fail(&err));
    let dither = Dither::parse(&options.dither).expect("CLI validated the dither name");
    let base = blizzard::base_image(&norm, width, height, dither, &stops);

    let contour = if options.accum > 0.0 {
        Some(blizzard::compute_snow_contour(&norm, width, height))
    } else {
        None
    };

    let params = blizzard::Params {
        frames: options.frames,
        storm: options.storm,
        wind: options.wind,
        seed: options.seed,
        accum: options.accum,
        shader: options.shader.clone(),
    };
    let frames = blizzard::render(&base, width, height, &params, contour.as_deref());
    if frames.is_empty() {
        fail("no frames were generated");
    }

    let size = encode_webp(&frames, width as u32, height as u32, &options.out)
        .unwrap_or_else(|err| fail(&err));
    println!(
        "wrote {} {} | dither {} palette {}",
        options.out, size, options.dither, palette_label
    );
}
