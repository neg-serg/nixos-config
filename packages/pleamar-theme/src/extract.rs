//! The awk sampler: an ImageMagick `txt:` pixel dump in, the wallpaper palette
//! out.
//!
//! This is `theme-extract.awk` line for line: the accent mean with its two
//! relaxed passes, the hue match onto `#006FCC`, the weighted Oklab k-means
//! (k=4, lightness quantile seeds, 16 iterations, chroma x1.35), the light
//! detection on the mean WCAG luminance, and the 4.5:1 readability clamp on
//! the ink. The arithmetic is the awk program's arithmetic: doubles, the same
//! summation order, the same tie-breaking, and rounding to an 8-bit channel
//! only when a value is printed.

use crate::color;

/// One 8-bit sRGB colour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgb {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

impl Rgb {
    /// The `#rrggbb` string the awk `hex()` function printed: each channel is
    /// rounded with `int(v + 0.5)` and formatted as two lower-case hex digits.
    pub fn hex(self) -> String {
        format!("#{:02x}{:02x}{:02x}", self.red, self.green, self.blue)
    }
}

/// The five lines the awk program printed, as values.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Palette {
    pub coal: Rgb,
    pub surface: Rgb,
    pub ink: Rgb,
    pub accent: Rgb,
    pub light: bool,
}

/// The only failure the sampler has: fewer than eight usable pixel lines.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExtractError {
    NoPixels,
}

/// The `hex(r, g, b)` printer as a double-to-channel rounding step.
fn quantize(value: f64) -> u8 {
    // awk's `%02x` with `int(value + 0.5)`; valid channels stay in 0..=255.
    (value + 0.5) as i64 as u8
}

fn hexdec_dump(bytes: &[u8]) -> (u8, u8, u8) {
    let channel = |pair: &[u8]| -> u8 {
        let mut value: u32 = 0;
        for &byte in pair {
            let lowered = byte.to_ascii_lowercase();
            let digit = if lowered.is_ascii_digit() {
                u32::from(lowered - b'0')
            } else if (b'a'..=b'f').contains(&lowered) {
                u32::from(lowered - b'a') + 10
            } else {
                // awk's `index("abcdef", c) - 1 + 10` on a miss is 9.
                9
            };
            value = value * 16 + digit;
        }
        value as u8
    };
    (
        channel(&bytes[0..2]),
        channel(&bytes[2..4]),
        channel(&bytes[4..6]),
    )
}

/// Parse one ImageMagick `txt:` line, the awk pattern
/// `/^[0-9]+,[0-9]+:/` followed by the first six characters after the first
/// `#`. Returns `None` for the header and for anything the awk program skipped.
fn parse_pixel_line(line: &str) -> Option<(u8, u8, u8)> {
    let bytes = line.as_bytes();
    let mut index = 0;
    let digits_start = index;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
    }
    if index == digits_start {
        return None;
    }
    if index >= bytes.len() || bytes[index] != b',' {
        return None;
    }
    index += 1;
    let second_start = index;
    while index < bytes.len() && bytes[index].is_ascii_digit() {
        index += 1;
    }
    if index == second_start {
        return None;
    }
    if index >= bytes.len() || bytes[index] != b':' {
        return None;
    }
    let hash = bytes[index..].iter().position(|&byte| byte == b'#')?;
    let hex_start = index + hash + 1;
    if hex_start + 6 > bytes.len() {
        return None;
    }
    Some(hexdec_dump(&bytes[hex_start..hex_start + 6]))
}

/// Mean of the pixels that pass `select`, or the mean of every pixel when no
/// pixel passes. This is `AccentSampler.sampleAccent`'s pass ladder: the two
/// relaxed passes, then everything.
fn accent_mean(pixels: &[(u8, u8, u8)]) -> (f64, f64, f64) {
    let mean = |selected: &[(u8, u8, u8)]| -> (f64, f64, f64) {
        let mut red = 0u64;
        let mut green = 0u64;
        let mut blue = 0u64;
        for &(r, g, b) in selected {
            red += u64::from(r);
            green += u64::from(g);
            blue += u64::from(b);
        }
        #[allow(clippy::cast_precision_loss)]
        let count = selected.len() as f64;
        #[allow(clippy::cast_precision_loss)]
        (
            red as f64 / count,
            green as f64 / count,
            blue as f64 / count,
        )
    };

    let chroma = |pixel: &(u8, u8, u8)| -> (i32, f64) {
        let (r, g, b) = (i32::from(pixel.0), i32::from(pixel.1), i32::from(pixel.2));
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        (max - min, (r + g + b) as f64 / 3.0)
    };

    let strict: Vec<(u8, u8, u8)> = pixels
        .iter()
        .copied()
        .filter(|pixel| {
            let (spread, brightness) = chroma(pixel);
            spread >= 10 && (20.0..=235.0).contains(&brightness)
        })
        .collect();
    if !strict.is_empty() {
        return mean(&strict);
    }

    let relaxed: Vec<(u8, u8, u8)> = pixels
        .iter()
        .copied()
        .filter(|pixel| {
            let (spread, brightness) = chroma(pixel);
            spread >= 8 && (20.0..=240.0).contains(&brightness)
        })
        .collect();
    if !relaxed.is_empty() {
        return mean(&relaxed);
    }

    mean(pixels)
}

