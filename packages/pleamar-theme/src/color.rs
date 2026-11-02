//! The colour primitives shared by the accented mean and the Oklab k-means.
//!
//! Every formula is the one `theme-extract.awk` transcribed from the reference
//! Quickshell code, including its constants and its clamping points. The awk
//! program worked in doubles; so does this module, and the functions take and
//! return doubles so the rounding to 8-bit channels happens once, in
//! [`crate::extract`], exactly where awk's `hex()` did it.

/// sRGB 8-bit channel to linear light, the 0.04045 threshold.
pub fn srgb2lin(channel: f64) -> f64 {
    let value = channel / 255.0;
    if value <= 0.04045 {
        value / 12.92
    } else {
        ((value + 0.055) / 1.055).powf(2.4)
    }
}

/// Linear light back to an 8-bit channel value.
///
/// The clamp happens after the transfer function, which is what the awk
/// program did (`BackgroundImage.qml` clamps before `linearToSrgb`; same ends).
pub fn lin2srgb(value: f64) -> f64 {
    let encoded = if value <= 0.003_130_8 {
        value * 12.92
    } else {
        1.055 * value.powf(1.0 / 2.4) - 0.055
    };
    encoded.clamp(0.0, 1.0) * 255.0
}

/// Forward Oklab transform: sRGB 8-bit channels to `(L, a, b)`.
pub fn to_lab(red: f64, green: f64, blue: f64) -> (f64, f64, f64) {
    let lr = srgb2lin(red);
    let lg = srgb2lin(green);
    let lb = srgb2lin(blue);
    let l = (0.412_221_470_8 * lr + 0.536_332_536_3 * lg + 0.051_445_992_9 * lb).powf(1.0 / 3.0);
    let m = (0.211_903_498_2 * lr + 0.680_699_545_1 * lg + 0.107_396_956_6 * lb).powf(1.0 / 3.0);
    let s = (0.088_302_461_9 * lr + 0.281_718_837_6 * lg + 0.629_978_700_5 * lb).powf(1.0 / 3.0);
    (
        0.210_454_255_3 * l + 0.793_617_785_0 * m - 0.004_072_046_8 * s,
        1.977_998_495_1 * l - 2.428_592_205_0 * m + 0.450_593_709_9 * s,
        0.025_904_037_1 * l + 0.782_771_766_2 * m - 0.808_675_766_0 * s,
    )
}

/// Inverse Oklab transform: `(L, a, b)` to linear-light sRGB expressed as
/// 8-bit channel values (already clamped by [`lin2srgb`]).
pub fn from_lab(l_value: f64, a_value: f64, b_value: f64) -> (f64, f64, f64) {
    let l = (l_value + 0.396_337_777_4 * a_value + 0.215_803_757_3 * b_value).powf(3.0);
    let m = (l_value - 0.105_561_345_8 * a_value - 0.063_854_172_8 * b_value).powf(3.0);
    let s = (l_value - 0.089_484_177_5 * a_value - 1.291_485_548_0 * b_value).powf(3.0);
    (
        lin2srgb(4.076_741_662_1 * l - 3.307_711_591_3 * m + 0.230_969_929_2 * s),
        lin2srgb(-1.268_438_004_6 * l + 2.609_757_401_1 * m - 0.341_319_396_5 * s),
        lin2srgb(-0.004_196_086_3 * l - 0.703_418_614_7 * m + 1.707_614_701_0 * s),
    )
}

/// sRGB channels (already in 0..255, fractional allowed) to HSL; the hue is in
/// 0..1, saturation and lightness in 0..1, and a grey pixel comes back as hue
/// 0, saturation 0. The accent mean feeds fractional channels here, exactly as
/// the awk program did.
pub fn to_hsl_f64(red: f64, green: f64, blue: f64) -> (f64, f64, f64) {
    let r = red / 255.0;
    let g = green / 255.0;
    let b = blue / 255.0;
    let mut max = if r > g { r } else { g };
    if b > max {
        max = b;
    }
    let mut min = if r < g { r } else { g };
    if b < min {
        min = b;
    }
    let lightness = (max + min) / 2.0;
    let mut hue = 0.0;
    let mut saturation = 0.0;
    if max != min {
        let delta = max - min;
        saturation = if lightness > 0.5 {
            delta / (2.0 - max - min)
        } else {
            delta / (max + min)
        };
        if max == r {
            hue = (g - b) / delta + if g < b { 6.0 } else { 0.0 };
        } else if max == g {
            hue = (b - r) / delta + 2.0;
        } else {
            hue = (r - g) / delta + 4.0;
        }
        hue /= 6.0;
    }
    (hue, saturation, lightness)
}

/// Integer-channel convenience wrapper around [`to_hsl_f64`].
pub fn to_hsl(red: u8, green: u8, blue: u8) -> (f64, f64, f64) {
    to_hsl_f64(f64::from(red), f64::from(green), f64::from(blue))
}

