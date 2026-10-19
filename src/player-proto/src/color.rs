//! Colour science for the design tokens: sRGB, WCAG contrast, OKLab and CIEDE2000.
//!
//! The theme states its guarantees as numbers ("every text token clears 4.5:1 on every ground",
//! "two row states differ by at least 0.05 in OKLab"), so those numbers need an implementation
//! the tests can call. `tools/theme-audit/theme_audit.py` implements the same maths for the
//! longer report (and adds the dichromacy simulation); this module is the set the UI itself
//! needs, kept dependency-free and exact.
//!
//! Everything here works on sRGB triples in 0..1 unless a function says otherwise. Converting
//! to linear light happens inside each function, because every perceptual model below is
//! defined on linear light and getting that wrong is the classic way to produce a palette that
//! measures fine and looks wrong.

/// sRGB transfer function, encoded -> linear.
pub fn decode(c: f32) -> f32 {
    if c <= 0.04045 {
        c / 12.92
    } else {
        ((c + 0.055) / 1.055).powf(2.4)
    }
}

/// Linear -> sRGB encoded.
pub fn encode(c: f32) -> f32 {
    let c = c.clamp(0.0, 1.0);
    if c <= 0.003_130_8 {
        c * 12.92
    } else {
        1.055 * c.powf(1.0 / 2.4) - 0.055
    }
}

/// WCAG 2.1 relative luminance.
pub fn luminance(rgb: [f32; 4]) -> f32 {
    0.2126 * decode(rgb[0]) + 0.7152 * decode(rgb[1]) + 0.0722 * decode(rgb[2])
}

/// WCAG 2.1 contrast ratio, always >= 1 and order-independent.
pub fn contrast(a: [f32; 4], b: [f32; 4]) -> f32 {
    let la = luminance(a);
    let lb = luminance(b);
    let (hi, lo) = if la > lb { (la, lb) } else { (lb, la) };
    (hi + 0.05) / (lo + 0.05)
}

/// OKLab (Ottosson 2020): the exact matrices, not the "cube root of XYZ" approximation.
pub fn oklab(rgb: [f32; 4]) -> [f32; 3] {
    let (r, g, b) = (decode(rgb[0]), decode(rgb[1]), decode(rgb[2]));
    let l = 0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_99 * b;
    let m = 0.211_903_5 * r + 0.680_699_54 * g + 0.107_396_96 * b;
    let s = 0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b;
    let l = l.cbrt();
    let m = m.cbrt();
    let s = s.cbrt();
    [
        0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s,
        1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s,
    ]
}

/// OKLCh: lightness, chroma and hue (degrees) — the space where hue is a separate axis, so
/// "same hue, more light" and "same light, another hue" are two distinct moves.
pub fn oklch(rgb: [f32; 4]) -> [f32; 3] {
    let lab = oklab(rgb);
    [
        lab[0],
        (lab[1] * lab[1] + lab[2] * lab[2]).sqrt(),
        lab[2].atan2(lab[1]).to_degrees().rem_euclid(360.0),
    ]
}

/// Euclidean distance in OKLab. ~0.02 is a just-noticeable difference on a large patch,
/// ~0.05 on text; it is the measure the theme's separation guarantees are stated in.
pub fn delta_ok(a: [f32; 4], b: [f32; 4]) -> f32 {
    let (x, y) = (oklab(a), oklab(b));
    ((x[0] - y[0]).powi(2) + (x[1] - y[1]).powi(2) + (x[2] - y[2]).powi(2)).sqrt()
}

/// CIELAB with a D65 white point.
pub fn lab(rgb: [f32; 4]) -> [f32; 3] {
    let (r, g, b) = (decode(rgb[0]), decode(rgb[1]), decode(rgb[2]));
    let x = 0.412_456_4 * r + 0.357_576_1 * g + 0.180_437_5 * b;
    let y = 0.212_672_9 * r + 0.715_152_2 * g + 0.072_175 * b;
    let z = 0.019_333_9 * r + 0.119_192 * g + 0.950_304_1 * b;
    let f = |t: f32| {
        let knee = (6.0_f32 / 29.0).powi(3);
        if t > knee {
            t.cbrt()
        } else {
            t / (3.0 * (6.0_f32 / 29.0).powi(2)) + 4.0 / 29.0
        }
    };
    let (fx, fy, fz) = (f(x / 0.950_47), f(y), f(z / 1.088_83));
    [116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)]
}

