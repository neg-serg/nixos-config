//! Measure the nixie tubes on a screenshot: the numbers the tubes are judged by.
//!
//! Port of `scripts/dev/nixie-metrics.py`. The look of a tube cannot be reviewed
//! in a chat, so this measures what a photo of a real one measures: how wide the
//! lit wire is, how fast its gas falls off, how much light the glass itself adds,
//! whether the anode mesh is there and how many unlit cathodes can be seen.
//! Thresholds are the acceptance criteria (A1..A7) in
//! docs/howto/designs/nixie-lamps-plan.xml.
//!
//! usage: nixie-metrics SHOT.png [--mode digits|clock] [--check]

use std::process::ExitCode;

const LIMITS: Limits = Limits {
    wire_white_px: 8,      // A2: the white-hot zone of the lit wire, device px
    wire_hot_px: 16,       // A2: R > 200
    glass_mid_ratio: 0.40, // A3: the unlit tube is darker than bare glass
    cathodes_min: 1,       // A6: the wires are thin and low-contrast, a weak proxy
    cage_contrast: 0.03,   // A5
};

struct Limits {
    wire_white_px: i64,
    wire_hot_px: i64,
    glass_mid_ratio: f64,
    cathodes_min: i64,
    cage_contrast: f64,
}

struct Shot {
    width: usize,
    height: usize,
    pixels: Vec<[u8; 3]>,
}

impl Shot {
    fn at(&self, x: usize, y: usize) -> [u8; 3] {
        self.pixels[y * self.width + x]
    }

    fn warm(&self, x: usize, y: usize) -> bool {
        let [r, _, b] = self.at(x, y);
        r > 110 && (r as i32 - b as i32) > 40
    }
}

/// Python slice bounds, including the negative-index wrap numpy performs.
fn slice_bounds(start: isize, end: isize, len: usize) -> (usize, usize) {
    let n = len as isize;
    let mut s = if start < 0 {
        (n + start).max(0)
    } else {
        start.min(n)
    };
    let e = if end < 0 {
        (n + end).max(0)
    } else {
        end.min(n)
    };
    if e < s {
        s = e;
    }
    (s as usize, e as usize)
}

/// Contiguous `true` runs as `(start, width)`, as the Python `runs()` helper.
fn runs(mask: &[bool]) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < mask.len() {
        if mask[i] {
            let mut j = i;
            while j + 1 < mask.len() && mask[j + 1] {
                j += 1;
            }
            out.push((i, j - i + 1));
            i = j + 1;
        } else {
            i += 1;
        }
    }
    out
}

fn median(values: &mut [f64]) -> f64 {
    if values.is_empty() {
        return f64::NAN;
    }
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = values.len();
    if n % 2 == 1 {
        values[n / 2]
    } else {
        (values[n / 2 - 1] + values[n / 2]) / 2.0
    }
}

fn mean(values: &[f64]) -> f64 {
    if values.is_empty() {
        return f64::NAN;
    }
    values.iter().sum::<f64>() / values.len() as f64
}

/// Column clusters of warm pixels — one per lit tube.
fn tubes(shot: &Shot) -> Vec<(usize, usize)> {
    let mut cols = vec![0i64; shot.width];
    for y in 0..shot.height {
        for x in 0..shot.width {
            if shot.warm(x, y) {
                cols[x] += 1;
            }
        }
    }
    let mut raw: Vec<(usize, usize)> = Vec::new();
    let mut i = 0;
    while i < cols.len() {
        if cols[i] > 3 {
            let mut j = i;
            while j + 1 < cols.len() && cols[j + 1] > 3 {
                j += 1;
            }
            if j - i > 12 {
                raw.push((i, j));
            }
            i = j + 1;
        } else {
            i += 1;
        }
    }

    // A numeral can break into two column runs (the mast and its flag): glue the
    // runs that sit closer than half a tube together.
    let mut widths: Vec<f64> = raw.iter().map(|(s, e)| (e - s) as f64).collect();
    if widths.is_empty() {
        widths.push(1.0);
    }
    let gap = 0.5 * median(&mut widths);
    let mut clusters: Vec<(usize, usize)> = Vec::new();
    for (s, e) in raw {
        if let Some(last) = clusters.last_mut() {
            if (s as f64) - (last.1 as f64) < gap {
                last.1 = e;
                continue;
            }
        }
        clusters.push((s, e));
    }
    clusters
}

