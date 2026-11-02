//! The generator itself: load and normalise the reference image, then render
//! the snow frames exactly like `blizzard()` in the Python script.
//!
//! Randomness comes from [`crate::rng::Mt19937`] seeded the same way as
//! `random.Random(seed)`, so flakes, gusts and mound profiles are identical to
//! the original generator for a given seed.

// The Python source samples angles as `r.uniform(0, 6.28)`. TAU would change
// the random draw and therefore the whole frame sequence, so the literal stays.
#![allow(clippy::approx_constant)]

use crate::color;
use crate::dither::{self, Dither};
use crate::pillow::{self, Canvas};
use crate::rng::Mt19937;

pub struct Params {
    pub frames: usize,
    pub storm: f64,
    pub wind: f64,
    pub seed: i64,
    pub accum: f64,
    pub shader: String,
}

/// Pillow's `convert("L")` for an RGB image: ITU-R 601-2 with rounding.
fn pillow_luma(rgb: &[u8]) -> Vec<u8> {
    rgb.chunks_exact(3)
        .map(|p| {
            ((p[0] as u32 * 19595 + p[1] as u32 * 38470 + p[2] as u32 * 7471 + 0x8000) >> 16) as u8
        })
        .collect()
}

fn percentile_sorted(sorted: &[u8], q: f64) -> f64 {
    let n = sorted.len();
    if n == 0 {
        return 0.0;
    }
    if n == 1 {
        return sorted[0] as f64;
    }
    let virtual_index = (n as f64 - 1.0) * q;
    let lo = virtual_index.floor() as usize;
    let hi = (lo + 1).min(n - 1);
    let frac = virtual_index - lo as f64;
    sorted[lo] as f64 + (sorted[hi] as f64 - sorted[lo] as f64) * frac
}

fn percentile(values: &[u8], q: f64) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    percentile_sorted(&sorted, q)
}

/// `load_norm`: crop the skull out of the reference, stretch its contrast and
/// resize it to the output resolution with Pillow's LANCZOS resampler.
pub fn load_norm(path: &str, target_w: usize, target_h: usize) -> Result<Vec<f64>, String> {
    let image = image::open(path).map_err(|err| format!("cannot read {path}: {err}"))?;
    let rgb = image.to_rgb8();
    let width = rgb.width() as usize;
    let height = rgb.height() as usize;
    if width == 0 || height == 0 {
        return Err(format!("reference image {path} is empty"));
    }
    let luma = pillow_luma(rgb.as_raw());

    let blurred = pillow::gaussian_blur::<1>(&luma, width, height, 8.0);
    let lo = percentile(&blurred, 0.02);
    let hi = percentile(&blurred, 0.98);
    let scale = if hi > lo { hi - lo } else { 1.0 };

    let cutoff = (height as f64 * 0.6) as usize;
    let mut sum_x = 0.0f64;
    let mut sum_y = 0.0f64;
    let mut count = 0usize;
    for y in 0..height {
        if y >= cutoff {
            break;
        }
        for x in 0..width {
            let bn = ((blurred[y * width + x] as f64 - lo) / scale).clamp(0.0, 1.0);
            if bn > 0.55 {
                sum_x += x as f64;
                sum_y += y as f64;
                count += 1;
            }
        }
    }
    if count == 0 {
        return Err("reference image has no bright region to centre on".to_string());
    }
    let fx = sum_x / count as f64 / width as f64;
    let fy = sum_y / count as f64 / height as f64;

    let aspect = target_w as f64 / target_h as f64;
    let crop_w = (0.66 * width as f64) as usize;
    let crop_h = (crop_w as f64 / aspect) as usize;
    if crop_w == 0 || crop_h == 0 {
        return Err("reference crop is empty".to_string());
    }

    let x0 = (fx * width as f64 - crop_w as f64 / 2.0) as i32;
    let y0 = (fy * height as f64 - crop_h as f64 / 2.0) as i32;
    let x0 = x0.min(width as i32 - crop_w as i32).max(0) as usize;
    let y0 = y0.min(height as i32 - crop_h as i32).max(0) as usize;

    let mut crop = Vec::with_capacity(crop_w * crop_h);
    for y in 0..crop_h {
        for x in 0..crop_w {
            let sx = x0 + x;
            let sy = y0 + y;
            crop.push(if sx < width && sy < height {
                luma[sy * width + sx]
            } else {
                0
            });
        }
    }

    let lo = percentile(&crop, 0.02);
    let hi = percentile(&crop, 0.98);
    let scale = if hi > lo { hi - lo } else { 1.0 };
    let mut normalized = Vec::with_capacity(crop.len());
    for value in &crop {
        let n = ((*value as f64 - lo) / scale).clamp(0.0, 1.0).powf(0.7);
        normalized.push((n * 255.0) as u8);
    }

    let resized = pillow::resize_lanczos_l(&normalized, crop_w, crop_h, target_w, target_h);
    Ok(resized.iter().map(|v| *v as f64 / 255.0).collect())
}