/// CIEDE2000 between two CIELAB triples, kL = kC = kH = 1.
pub fn delta_e_2000(lab1: [f32; 3], lab2: [f32; 3]) -> f32 {
    let [l1, a1, b1] = lab1;
    let [l2, a2, b2] = lab2;
    let c1 = (a1 * a1 + b1 * b1).sqrt();
    let c2 = (a2 * a2 + b2 * b2).sqrt();
    let c_bar = (c1 + c2) / 2.0;
    let c_bar7 = c_bar.powi(7);
    let g = 0.5 * (1.0 - (c_bar7 / (c_bar7 + 25.0_f32.powi(7))).sqrt());
    let a1p = (1.0 + g) * a1;
    let a2p = (1.0 + g) * a2;
    let c1p = (a1p * a1p + b1 * b1).sqrt();
    let c2p = (a2p * a2p + b2 * b2).sqrt();
    let hue = |a: f32, b: f32| {
        if a == 0.0 && b == 0.0 {
            0.0
        } else {
            b.atan2(a).to_degrees().rem_euclid(360.0)
        }
    };
    let h1p = hue(a1p, b1);
    let h2p = hue(a2p, b2);

    let dlp = l2 - l1;
    let dcp = c2p - c1p;
    let dhp = if c1p * c2p == 0.0 {
        0.0
    } else {
        let diff = h2p - h1p;
        if diff > 180.0 {
            diff - 360.0
        } else if diff < -180.0 {
            diff + 360.0
        } else {
            diff
        }
    };
    let dhp_term = 2.0 * (c1p * c2p).sqrt() * (dhp / 2.0).to_radians().sin();

    let l_bar = (l1 + l2) / 2.0;
    let c_bar_p = (c1p + c2p) / 2.0;
    let h_bar = if c1p * c2p == 0.0 {
        h1p + h2p
    } else if (h1p - h2p).abs() > 180.0 {
        if h1p + h2p < 360.0 {
            (h1p + h2p + 360.0) / 2.0
        } else {
            (h1p + h2p - 360.0) / 2.0
        }
    } else {
        (h1p + h2p) / 2.0
    };

    let t = 1.0 - 0.17 * (h_bar - 30.0).to_radians().cos()
        + 0.24 * (2.0 * h_bar).to_radians().cos()
        + 0.32 * (3.0 * h_bar + 6.0).to_radians().cos()
        - 0.20 * (4.0 * h_bar - 63.0).to_radians().cos();
    let d_theta = 30.0 * (-((h_bar - 275.0) / 25.0).powi(2)).exp();
    let c_bar_p7 = c_bar_p.powi(7);
    let r_c = 2.0 * (c_bar_p7 / (c_bar_p7 + 25.0_f32.powi(7))).sqrt();
    let l_sq = (l_bar - 50.0).powi(2);
    let s_l = 1.0 + (0.015 * l_sq) / (20.0 + l_sq).sqrt();
    let s_c = 1.0 + 0.045 * c_bar_p;
    let s_h = 1.0 + 0.015 * c_bar_p * t;
    let r_t = -(2.0 * d_theta).to_radians().sin() * r_c;

    let tl = dlp / s_l;
    let tc = dcp / s_c;
    let th = dhp_term / s_h;
    (tl * tl + tc * tc + th * th + r_t * tc * th).sqrt()
}

/// CIEDE2000 between two sRGB colours.
pub fn delta_e_2000_rgb(a: [f32; 4], b: [f32; 4]) -> f32 {
    delta_e_2000(lab(a), lab(b))
}

/// sRGB triple to the `#rrggbb` an author writes in a theme comment.
pub fn hex(rgb: [f32; 4]) -> String {
    let channel = |c: f32| (c.clamp(0.0, 1.0) * 255.0).round() as u32;
    format!(
        "#{:02x}{:02x}{:02x}",
        channel(rgb[0]),
        channel(rgb[1]),
        channel(rgb[2])
    )
}