struct Measured {
    id: String,
    bbox: (usize, usize, usize, usize),
    wire_white_px: i64,
    wire_hot_px: i64,
    halo_half_px: Option<i64>,
    glass_mid_ratio: Option<f64>,
    glass_own_light: Option<f64>,
    cage_contrast: Option<f64>,
    cathodes_min: Option<i64>,
}

fn measure(
    shot: &Shot,
    x0: usize,
    x1: usize,
    label: &str,
    yband: Option<(usize, usize)>,
) -> Measured {
    let warm_rows: Vec<usize> = (0..shot.height)
        .filter(|&y| (x0..x1).any(|x| shot.warm(x, y)))
        .collect();
    let (y0, y1) = match yband {
        Some(band) => band,
        None => (
            *warm_rows.iter().min().unwrap(),
            *warm_rows.iter().max().unwrap(),
        ),
    };
    let ymid = (y0 + y1) / 2;
    let mut measured = Measured {
        id: label.to_string(),
        bbox: (x0, x1, y0, y1),
        wire_white_px: 0,
        wire_hot_px: 0,
        halo_half_px: None,
        glass_mid_ratio: None,
        glass_own_light: None,
        cage_contrast: None,
        cathodes_min: None,
    };

    // The lit wire and its gas, on the row through the middle of the numeral.
    let (xs, xe) = slice_bounds(x0 as isize - 20, x1 as isize + 20, shot.width);
    let rows: Vec<usize> = (y0.max(1)..y1.min(shot.height.saturating_sub(1))).collect();
    let mut white: Vec<f64> = Vec::new();
    let mut hotw: Vec<f64> = Vec::new();
    for &y in &rows {
        let mut white_mask = Vec::new();
        let mut hot_mask = Vec::new();
        for x in xs..xe {
            let r = shot.at(x, y)[0];
            white_mask.push(r > 240);
            hot_mask.push(r > 200);
        }
        let w = runs(&white_mask)
            .into_iter()
            .map(|(_, w)| w)
            .max()
            .unwrap_or(0);
        white.push(w as f64);
        let h = runs(&hot_mask)
            .into_iter()
            .map(|(_, w)| w)
            .max()
            .unwrap_or(0);
        hotw.push(h as f64);
    }
    measured.wire_white_px = median(&mut white) as i64;
    measured.wire_hot_px = median(&mut hotw) as i64;

    let row: Vec<f64> = (xs..xe).map(|x| shot.at(x, ymid)[0] as f64).collect();
    let peak = row
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.partial_cmp(b.1).unwrap())
        .map(|(i, _)| i)
        .unwrap_or(0);
    if peak > 0 && peak < row.len() - 1 {
        let half = row[peak] / 2.0;
        let mut i = peak;
        while i > 0 && row[i] > half {
            i -= 1;
        }
        let left = peak - i;
        let mut i = peak;
        while i < row.len() - 1 && row[i] > half {
            i += 1;
        }
        measured.halo_half_px = Some(left.max(i - peak) as i64);
        let cx = (x0 + x1) / 2;
        let (bs, be) = slice_bounds(y0 as isize - 40, (y0 as isize - 12).max(1), shot.height);
        let band_rows: Vec<usize> = (bs..be).collect();
        let lum = |x: usize, y: usize| {
            let [r, g, b] = shot.at(x, y);
            r as f64 * 0.3 + g as f64 * 0.6 + b as f64 * 0.1
        };
        let (is, ie) = slice_bounds(cx as isize - 10, cx as isize + 10, shot.width);
        let inside = mean(
            &band_rows
                .iter()
                .flat_map(|&y| (is..ie).map(move |x| lum(x, y)))
                .collect::<Vec<_>>(),
        );
        let (os1, oe1) = slice_bounds(
            (cx as isize - 130).max(0),
            (cx as isize - 90).max(1),
            shot.width,
        );
        let (os2, oe2) = slice_bounds(cx as isize + 90, cx as isize + 130, shot.width);
        let mut outside_values: Vec<f64> = Vec::new();
        for &y in &band_rows {
            outside_values.extend((os1..oe1).map(|x| lum(x, y)));
            outside_values.extend((os2..oe2).map(|x| lum(x, y)));
        }
        let outside = mean(&outside_values);
        measured.glass_mid_ratio = Some(inside / outside.max(0.01) - 1.0);
        measured.glass_own_light = Some(inside / row[peak].max(1.0));

        let (ws, we) = slice_bounds(y0 as isize + 10, y1 as isize - 10, shot.height);
        let (cs, ce) = slice_bounds(cx as isize - 18, cx as isize + 18, shot.width);
        let win_rows: Vec<usize> = (ws..we).collect();
        let mut win: Vec<Vec<f64>> = Vec::new();
        for &y in &win_rows {
            win.push((cs..ce).map(|x| lum(x, y)).collect());
        }
        if !win.is_empty() && !win[0].is_empty() {
            let flat: Vec<f64> = win.iter().flat_map(|row| row.iter().copied()).collect();
            let win_mean = mean(&flat);
            let mut dx: Vec<f64> = Vec::new();
            for row in &win {
                for pair in row.windows(2) {
                    dx.push((pair[1] - pair[0]).abs());
                }
            }
            measured.cage_contrast = Some(median(&mut dx) / win_mean.max(0.01));
            let width = win[0].len();
            let mut profile = Vec::with_capacity(width);
            for x in 0..width {
                let column: Vec<f64> = win.iter().map(|row| row[x]).collect();
                profile.push(mean(&column));
            }
            let profile_mean = mean(&profile);
            let mask: Vec<bool> = profile.iter().map(|&v| v > profile_mean * 1.06).collect();
            measured.cathodes_min = Some(runs(&mask).len() as i64);
        }
    }
    measured
}