/// `compute_snow_contour`: per-column top of the blurred silhouette, smoothed
/// with a 25-pixel window.
pub fn compute_snow_contour(norm: &[f64], width: usize, height: usize) -> Vec<i32> {
    let gray: Vec<u8> = norm.iter().map(|v| (v * 255.0) as u8).collect();
    let blurred = pillow::gaussian_blur::<1>(&gray, width, height, 7.0);
    let levels: Vec<f64> = blurred.iter().map(|v| *v as f64 / 255.0).collect();

    let mut contour = vec![0i32; width];
    for x in 0..width {
        let mut top = height as i32;
        for y in 0..height {
            if levels[y * width + x] > 0.18 {
                top = y as i32;
                break;
            }
        }
        contour[x] = top;
    }

    let k = 25i32 / 2;
    let mut smoothed = vec![0i32; width];
    for (x, slot) in smoothed.iter_mut().enumerate() {
        let lo = (x as i32 - k).max(0) as usize;
        let hi = ((x as i32 + k + 1) as usize).min(width);
        let sum: i64 = contour[lo..hi].iter().map(|v| *v as i64).sum();
        *slot = (sum as f64 / (hi - lo) as f64) as i32;
    }
    smoothed
}

struct Flake {
    x: f64,
    y: f64,
    v: f64,
    r: f64,
    drift: f64,
}

struct Layer {
    flakes: Vec<Flake>,
    alpha: i32,
    blur: f32,
}

#[allow(clippy::too_many_arguments)]
fn make_layer(
    rng: &mut Mt19937,
    count: usize,
    vrange: (f64, f64),
    rrange: (f64, f64),
    drift: (f64, f64),
    alpha: i32,
    blur: f32,
    width: usize,
    height: usize,
    storm: f64,
) -> Layer {
    let mut flakes = Vec::with_capacity(count);
    for _ in 0..count {
        flakes.push(Flake {
            x: rng.uniform(0.0, width as f64),
            y: rng.uniform(-(height as f64), height as f64),
            v: rng.uniform(vrange.0, vrange.1) * storm,
            r: rng.uniform(rrange.0, rrange.1),
            drift: rng.uniform(drift.0, drift.1),
        });
    }
    Layer {
        flakes,
        alpha,
        blur,
    }
}

struct SwirlPoint {
    rad: f64,
    spd: f64,
    phase: f64,
    r: f64,
}