fn hue_to_rgb(p: f64, q: f64, mut t: f64) -> f64 {
    if t < 0.0 {
        t += 1.0;
    }
    if t > 1.0 {
        t -= 1.0;
    }
    if t < 1.0 / 6.0 {
        p + (q - p) * 6.0 * t
    } else if t < 1.0 / 2.0 {
        q
    } else if t < 2.0 / 3.0 {
        p + (q - p) * (2.0 / 3.0 - t) * 6.0
    } else {
        p
    }
}

/// HSL back to 8-bit channel values (0..255, not yet rounded).
pub fn from_hsl(mut hue: f64, saturation: f64, lightness: f64) -> (f64, f64, f64) {
    hue -= hue.trunc();
    if hue < 0.0 {
        hue += 1.0;
    }
    if saturation == 0.0 {
        let grey = lightness * 255.0;
        return (grey, grey, grey);
    }
    let q = if lightness < 0.5 {
        lightness * (1.0 + saturation)
    } else {
        lightness + saturation - lightness * saturation
    };
    let p = 2.0 * lightness - q;
    (
        hue_to_rgb(p, q, hue + 1.0 / 3.0) * 255.0,
        hue_to_rgb(p, q, hue) * 255.0,
        hue_to_rgb(p, q, hue - 1.0 / 3.0) * 255.0,
    )
}

/// WCAG relative luminance: the readability clamp's metric.
pub fn relative_luminance(red: f64, green: f64, blue: f64) -> f64 {
    0.2126 * srgb2lin(red) + 0.7152 * srgb2lin(green) + 0.0722 * srgb2lin(blue)
}

/// WCAG contrast ratio of two colours given as 8-bit channel values.
pub fn contrast(red1: f64, green1: f64, blue1: f64, red2: f64, green2: f64, blue2: f64) -> f64 {
    let first = relative_luminance(red1, green1, blue1) + 0.05;
    let second = relative_luminance(red2, green2, blue2) + 0.05;
    if first > second {
        first / second
    } else {
        second / first
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The awk program rounds only when printing; these tests pin the
    /// intermediate doubles tightly enough to catch a constant changed by one
    /// decimal place.
    fn close(actual: f64, expected: f64) {
        assert!(
            (actual - expected).abs() < 1e-12,
            "got {actual:.17}, want {expected:.17}"
        );
    }

    #[test]
    fn hsl_matches_the_reference_values() {
        let (h, s, l) = to_hsl(0, 111, 204);
        close(h, 0.575_980_392_156_862_8);
        close(s, 1.0);
        close(l, 0.4);

        let (h, s, l) = to_hsl(255, 0, 0);
        close(h, 0.0);
        close(s, 1.0);
        close(l, 0.5);

        let (h, s, l) = to_hsl(128, 128, 128);
        close(h, 0.0);
        close(s, 0.0);
        close(l, 128.0 / 255.0);
    }

    #[test]
    fn hsl_round_trip_keeps_the_hue() {
        for pixel in [
            (0u8, 111u8, 204u8),
            (255, 0, 0),
            (10, 120, 10),
            (60, 30, 90),
        ] {
            let (hue, _, _) = to_hsl(pixel.0, pixel.1, pixel.2);
            let (r, g, b) = from_hsl(hue, 1.0, 0.4);
            let (again, _, _) = to_hsl((r + 0.5) as u8, (g + 0.5) as u8, (b + 0.5) as u8);
            close(again, hue);
        }
    }

    #[test]
    fn wcag_values_match_the_awk_formulas() {
        close(
            relative_luminance(203.0, 214.0, 229.0),
            0.664_467_874_610_465_4,
        );
        close(
            relative_luminance(246.0, 243.0, 248.0),
            0.904_713_253_772_487_7,
        );
        close(
            contrast(203.0, 214.0, 229.0, 36.0, 42.0, 53.0),
            9.803_294_871_759_558,
        );
        close(
            contrast(27.0, 33.0, 39.0, 246.0, 243.0, 248.0),
            14.762_371_295_432_517,
        );
        close(
            contrast(82.0, 82.0, 82.0, 220.0, 220.0, 220.0),
            5.698_132_814_638_215,
        );
    }

    #[test]
    fn oklab_round_trip_is_linear_across_the_channel_range() {
        for red in (0..=255).step_by(17) {
            for green in (0..=255).step_by(51) {
                for blue in (0..=255).step_by(85) {
                    let (l, a, b) = to_lab(f64::from(red), f64::from(green), f64::from(blue));
                    let (r, g, bl) = from_lab(l, a, b);
                    assert!((r - f64::from(red)).abs() <= 1.0, "red {red} -> {r}");
                    assert!((g - f64::from(green)).abs() <= 1.0, "green {green} -> {g}");
                    assert!((bl - f64::from(blue)).abs() <= 1.0, "blue {blue} -> {bl}");
                }
            }
        }
    }
}