/// A7: 7 has its mass in the top half, 2 has a bar across the bottom.
fn orientation(shot: &Shot, x0: usize, x1: usize, digit: usize) -> Option<String> {
    let mut ys: Vec<usize> = Vec::new();
    let mut xs: Vec<usize> = Vec::new();
    for y in 0..shot.height {
        for x in x0..x1 {
            if shot.warm(x, y) {
                ys.push(y);
                xs.push(x);
            }
        }
    }
    if ys.is_empty() {
        return None;
    }
    let y0 = *ys.iter().min().unwrap();
    let y1 = *ys.iter().max().unwrap();
    let mid = (y0 + y1) as f64 / 2.0;
    match digit {
        7 => Some(
            if (ys.iter().sum::<usize>() as f64 / ys.len() as f64) < mid {
                "pass".to_string()
            } else {
                "FAIL (mass below the middle)".to_string()
            },
        ),
        2 => {
            let start = (y1 as f64 - 0.2 * (y1 - y0) as f64) as usize;
            let mut band = vec![false; x1 - x0];
            for (index, x) in (x0..x1).enumerate() {
                band[index] = (start..shot.height).any(|y| shot.warm(x, y));
            }
            let widths: Vec<usize> = runs(&band).into_iter().map(|(_, w)| w).collect();
            let need = 0.45 * (xs.iter().max().unwrap() - xs.iter().min().unwrap() + 1) as f64;
            let max_width = widths.iter().copied().max().unwrap_or(0);
            Some(if max_width as f64 >= need {
                "pass".to_string()
            } else {
                format!("FAIL (no bar, max {max_width} < {need:.0})")
            })
        }
        _ => Some("-".to_string()),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(path) = args.iter().find(|a| !a.starts_with('-')).cloned() else {
        eprintln!("usage: nixie-metrics SHOT.png [--mode digits|clock] [--check]");
        return ExitCode::from(2);
    };
    let mut mode = "clock".to_string();
    if let Some(index) = args.iter().position(|a| a == "--mode") {
        if let Some(value) = args.get(index + 1) {
            mode = value.clone();
        }
    }
    let check = args.iter().any(|a| a == "--check");

    let image = match image::open(&path) {
        Ok(image) => image.to_rgb8(),
        Err(error) => {
            eprintln!("nixie-metrics: {path}: {error}");
            return ExitCode::from(2);
        }
    };
    let shot = Shot {
        width: image.width() as usize,
        height: image.height() as usize,
        pixels: image.pixels().map(|p| [p[0], p[1], p[2]]).collect(),
    };
    let clusters = tubes(&shot);
    if clusters.is_empty() {
        println!("no lit tube found in the shot");
        return ExitCode::from(2);
    }
    println!("{path}: {} tube(s), mode={mode}", clusters.len());

    let mut bad: Vec<String> = Vec::new();
    // The last tube of the digits harness is unlit. It is the only place where
    // the glass, the anode mesh and the cathode stack can be measured without
    // the discharge drowning them: measure those there, and only the wire on
    // lit tubes.
    let unlit = mode == "digits" && clusters.len() > 10;
    let lit: &[(usize, usize)] = if unlit {
        &clusters[..clusters.len() - 1]
    } else {
        &clusters
    };
    let mut boxes: Vec<(usize, usize)> = Vec::new();
    for (index, &(x0, x1)) in lit.iter().enumerate() {
        let measured = measure(&shot, x0, x1, &format!("tube{index}"), None);
        boxes.push((measured.bbox.2, measured.bbox.3));
        let halo = measured
            .halo_half_px
            .map(|v| v.to_string())
            .unwrap_or_else(|| "?".to_string());
        println!(
            "  {}: wire white {}px hot {}px | halo half {}px",
            measured.id, measured.wire_white_px, measured.wire_hot_px, halo
        );
        if check {
            if measured.wire_white_px > LIMITS.wire_white_px {
                bad.push(format!(
                    "{}: wire white {} > {}",
                    measured.id, measured.wire_white_px, LIMITS.wire_white_px
                ));
            }
            if measured.wire_hot_px > LIMITS.wire_hot_px {
                bad.push(format!(
                    "{}: wire hot {} > {}",
                    measured.id, measured.wire_hot_px, LIMITS.wire_hot_px
                ));
            }
        }
    }
    if unlit {
        let (x0, x1) = clusters[clusters.len() - 1];
        let yband = if boxes.is_empty() {
            None
        } else {
            let mut y0s: Vec<f64> = boxes.iter().map(|b| b.0 as f64).collect();
            let mut y1s: Vec<f64> = boxes.iter().map(|b| b.1 as f64).collect();
            Some((median(&mut y0s) as usize, median(&mut y1s) as usize))
        };
        let measured = measure(&shot, x0, x1, "unlit", yband);
        println!(
            "  unlit tube (glass only): glass {:+.0}% / own {:.0}% | mesh {:.1}% | bars {}",
            measured.glass_mid_ratio.unwrap_or(f64::NAN) * 100.0,
            measured.glass_own_light.unwrap_or(f64::NAN) * 100.0,
            measured.cage_contrast.unwrap_or(f64::NAN) * 100.0,
            measured.cathodes_min.unwrap_or(0)
        );
        if check && measured.glass_mid_ratio.unwrap_or(0.0).abs() > LIMITS.glass_mid_ratio {
            bad.push(format!(
                "unlit: glass {:+.0}% (limit ±{:.0}%)",
                measured.glass_mid_ratio.unwrap_or(0.0) * 100.0,
                LIMITS.glass_mid_ratio * 100.0
            ));
        }
        if check && measured.cathodes_min.unwrap_or(0) < LIMITS.cathodes_min {
            bad.push(format!(
                "unlit: visible bars {} < {}",
                measured.cathodes_min.unwrap_or(0),
                LIMITS.cathodes_min
            ));
        }
        if check && measured.cage_contrast.unwrap_or(0.0) < LIMITS.cage_contrast {
            bad.push(format!(
                "unlit: mesh contrast {:.1}% < {:.0}%",
                measured.cage_contrast.unwrap_or(0.0) * 100.0,
                LIMITS.cage_contrast * 100.0
            ));
        }
        if check && measured.glass_own_light.unwrap_or(0.0) > 4.0 {
            bad.push(format!(
                "unlit: glass own light {:.0}% of the wire (expected: dim)",
                measured.glass_own_light.unwrap_or(0.0) * 100.0
            ));
        }
    }
    if mode == "digits" {
        for k in 0..clusters.len().min(10) {
            let (x0, x1) = clusters[k];
            if let Some(result) = orientation(&shot, x0, x1, k) {
                if result != "-" {
                    println!("  digit {k}: orientation {result}");
                    if check && result != "pass" {
                        bad.push(format!("digit {k}: {result}"));
                    }
                }
            }
        }
    }
    if check {
        if !bad.is_empty() {
            println!("\nFAIL:");
            for entry in bad {
                println!("  - {entry}");
            }
            return ExitCode::FAILURE;
        }
        println!("\nOK: every measured criterion is inside its limit");
    }
    ExitCode::SUCCESS
}
