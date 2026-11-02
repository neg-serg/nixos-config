//! Palettes, gradient construction, palette colouring and the optional
//! post-shader. Mirrors the PALETTES table, `build_gradient`, `colormap` and
//! `apply_shader` from the Python generator.

pub type Stop = (f64, [u8; 3]);

pub const PALETTE_NAMES: [&str; 3] = ["ash", "ember", "ice"];

pub fn palette(name: &str) -> Vec<Stop> {
    match name {
        "ash" => vec![
            (0.0, [6, 7, 9]),
            (0.4, [60, 68, 82]),
            (0.7, [130, 145, 165]),
            (0.9, [205, 216, 230]),
            (1.0, [246, 250, 255]),
        ],
        "ember" => vec![
            (0.0, [8, 4, 5]),
            (0.35, [120, 22, 10]),
            (0.62, [205, 68, 16]),
            (0.85, [244, 130, 42]),
            (1.0, [255, 216, 155]),
        ],
        "ice" => vec![
            (0.0, [6, 10, 16]),
            (0.35, [20, 50, 74]),
            (0.62, [40, 95, 130]),
            (0.85, [80, 160, 200]),
            (1.0, [200, 240, 255]),
        ],
        _ => unreachable!("palette name was validated by the CLI"),
    }
}

fn hex_rgb(value: &str) -> Result<[u8; 3], String> {
    let s = value.trim_start_matches('#');
    if s.len() < 6 {
        return Err(format!("invalid color {value:?}: expected #RRGGBB"));
    }
    let mut out = [0u8; 3];
    for (i, channel) in out.iter_mut().enumerate() {
        let pair = &s[i * 2..i * 2 + 2];
        *channel = u8::from_str_radix(pair, 16)
            .map_err(|_| format!("invalid color {value:?}: expected #RRGGBB"))?;
    }
    Ok(out)
}

/// `build_gradient`: five stops dark to bright, mixed toward white above 0.6.
pub fn build_gradient(value: &str) -> Result<Vec<Stop>, String> {
    let [r, g, b] = hex_rgb(value)?;
    let mut out = Vec::with_capacity(5);
    for f in [0.0f64, 0.35, 0.62, 0.85, 1.0] {
        let wt = (f - 0.6).max(0.0) * 0.55;
        let color = [
            (r as f64 * f + 60.0 * wt).min(255.0) as u8,
            (g as f64 * f + 60.0 * wt).min(255.0) as u8,
            (b as f64 * f + 60.0 * wt).min(255.0) as u8,
        ];
        out.push((f, color));
    }
    Ok(out)
}

fn interp(x: f64, stops: &[Stop], channel: usize) -> f64 {
    if x <= stops[0].0 {
        return stops[0].1[channel] as f64;
    }
    for pair in stops.windows(2) {
        let (x0, c0) = pair[0];
        let (x1, c1) = pair[1];
        if x <= x1 {
            let y0 = c0[channel] as f64;
            let y1 = c1[channel] as f64;
            let slope = (y1 - y0) / (x1 - x0);
            return slope * (x - x0) + y0;
        }
    }
    stops[stops.len() - 1].1[channel] as f64
}

/// `colormap`: paint the dithered mask with the gradient, black-ish background.
pub fn colormap(mask: &[bool], norm: &[f64], stops: &[Stop]) -> Vec<u8> {
    // NumPy builds the background in float32: stop[0] * 0.22, then truncates.
    let bg = stops[0].1.map(|c| (c as f32 * 0.22f32) as u8);
    let mut out = Vec::with_capacity(norm.len() * 3);
    for (i, &pixel) in norm.iter().enumerate() {
        if mask[i] {
            let x = pixel.clamp(0.0, 1.0);
            for channel in 0..3 {
                // NumPy stores the interpolation into a float32 buffer before
                // the uint8 cast, so round through f32 first.
                out.push((interp(x, stops, channel) as f32) as u8);
            }
        } else {
            out.extend_from_slice(&bg);
        }
    }
    out
}

/// `apply_shader` on an RGB buffer: optional inversion and a 14 px chromatic
/// split (`np.roll` semantics, i.e. wrapping at the edges).
pub fn apply_shader(rgb: &mut [u8], width: usize, height: usize, shader: &str) {
    if shader.is_empty() || shader == "none" {
        return;
    }
    let invert = shader.contains("invert");
    let shift_rgb = shader.contains("rgb");
    if invert {
        for value in rgb.iter_mut() {
            *value = 255 - *value;
        }
    }
    if shift_rgb {
        // np.roll with shift 14: R moves right, B moves left, wrapping.
        let shift = 14 % width;
        let mut row = vec![0u8; width * 3];
        for y in 0..height {
            let start = y * width * 3;
            row.copy_from_slice(&rgb[start..start + width * 3]);
            for x in 0..width {
                let src_r = (x + width - shift) % width;
                let src_b = (x + shift) % width;
                rgb[start + x * 3] = row[src_r * 3];
                rgb[start + x * 3 + 2] = row[src_b * 3 + 2];
            }
        }
    }
}

/// The per-frame "breathing" lookup table: gamma pulse plus a slight gain.
/// Keeps 0 black, pulses mids/highs exactly like the Python `im.point` LUT.
pub fn breathing_lut(phase: f64) -> [u8; 256] {
    let b = 1.0 + 0.05 * (2.0 * std::f64::consts::PI * phase).sin();
    let g = 1.0 + 0.14 * (2.0 * std::f64::consts::PI * phase * 2.0 + 0.6).sin();
    let mut lut = [0u8; 256];
    for (v, slot) in lut.iter_mut().enumerate() {
        let mut x = v as f64 / 255.0;
        x = x.clamp(0.0, 1.0);
        x = x.powf(1.0 / g);
        x = x.min(1.0) * b;
        *slot = (x * 255.0).clamp(0.0, 255.0) as u8;
    }
    lut
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gradient_matches_python_example() {
        let stops = build_gradient("#804020").unwrap();
        assert_eq!(stops[0], (0.0, [0, 0, 0]));
        assert_eq!(stops[4], (1.0, [141, 77, 45]));
    }

    #[test]
    fn shader_inverts_and_splits() {
        // width 8 -> shift 6: R[x] = in[(x+2)%8], B[x] = in[(x+6)%8].
        let mut rgb: Vec<u8> = (0..8u8)
            .flat_map(|x| [x * 10 + 1, 100, x * 10 + 3])
            .collect();
        apply_shader(&mut rgb, 8, 1, "rgb");
        // R[x] = R[(x + 2) % 8]
        assert_eq!(rgb[0], 21);
        assert_eq!(rgb[2 * 3], 41);
        // B[x] = B[(x + 6) % 8]
        assert_eq!(rgb[2 * 3 + 2], 3);
        assert_eq!(rgb[7 * 3 + 2], 53);
    }

    #[test]
    fn breathing_lut_keeps_black() {
        assert_eq!(breathing_lut(0.0)[0], 0);
        assert_eq!(breathing_lut(0.3)[0], 0);
    }
}