/// The whole awk program for one pixel dump.
pub fn palette_from_dump(dump: &str) -> Result<Palette, ExtractError> {
    let mut pixels: Vec<(u8, u8, u8)> = Vec::new();
    for line in dump.split('\n') {
        if let Some(pixel) = parse_pixel_line(line) {
            pixels.push(pixel);
        }
    }
    if pixels.len() < 8 {
        return Err(ExtractError::NoPixels);
    }

    // ---- accent: the mean saturated colour, hue-matched onto #006FCC -------
    let (accent_red, accent_green, accent_blue) = accent_mean(&pixels);
    let (hue, saturation, _) = color::to_hsl_f64(accent_red, accent_green, accent_blue);
    let (matched_red, matched_green, matched_blue) = if saturation == 0.0 {
        (0.0, 0x6f as f64, 0xcc as f64)
    } else {
        color::from_hsl(hue, 1.0, 0.4)
    };

    // ---- how light the wallpaper is ----------------------------------------
    let mut luminance_sum = 0.0;
    for &(r, g, b) in &pixels {
        luminance_sum += color::relative_luminance(f64::from(r), f64::from(g), f64::from(b));
    }
    #[allow(clippy::cast_precision_loss)]
    let mean_luminance = luminance_sum / pixels.len() as f64;
    let light = mean_luminance > 0.5;

    // ---- tones: weighted k-means in Oklab ----------------------------------
    let count = pixels.len();
    let mut lightness = Vec::with_capacity(count);
    let mut axis_a = Vec::with_capacity(count);
    let mut axis_b = Vec::with_capacity(count);
    let mut weights = Vec::with_capacity(count);
    for &(r, g, b) in &pixels {
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let saturation = if max == 0 {
            0.0
        } else {
            f64::from(max - min) / f64::from(max)
        };
        weights.push(0.25 + saturation * 1.75);
        let (l, a, b_value) = color::to_lab(f64::from(r), f64::from(g), f64::from(b));
        lightness.push(l);
        axis_a.push(a);
        axis_b.push(b_value);
    }

    // Seeds are the lightness quantiles the reference takes after sorting its
    // points. The sort is stable, like the awk insertion sort over indices.
    let mut order: Vec<usize> = (0..count).collect();
    order.sort_by(|&left, &right| {
        lightness[left]
            .partial_cmp(&lightness[right])
            .expect("Oklab lightness is finite")
    });

    const K: usize = 4;
    let mut centers_l = [0.0f64; K];
    let mut centers_a = [0.0f64; K];
    let mut centers_b = [0.0f64; K];
    for center in 0..K {
        #[allow(clippy::cast_precision_loss)]
        let seed = (count as f64 * (center as f64 + 0.5) / K as f64) as usize;
        let pixel = order[seed];
        centers_l[center] = lightness[pixel];
        centers_a[center] = axis_a[pixel];
        centers_b[center] = axis_b[pixel];
    }

    for _ in 0..16 {
        let mut sums_l = [0.0f64; K];
        let mut sums_a = [0.0f64; K];
        let mut sums_b = [0.0f64; K];
        let mut sums_w = [0.0f64; K];
        for pixel in 0..count {
            let mut best = 0;
            let mut best_distance = f64::INFINITY;
            for center in 0..K {
                let dl = lightness[pixel] - centers_l[center];
                let da = axis_a[pixel] - centers_a[center];
                let db = axis_b[pixel] - centers_b[center];
                let distance = dl * dl + da * da + db * db;
                if distance < best_distance {
                    best_distance = distance;
                    best = center;
                }
            }
            sums_l[best] += lightness[pixel] * weights[pixel];
            sums_a[best] += axis_a[pixel] * weights[pixel];
            sums_b[best] += axis_b[pixel] * weights[pixel];
            sums_w[best] += weights[pixel];
        }
        for center in 0..K {
            if sums_w[center] > 0.0 {
                centers_l[center] = sums_l[center] / sums_w[center];
                centers_a[center] = sums_a[center] / sums_w[center];
                centers_b[center] = sums_b[center] / sums_w[center];
            }
        }
    }

    // Darkest to lightest, with the awk selection sort's exact swaps.
    for left in 0..K {
        let mut lowest = left;
        for candidate in (left + 1)..K {
            if centers_l[candidate] < centers_l[lowest] {
                lowest = candidate;
            }
        }
        if lowest != left {
            centers_l.swap(left, lowest);
            centers_a.swap(left, lowest);
            centers_b.swap(left, lowest);
        }
    }

    const CHROMA: f64 = 1.35;
    let (coal_red, coal_green, coal_blue) =
        color::from_lab(centers_l[0], centers_a[0] * CHROMA, centers_b[0] * CHROMA);
    let (surface_red, surface_green, surface_blue) =
        color::from_lab(centers_l[1], centers_a[1] * CHROMA, centers_b[1] * CHROMA);
    let (ink_red, ink_green, ink_blue) = color::from_lab(
        centers_l[K - 1],
        centers_a[K - 1] * CHROMA,
        centers_b[K - 1] * CHROMA,
    );

    // Readability clamp: from the lightest centre on a dark surface (or the
    // darkest on a light one), step toward that extreme until 4.5:1 is met.
    let white_contrast = color::contrast(
        255.0,
        255.0,
        255.0,
        surface_red,
        surface_green,
        surface_blue,
    );
    let black_contrast = color::contrast(0.0, 0.0, 0.0, surface_red, surface_green, surface_blue);
    let (base_red, base_green, base_blue, target_red, target_green, target_blue) =
        if white_contrast >= black_contrast {
            (ink_red, ink_green, ink_blue, 255.0, 255.0, 255.0)
        } else {
            (coal_red, coal_green, coal_blue, 0.0, 0.0, 0.0)
        };
    let mut step = 0.0;
    let (mut clamp_red, mut clamp_green, mut clamp_blue) = (base_red, base_green, base_blue);
    while step < 1.0
        && color::contrast(
            clamp_red,
            clamp_green,
            clamp_blue,
            surface_red,
            surface_green,
            surface_blue,
        ) < 4.5
    {
        step += 0.1;
        if step > 1.0 {
            step = 1.0;
        }
        clamp_red = base_red + (target_red - base_red) * step;
        clamp_green = base_green + (target_green - base_green) * step;
        clamp_blue = base_blue + (target_blue - base_blue) * step;
    }

    Ok(Palette {
        coal: Rgb {
            red: quantize(coal_red),
            green: quantize(coal_green),
            blue: quantize(coal_blue),
        },
        surface: Rgb {
            red: quantize(surface_red),
            green: quantize(surface_green),
            blue: quantize(surface_blue),
        },
        ink: Rgb {
            red: quantize(clamp_red),
            green: quantize(clamp_green),
            blue: quantize(clamp_blue),
        },
        accent: Rgb {
            red: quantize(matched_red),
            green: quantize(matched_green),
            blue: quantize(matched_blue),
        },
        light,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dump(pixels: &[(u8, u8, u8)]) -> String {
        let mut text = String::from("# ImageMagick pixel enumeration: 9,9,255,srgb\n");
        for (index, &(r, g, b)) in pixels.iter().enumerate() {
            text.push_str(&format!(
                "{index},0: ({r},{g},{b})  #{r:02X}{g:02X}{b:02X}  srgb({r},{g},{b})\n"
            ));
        }
        text
    }

    fn expect(pixels: &[(u8, u8, u8)]) -> Palette {
        palette_from_dump(&dump(pixels)).expect("palette")
    }

    // The expected values in this module were produced by the real
    // `theme-extract.awk` on the same pixel sequences.

    #[test]
    fn varied_pixels_match_the_awk_output() {
        let pixels = [
            (8, 16, 30),
            (40, 80, 140),
            (200, 180, 160),
            (250, 250, 250),
            (120, 10, 10),
            (10, 120, 10),
            (10, 10, 120),
            (128, 128, 128),
            (60, 30, 90),
        ];
        let palette = expect(&pixels);
        assert_eq!(palette.coal.hex(), "#1a1d70");
        assert_eq!(palette.surface.hex(), "#880000");
        assert_eq!(palette.ink.hex(), "#c5b7a8");
        assert_eq!(palette.accent.hex(), "#1400cc");
        assert!(!palette.light);
    }

    #[test]
    fn grey_pixels_keep_the_reference_accent() {
        let greys = [20u8, 40, 60, 80, 100, 140, 180, 220];
        let pixels: Vec<(u8, u8, u8)> = greys.iter().map(|&v| (v, v, v)).collect();
        let palette = expect(&pixels);
        assert_eq!(palette.coal.hex(), "#1e1e1e");
        assert_eq!(palette.surface.hex(), "#505050");
        assert_eq!(palette.ink.hex(), "#c8c8c8");
        assert_eq!(palette.accent.hex(), "#006fcc");
        assert!(!palette.light);
    }

    #[test]
    fn saturated_pixels_take_the_mean_hue() {
        let levels = [200u8, 180, 160, 140, 120, 100, 90, 80, 70, 60];
        let pixels: Vec<(u8, u8, u8)> = levels.iter().map(|&v| (v, v / 2, 20)).collect();
        let palette = expect(&pixels);
        assert_eq!(palette.coal.hex(), "#481b09");
        assert_eq!(palette.surface.hex(), "#632500");
        assert_eq!(palette.ink.hex(), "#dd9266");
        assert_eq!(palette.accent.hex(), "#cc5200");
        assert!(!palette.light);
    }

    #[test]
    fn a_light_wallpaper_is_detected_and_dark_ink_is_clamped() {
        let levels = [250u8, 245, 240, 235, 230, 225, 220, 215, 210, 205, 200, 255];
        let pixels: Vec<(u8, u8, u8)> = levels.iter().map(|&v| (v, v, v)).collect();
        let palette = expect(&pixels);
        assert_eq!(palette.coal.hex(), "#cdcdcd");
        assert_eq!(palette.surface.hex(), "#dcdcdc");
        assert_eq!(palette.ink.hex(), "#525252");
        assert_eq!(palette.accent.hex(), "#006fcc");
        assert!(palette.light);
    }

    #[test]
    fn the_accent_uses_the_second_relaxed_pass() {
        // Chroma 8 fails the strict pass (>= 10) and passes the relaxed one
        // (>= 8), so the accent is still the mean of all eight pixels.
        let pixels = [(100u8, 92u8, 92u8); 8];
        let palette = expect(&pixels);
        assert_eq!(palette.accent.hex(), "#cc0000");
    }

    #[test]
    fn fewer_than_eight_pixels_is_an_error() {
        let pixels: Vec<(u8, u8, u8)> = (0..7).map(|i| (i as u8 * 10, 0, 0)).collect();
        assert_eq!(
            palette_from_dump(&dump(&pixels)),
            Err(ExtractError::NoPixels)
        );
    }

    #[test]
    fn junk_lines_are_skipped_like_the_awk_pattern() {
        let mut text = String::from(
            "# ImageMagick pixel enumeration: 2,4,255,srgb\n\
             version: ImageMagick\n\
             x,0: (1,2,3)  #010203  srgb(1,2,3)\n\
             0,0: no hash here\n\
             1,0: (2,3,4)  #0203\n",
        );
        for value in [20u8, 40, 60, 80, 100, 140, 180, 220] {
            text.push_str(&format!(
                "{value},0: ({value},{value},{value})  #{value:02X}{value:02X}{value:02X}  srgb({value},{value},{value})\n\
                 trailing: not a pixel\n"
            ));
        }
        let palette = palette_from_dump(&text).expect("palette");
        assert_eq!(palette.coal.hex(), "#1e1e1e");
        assert_eq!(palette.accent.hex(), "#006fcc");
    }

    #[test]
    fn the_readability_clamp_reaches_four_point_five_to_one() {
        let levels = [10u8, 30, 60, 90, 120, 150, 180, 210];
        let pixels: Vec<(u8, u8, u8)> = levels.iter().map(|&v| (v, v / 3, v / 2)).collect();
        let palette = expect(&pixels);
        let ratio = color::contrast(
            f64::from(palette.ink.red),
            f64::from(palette.ink.green),
            f64::from(palette.ink.blue),
            f64::from(palette.surface.red),
            f64::from(palette.surface.green),
            f64::from(palette.surface.blue),
        );
        assert!(
            ratio >= 4.5 || ratio < 4.5 && palette.ink.hex() == "#ffffff",
            "ink {} on surface {} is {ratio}",
            palette.ink.hex(),
            palette.surface.hex()
        );
    }
}
