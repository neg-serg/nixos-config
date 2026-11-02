//! Dithering algorithms, copied one-to-one from `make_blizzard.py`.
//!
//! The error-diffusion variants deliberately keep the Python loop order and
//! float operations, because the kernels' rounding decides where the mask
//! boundary falls and therefore the look of the skull texture.

use crate::rng::Mt19937;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dither {
    Fs,
    Atkinson,
    Sierra,
    Stucki,
    Bayer,
    Noise,
    None,
}

impl Dither {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "fs" => Some(Self::Fs),
            "atkinson" => Some(Self::Atkinson),
            "sierra" => Some(Self::Sierra),
            "stucki" => Some(Self::Stucki),
            "bayer" => Some(Self::Bayer),
            "noise" => Some(Self::Noise),
            "none" => Some(Self::None),
            _ => None,
        }
    }
}

const FS: [(i32, i32, f64); 4] = [
    (1, 0, 7.0 / 16.0),
    (-1, 1, 3.0 / 16.0),
    (0, 1, 5.0 / 16.0),
    (1, 1, 1.0 / 16.0),
];

const ATKINSON: [(i32, i32, f64); 6] = [
    (1, 0, 1.0),
    (2, 0, 1.0),
    (-1, 1, 1.0),
    (0, 1, 1.0),
    (1, 1, 1.0),
    (0, 2, 1.0),
];

const SIERRA: [(i32, i32, f64); 10] = [
    (1, 0, 5.0 / 32.0),
    (2, 0, 3.0 / 32.0),
    (-2, 1, 2.0 / 32.0),
    (-1, 1, 4.0 / 32.0),
    (0, 1, 5.0 / 32.0),
    (1, 1, 4.0 / 32.0),
    (2, 1, 2.0 / 32.0),
    (-1, 2, 2.0 / 32.0),
    (0, 2, 3.0 / 32.0),
    (1, 2, 2.0 / 32.0),
];

const STUCKI: [(i32, i32, f64); 12] = [
    (1, 0, 8.0 / 42.0),
    (2, 0, 4.0 / 42.0),
    (-2, 1, 2.0 / 42.0),
    (-1, 1, 4.0 / 42.0),
    (0, 1, 8.0 / 42.0),
    (1, 1, 4.0 / 42.0),
    (2, 1, 2.0 / 42.0),
    (-2, 2, 1.0 / 42.0),
    (-1, 2, 2.0 / 42.0),
    (0, 2, 4.0 / 42.0),
    (1, 2, 2.0 / 42.0),
    (2, 2, 1.0 / 42.0),
];

fn diffuse(
    gray: &[f64],
    width: usize,
    height: usize,
    kernel: &[(i32, i32, f64)],
    divisor: f64,
) -> Vec<bool> {
    let mut buf = gray.to_vec();
    let mut out = vec![false; width * height];
    let clamp = |v: f64| v.clamp(0.0, 1.0);

    for y in 0..height {
        for x in 0..width {
            let idx = y * width + x;
            let old = buf[idx];
            let new = if old >= 0.5 { 1.0 } else { 0.0 };
            out[idx] = new != 0.0;
            let err = (old - new) / divisor;
            for &(dx, dy, weight) in kernel {
                let nx = x as i32 + dx;
                let ny = y as i32 + dy;
                if nx >= 0 && nx < width as i32 && ny >= 0 && ny < height as i32 {
                    let nidx = ny as usize * width + nx as usize;
                    buf[nidx] = clamp(buf[nidx] + err * weight);
                }
            }
        }
    }
    out
}

fn bayer(gray: &[f64], width: usize, height: usize, n: usize) -> Vec<bool> {
    const BASE: [[u8; 4]; 4] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    let mut out = vec![false; width * height];
    for y in 0..height {
        for x in 0..width {
            let threshold = (BASE[y % n][x % n] as f64 + 0.5) / (n * n) as f64;
            out[y * width + x] = gray[y * width + x] >= threshold;
        }
    }
    out
}

pub fn apply(dither: Dither, gray: &[f64], width: usize, height: usize) -> Vec<bool> {
    match dither {
        Dither::Fs => diffuse(gray, width, height, &FS, 1.0),
        Dither::Atkinson => diffuse(gray, width, height, &ATKINSON, 8.0),
        Dither::Sierra => diffuse(gray, width, height, &SIERRA, 1.0),
        Dither::Stucki => diffuse(gray, width, height, &STUCKI, 1.0),
        Dither::Bayer => bayer(gray, width, height, 4),
        Dither::Noise => {
            // `dither_noise` always seeds NumPy's legacy RandomState with 0.
            let mut rng = Mt19937::from_numpy_seed(0);
            gray.iter().map(|value| *value > rng.random()).collect()
        }
        Dither::None => gray.iter().map(|value| *value >= 0.5).collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bayer_is_deterministic() {
        let gray = vec![0.5; 16];
        let a = apply(Dither::Bayer, &gray, 4, 4);
        let b = apply(Dither::Bayer, &gray, 4, 4);
        assert_eq!(a, b);
        // The 0.5 threshold cuts the 4x4 Bayer matrix between entries 7 and 8.
        assert_eq!(a.iter().filter(|v| **v).count(), 8);
    }

    #[test]
    fn none_thresholds_at_half() {
        let gray = vec![0.49, 0.5, 0.51];
        assert_eq!(apply(Dither::None, &gray, 3, 1), vec![false, true, true]);
    }
}