/// `#rrggbb` to an sRGB quad, alpha 1. Used by the theme tests and by anything that has to
/// take a colour from a config file or a command line.
pub fn parse_hex(text: &str) -> Option<[f32; 4]> {
    let s = text.trim().trim_start_matches('#');
    if s.len() != 6 {
        return None;
    }
    let channel = |i: usize| {
        u8::from_str_radix(&s[i..i + 2], 16)
            .ok()
            .map(|v| v as f32 / 255.0)
    };
    Some([channel(0)?, channel(2)?, channel(4)?, 1.0])
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(hexstr: &str) -> [f32; 4] {
        parse_hex(hexstr).expect("valid hex")
    }

    #[test]
    fn srgb_round_trips() {
        for v in [0.0, 0.0123, 0.5, 0.777, 1.0] {
            assert!(
                (encode(decode(v)) - v).abs() < 1e-6,
                "{v} did not round-trip"
            );
        }
    }

    #[test]
    fn contrast_matches_wcag_reference_values() {
        assert!((contrast(c("#000000"), c("#ffffff")) - 21.0).abs() < 1e-4);
        assert!((contrast(c("#777777"), c("#ffffff")) - 4.478).abs() < 0.01);
        assert!((contrast(c("#000000"), c("#808080")) - 5.319).abs() < 0.02);
        // Order must not matter.
        assert!(
            (contrast(c("#ffffff"), c("#000000")) - contrast(c("#000000"), c("#ffffff"))).abs()
                < 1e-6
        );
    }

    #[test]
    fn oklab_matches_published_reference_points() {
        let cases = [
            ("#ffffff", [1.0, 0.0, 0.0]),
            ("#000000", [0.0, 0.0, 0.0]),
            ("#ff0000", [0.6279, 0.2249, 0.1258]),
            ("#0000ff", [0.4520, -0.0324, -0.3115]),
            ("#00ff00", [0.8664, -0.2339, 0.1795]),
        ];
        for (hexstr, want) in cases {
            let got = oklab(c(hexstr));
            for i in 0..3 {
                assert!(
                    (got[i] - want[i]).abs() < 2e-3,
                    "{hexstr} channel {i}: got {}, want {}",
                    got[i],
                    want[i]
                );
            }
        }
    }

    #[test]
    fn ciede2000_matches_sharma_reference_data() {
        let cases: &[([f32; 3], [f32; 3], f32)] = &[
            ([50.0, 2.6772, -79.7751], [50.0, 0.0, -82.7485], 2.0425),
            ([50.0, 3.1571, -77.2803], [50.0, 0.0, -82.7485], 2.8615),
            ([50.0, 2.8361, -74.02], [50.0, 0.0, -82.7485], 3.4412),
            ([50.0, -1.3802, -84.2814], [50.0, 0.0, -82.7485], 1.0),
            ([50.0, 0.0, 0.0], [50.0, -1.0, 2.0], 2.3669),
            ([50.0, 2.49, -0.001], [50.0, -2.49, 0.0009], 7.1792),
            ([50.0, 2.5, 0.0], [73.0, 25.0, -18.0], 27.1492),
            (
                [22.7233, 20.0904, -46.694],
                [23.0331, 14.973, -42.5619],
                2.0373,
            ),
            (
                [90.9257, -0.5406, -0.9208],
                [88.6381, -0.8985, -0.7239],
                1.5381,
            ),
            ([2.0776, 0.0795, -1.135], [0.9033, -0.0636, -0.5514], 0.9082),
        ];
        for (a, b, want) in cases {
            let got = delta_e_2000(*a, *b);
            assert!(
                (got - want).abs() < 1e-4,
                "dE2000 {a:?} vs {b:?}: got {got}, want {want}"
            );
        }
    }

    #[test]
    fn hex_parsing_round_trips() {
        for hexstr in ["#000000", "#d1e5ff", "#272727", "#0d1824"] {
            assert_eq!(hex(c(hexstr)), hexstr);
        }
        assert!(parse_hex("nope").is_none());
        assert!(parse_hex("#abc").is_none());
    }

    #[test]
    fn oklch_hue_is_a_separate_axis() {
        let (l, ch, h) = {
            let [l, ch, h] = oklch(c("#367cb0"));
            (l, ch, h)
        };
        assert!(
            (200.0..270.0).contains(&h),
            "blue should have a blue-ish hue, got {h}"
        );
        assert!(ch > 0.05, "the accent is not grey, got chroma {ch}");
        assert!(l > 0.4 && l < 0.7, "accent lightness out of range: {l}");
    }
}