/// Render every frame. Returns RGB buffers, one per frame.
pub fn render(
    base_rgb: &[u8],
    width: usize,
    height: usize,
    params: &Params,
    contour: Option<&[i32]>,
) -> Vec<Vec<u8>> {
    let mut rng = Mt19937::from_python_seed(params.seed);
    let tw = width as f64;
    let th = height as f64;

    // Three depth layers: background small/fast/faint, foreground big/slow.
    let mut layers = vec![
        make_layer(
            &mut rng,
            200,
            (150.0, 270.0),
            (0.9, 1.8),
            (0.5, 1.1),
            110,
            1.6,
            width,
            height,
            params.storm,
        ),
        make_layer(
            &mut rng,
            150,
            (95.0, 185.0),
            (2.1, 3.5),
            (0.6, 1.3),
            180,
            1.0,
            width,
            height,
            params.storm,
        ),
        make_layer(
            &mut rng,
            70,
            (40.0, 90.0),
            (4.0, 6.6),
            (0.7, 1.6),
            235,
            0.4,
            width,
            height,
            params.storm,
        ),
    ];

    let swirl_cx = tw * 0.5;
    let swirl_cy = th * 0.55;
    let mut swirl_ang = 0.0f64;
    let mut swirl_pts = Vec::with_capacity(26);
    for _ in 0..26 {
        swirl_pts.push(SwirlPoint {
            rad: rng.uniform(60.0, 220.0),
            spd: rng.uniform(0.5, 1.2),
            phase: rng.uniform(0.0, 6.28),
            r: rng.uniform(1.2, 2.6),
        });
    }

    // Broad rounded snow drifts along the contour.
    let mound_count = (width / 55).max(4);
    let mut mounds = Vec::with_capacity(mound_count);
    for _ in 0..mound_count {
        mounds.push((
            rng.uniform(0.0, tw),
            rng.uniform(30.0, 170.0),
            rng.uniform(0.35, 1.9),
        ));
    }
    let wobble1 = rng.uniform(0.0, 6.28);
    let wobble2 = rng.uniform(0.0, 6.28);

    let mut depth_profile = vec![0.0f64; width];
    for (x, slot) in depth_profile.iter_mut().enumerate() {
        let mut value = 0.0f64;
        for (cx, w, h) in &mounds {
            let d = (x as f64 - cx) / w;
            value = value.max(h * (-(d * d)).exp());
        }
        value *= 1.0
            + 0.18 * (x as f64 * 0.018 + wobble1).sin()
            + 0.10 * (x as f64 * 0.045 + wobble2).sin();
        *slot = value.max(0.0);
    }

    let mut frames = Vec::with_capacity(params.frames);
    for frame_index in 0..params.frames {
        let phase = frame_index as f64 / params.frames as f64;

        let gust = 0.55
            + 0.35 * (2.0 * std::f64::consts::PI * phase).sin()
            + 0.20 * (2.0 * std::f64::consts::PI * phase * 2.0 + 1.1).sin();
        let intensity = (gust * params.wind).max(0.35);

        let wind_angle =
            (-34.0 + 26.0 * (2.0 * std::f64::consts::PI * phase * 1.7 + 0.4).sin()).to_radians();
        let wind_strength = 2.0
            + 2.6 * (2.0 * std::f64::consts::PI * phase + 0.9).sin()
            + 1.2 * (2.0 * std::f64::consts::PI * phase * 3.0 + 2.0).sin();
        let wx = wind_angle.sin() * wind_strength * params.wind;

        let mut overlay = Canvas::new(width, height);

        for layer in layers.iter_mut() {
            let mut layer_canvas = Canvas::new(width, height);
            for flake in layer.flakes.iter_mut() {
                flake.y += flake.v;
                flake.x += flake.v * flake.drift * wx;
                if flake.y > th + 14.0 {
                    flake.y = rng.uniform(-40.0, -4.0);
                    flake.x = rng.uniform(0.0, tw);
                }
                if flake.x > tw + 14.0 {
                    flake.x = -14.0;
                }
                if flake.x < -14.0 {
                    flake.x = tw + 14.0;
                }

                let radius = flake.r;
                let alpha = (layer.alpha as f64 * (0.55 + 0.45 * intensity)) as i32;
                let vx = flake.v * flake.drift * wx;
                let vy = flake.v;
                let mut magnitude = (vx * vx + vy * vy).sqrt();
                if magnitude == 0.0 {
                    magnitude = 1.0;
                }
                let streak = radius * 2.6 + flake.v * 0.016;
                let ux = vx / magnitude;
                let uy = vy / magnitude;
                let (hx, hy) = (flake.x, flake.y);
                let (tx, ty) = (hx - ux * streak, hy - uy * streak);

                let line_width = (radius as i32).max(1);
                layer_canvas.line(hx, hy, tx, ty, [236, 243, 253, alpha], line_width);
                layer_canvas.line(
                    hx,
                    hy,
                    hx - ux * streak * 0.5,
                    hy - uy * streak * 0.5,
                    [246, 250, 255, (alpha as f64 * 1.25) as i32],
                    1,
                );
            }
            let blurred = pillow::gaussian_blur::<4>(&layer_canvas.data, width, height, layer.blur);
            overlay.data = pillow::alpha_composite(&overlay.data, &blurred);
        }

        // Vortex: a subtle swirl of flakes around the centre.
        swirl_ang += 0.02;
        for point in &swirl_pts {
            let angle = point.phase + swirl_ang / point.spd;
            let x = swirl_cx + point.rad * angle.cos();
            let y = swirl_cy + point.rad * 0.62 * angle.sin();
            if x >= 0.0 && x < tw && y >= 0.0 && y < th {
                overlay.ellipse(
                    x - point.r,
                    y - point.r,
                    x + point.r,
                    y + point.r,
                    [230, 240, 250, (140.0 * intensity).max(0.0) as i32],
                );
            }
        }

        if let Some(contour) = contour {
            let depth =
                66.0 * params.accum * (((frame_index + 1) as f64) / params.frames as f64).powf(1.8)
                    + 3.0;
            let mut acc = Canvas::new(width, height);
            for x in 0..width {
                let y0 = contour[x];
                if y0 >= height as i32 - 2 {
                    continue;
                }
                let profile = depth_profile[x];
                let d = ((profile * depth + rng.uniform(-1.0, 1.0)) as i32).max(2);
                let y1 = (y0 + d).min(height as i32);

                let left = depth_profile[x.saturating_sub(1)];
                let right = depth_profile[(x + 1).min(width - 1)];
                let slope = right - left;
                let flat = (1.0 - slope.abs() * 2.3).max(0.0);
                let crevice = (1.0 - (profile * 1.2).min(1.5)).max(0.0);
                let bright = (flat * (1.0 - crevice * 0.72)).max(0.0);

                const STEPS: i32 = 5;
                for k in 0..STEPS {
                    let frac = k as f64 / STEPS as f64;
                    let tone = (bright * (1.0 - frac * 0.5)).max(0.0);
                    let r = (140.0 + (252.0 - 140.0) * tone) as i32;
                    let g = (158.0 + (253.0 - 158.0) * tone) as i32;
                    let b = (188.0 + (255.0 - 188.0) * tone) as i32;
                    let a = (65.0 + (238.0 - 65.0) * (0.30 + 0.70 * tone)) as i32;
                    let yy0 = y0 + (k * d) / STEPS;
                    let yy1 = y0 + ((k + 1) * d) / STEPS;
                    acc.line(x as f64, yy0 as f64, x as f64, yy1 as f64, [r, g, b, a], 1);
                }
                if d > 5 {
                    acc.line(
                        (x as i32 - 1) as f64,
                        (y0 + 1) as f64,
                        (x as i32 + 1) as f64,
                        (y0 + 1) as f64,
                        [255, 255, 255, 215],
                        2,
                    );
                }
                if flat > 0.6 && d > 8 {
                    acc.line(
                        x as f64,
                        y0 as f64,
                        x as f64,
                        (y0 + 1) as f64,
                        [255, 255, 255, 245],
                        2,
                    );
                }
                acc.line(
                    x as f64,
                    y1 as f64,
                    x as f64,
                    (y1 + 3).min(height as i32) as f64,
                    [70, 84, 116, 90],
                    2,
                );
                if crevice > 0.5 {
                    acc.line(
                        x as f64,
                        y1 as f64,
                        x as f64,
                        (y1 + 2).min(height as i32) as f64,
                        [38, 50, 84, 120],
                        2,
                    );
                }
            }
            let blurred = pillow::gaussian_blur::<4>(&acc.data, width, height, 1.3);
            overlay.data = pillow::alpha_composite(&overlay.data, &blurred);
        }

        // Breathing: gamma pulse plus a slight brightness pulse. Black stays
        // black, so the skull visibly inhales without lifting the background.
        let lut = color::breathing_lut(phase);
        let mut rgba = Vec::with_capacity(width * height * 4);
        for pixel in base_rgb.chunks_exact(3) {
            rgba.push(lut[pixel[0] as usize]);
            rgba.push(lut[pixel[1] as usize]);
            rgba.push(lut[pixel[2] as usize]);
            rgba.push(255);
        }
        let composed = pillow::alpha_composite(&rgba, &overlay.data);
        let mut frame = Vec::with_capacity(width * height * 3);
        for pixel in composed.chunks_exact(4) {
            frame.extend_from_slice(&pixel[..3]);
        }
        color::apply_shader(&mut frame, width, height, &params.shader);
        frames.push(frame);
    }
    frames
}

/// Build the dithered, palette-coloured base image.
pub fn base_image(
    norm: &[f64],
    width: usize,
    height: usize,
    dither: Dither,
    stops: &[color::Stop],
) -> Vec<u8> {
    let mask = dither::apply(dither, norm, width, height);
    color::colormap(&mask, norm, stops)
}
