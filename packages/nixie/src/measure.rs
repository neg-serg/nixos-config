//! What a picture of a lamp is judged by — measured on the frame this tool drew
//! itself, so there is no screenshot to find the tube in: the box the drawing
//! asks for is exactly where the renderer put it.
//!
//! The numbers and their limits are the acceptance criteria A1..A7 of
//! docs/howto/designs/nixie-lamps-plan.xml, the same ones nixie-metrics.py
//! measured on a screen shot.

/// The limits, in device pixels and ratios. A wire is white-hot and thin, the
/// gas falls away inside the mesh, the glass adds little of its own light.
#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub wire_white_px: u32,
    pub wire_hot_px: u32,
    pub halo_half_px: (u32, u32),
    pub glass_own_light: f32,
    pub cage_contrast: f32,
}

impl Default for Limits {
    fn default() -> Self {
        // the plan's numbers are written for a lamp drawn at 2 device px per
        // logical px, which is the scale `render --scale 2` uses
        Self {
            wire_white_px: 8,
            wire_hot_px: 16,
            halo_half_px: (6, 14),
            glass_own_light: 0.08,
            cage_contrast: 0.03,
        }
    }
}

/// One lamp, measured.
#[derive(Debug, Clone, Default)]
pub struct Measured {
    pub wire_white_px: u32,
    pub wire_hot_px: u32,
    pub halo_half_px: u32,
    pub glass_own_light: f32,
    pub cage_contrast: f32,
    /// Where the lit metal sits inside the box, as a share of the box: a `7`
    /// carries its ink in the upper half, a `2` has a bar across the bottom.
    pub ink_top_share: f32,
    pub ink_bbox: (u32, u32, u32, u32),
}

impl Measured {
    /// The criteria a picture has to meet, as (name, ok, what was measured).
    pub fn checks(&self, limits: &Limits) -> Vec<(&'static str, bool, String)> {
        vec![
            (
                "the wire is thin",
                self.wire_white_px <= limits.wire_white_px,
                format!(
                    "white {} px (limit {})",
                    self.wire_white_px, limits.wire_white_px
                ),
            ),
            (
                "the hot zone is thin",
                self.wire_hot_px <= limits.wire_hot_px,
                format!("hot {} px (limit {})", self.wire_hot_px, limits.wire_hot_px),
            ),
            (
                "the gas falls away inside the mesh",
                self.halo_half_px >= limits.halo_half_px.0
                    && self.halo_half_px <= limits.halo_half_px.1,
                format!(
                    "halo half {} px (want {}..{})",
                    self.halo_half_px, limits.halo_half_px.0, limits.halo_half_px.1
                ),
            ),
            (
                "the glass adds little of its own",
                self.glass_own_light <= limits.glass_own_light,
                format!(
                    "glass light {:.0}% of the wire",
                    self.glass_own_light * 100.0
                ),
            ),
            (
                "the mesh is there",
                self.cage_contrast >= limits.cage_contrast,
                format!("mesh contrast {:.1}%", self.cage_contrast * 100.0),
            ),
        ]
    }
}

/// Measure the lamp inside `box` (x0, y0, x1, y1) of an RGBA frame.
pub fn measure(rgba: &[u8], width: u32, box_: (u32, u32, u32, u32)) -> Measured {
    let (x0, y0, x1, y1) = box_;
    let at = |x: u32, y: u32| -> (i32, i32, i32) {
        let i = ((y * width + x) * 4) as usize;
        (rgba[i] as i32, rgba[i + 1] as i32, rgba[i + 2] as i32)
    };
    let mut out = Measured::default();

    // the wire: the widest run of white and of hot red across every row of the
    // numeral, and where the ink is
    let mut white = Vec::new();
    let mut hot = Vec::new();
    let mut ink_top = 0u64;
    let mut ink_bottom = 0u64;
    let (mut bx0, mut by0, mut bx1, mut by1) = (u32::MAX, u32::MAX, 0u32, 0u32);
    let mut reds: Vec<i32> = Vec::new();
    for y in y0..y1 {
        let mut run_w = 0;
        let mut run_h = 0;
        let mut best_w = 0;
        let mut best_h = 0;
        for x in x0..x1 {
            let (r, _g, b) = at(x, y);
            let warm = r > 150 && r - b > 45;
            if warm {
                bx0 = bx0.min(x);
                bx1 = bx1.max(x);
                by0 = by0.min(y);
                by1 = by1.max(y);
                reds.push(r);
                if y < (y0 + y1) / 2 {
                    ink_top += 1;
                } else {
                    ink_bottom += 1;
                }
            }
            if r > 240 {
                run_w += 1;
                best_w = best_w.max(run_w);
            } else {
                run_w = 0;
            }
            if r > 200 {
                run_h += 1;
                best_h = best_h.max(run_h);
            } else {
                run_h = 0;
            }
        }
        white.push(best_w);
        hot.push(best_h);
    }
    white.sort_unstable();
    hot.sort_unstable();
    out.wire_white_px = white.get(white.len() / 2).copied().unwrap_or(0);
    out.wire_hot_px = hot.get(hot.len() / 2).copied().unwrap_or(0);
    out.ink_bbox = (bx0, by0, bx1, by1);
    let ink = (ink_top + ink_bottom) as f32;
    out.ink_top_share = if ink > 0.0 { ink_top as f32 / ink } else { 0.0 };

    // the gas: how far the red channel takes to fall to half its peak, measured
    // off the wire on the row through the middle of the numeral
    let mid_y = (by0 + by1) / 2;
    let mut peak = 0i32;
    let mut peak_x = x0;
    for x in x0..x1 {
        let (r, _g, _b) = at(x, mid_y);
        if r > peak {
            peak = r;
            peak_x = x;
        }
    }
    let half = peak / 2;
    let mut reach = 0;
    for x in (x0..peak_x).rev() {
        if at(x, mid_y).0 < half {
            break;
        }
        reach = peak_x - x - 1;
    }
    out.halo_half_px = reach;

    // the glass's own light: the tube's body above the numeral against the
    // picture the glass covers — the box's corner is outside the tube
    let band_y = y0 + (by0 - y0) / 2;
    let mut inside = 0f32;
    let mut outside = 0f32;
    let mut n_in = 0f32;
    let mut n_out = 0f32;
    let cx = (x0 + x1) / 2;
    for y in y0..band_y.max(y0 + 1) {
        for x in x0..x1 {
            let l = at(x, y).0 as f32;
            if x > cx - 20 && x < cx + 20 {
                inside += l;
                n_in += 1.0;
            } else if x < x0 + 20 || x > x1 - 20 {
                outside += l;
                n_out += 1.0;
            }
        }
    }
    let peak_f = peak.max(1) as f32;
    out.glass_own_light = if n_in > 0.0 {
        (inside / n_in) / peak_f
    } else {
        0.0
    };

    // the mesh: how much high-frequency structure the tube's body carries — a
    // lamp without an anode looks like flat glass, one with it does not
    let mut diff = 0f32;
    let mut mean = 0f32;
    let mut n = 0f32;
    for y in (by0 + 4)..by1.saturating_sub(4) {
        for x in (cx - 18)..(cx + 18) {
            let a = at(x, y).0 as f32;
            let b = at(x + 1, y).0 as f32;
            diff += (a - b).abs();
            mean += a;
            n += 1.0;
        }
    }
    if n > 0.0 {
        out.cage_contrast = (diff / n) / (mean / n).max(1.0);
    }
    let _ = (reds.len(), outside);
    out
}
