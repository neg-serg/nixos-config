//! Pixel primitives ported from Pillow (12.x) so the output matches the Python
//! generator, not merely "a Gaussian blur" or "a line".
//!
//! Pillow 12 implements `GaussianBlur` as three fractional box-blur passes
//! (Gwosdek's approximation), `Image.LANCZOS` as a fixed-point separable
//! resampler, `alpha_composite` with integer maths, and `ImageDraw` with its
//! own scanline rasteriser. All four are reproduced here; the visual parity
//! test in the crate report is based on these exact routines.

/// Pillow's `PRECISION_BITS`: 32 - 8 bits of result - 2 bits of overflow.
pub const PRECISION_BITS: i32 = 22;

// ---------------------------------------------------------------------------
// Gaussian blur (Pillow: three fractional box-blur passes)
// ---------------------------------------------------------------------------

fn gaussian_box_radius(radius: f32, passes: u32) -> f32 {
    // float sigma2, L, l, a; sqrt() is double but the assignment to L is float.
    let sigma2 = radius * radius / passes as f32;
    let l_wide = (12.0f64 * sigma2 as f64 + 1.0).sqrt();
    let l = ((l_wide - 1.0) / 2.0).floor() as f32;
    let mut a = (2.0f32 * l + 1.0) * (l * (l + 1.0) - 3.0 * sigma2);
    a /= 6.0 * (sigma2 - (l + 1.0) * (l + 1.0));
    l + a
}

#[derive(Clone, Copy)]
struct BoxParams {
    radius: usize,
    ww: u32,
    fw: u32,
    edge_a: usize,
    edge_b: usize,
}

fn box_params(radius_f: f32, width: usize) -> BoxParams {
    let radius = radius_f as usize;
    let ww = ((1u32 << 24) as f32 / (radius_f * 2.0 + 1.0)) as u32;
    let fw = ((1u32 << 24) - (radius as u32 * 2 + 1) * ww) / 2;
    BoxParams {
        radius,
        ww,
        fw,
        edge_a: (radius + 1).min(width),
        edge_b: width.saturating_sub(radius + 1),
    }
}

#[inline]
fn save_px<const C: usize>(
    out_line: &mut [u8],
    x: usize,
    acc: &[u32; C],
    left: usize,
    right: usize,
    in_line: &[u8],
    p: &BoxParams,
) {
    for c in 0..C {
        let bulk = acc[c] as u64 * p.ww as u64
            + (in_line[left * C + c] as u64 + in_line[right * C + c] as u64) * p.fw as u64;
        out_line[x * C + c] = ((bulk + (1 << 23)) >> 24) as u8;
    }
}

/// One horizontal box pass over a `width * C` line of pixels.
fn box_blur_line<const C: usize>(in_line: &[u8], out_line: &mut [u8], width: usize, p: &BoxParams) {
    debug_assert!(width > 0);
    let lastx = width - 1;
    let tail = p.radius + 1 - p.edge_a;

    let mut acc = [0u32; C];
    for c in 0..C {
        acc[c] = in_line[c] as u32 * (p.radius as u32 + 1);
    }
    for x in 0..p.edge_a - 1 {
        for c in 0..C {
            acc[c] += in_line[x * C + c] as u32;
        }
    }
    for c in 0..C {
        acc[c] += in_line[lastx * C + c] as u32 * tail as u32;
    }

    if p.edge_a <= p.edge_b {
        for x in 0..p.edge_a {
            for c in 0..C {
                acc[c] += in_line[(x + p.radius) * C + c] as u32 - in_line[c] as u32;
            }
            save_px(out_line, x, &acc, 0, x + p.radius + 1, in_line, p);
        }
        for x in p.edge_a..p.edge_b {
            for c in 0..C {
                acc[c] += in_line[(x + p.radius) * C + c] as u32
                    - in_line[(x - p.radius - 1) * C + c] as u32;
            }
            save_px(
                out_line,
                x,
                &acc,
                x - p.radius - 1,
                x + p.radius + 1,
                in_line,
                p,
            );
        }
        for x in p.edge_b..=lastx {
            for c in 0..C {
                acc[c] +=
                    in_line[lastx * C + c] as u32 - in_line[(x - p.radius - 1) * C + c] as u32;
            }
            save_px(out_line, x, &acc, x - p.radius - 1, lastx, in_line, p);
        }
    } else {
        for x in 0..p.edge_b {
            for c in 0..C {
                acc[c] += in_line[(x + p.radius) * C + c] as u32 - in_line[c] as u32;
            }
            save_px(out_line, x, &acc, 0, x + p.radius + 1, in_line, p);
        }
        for x in p.edge_b..p.edge_a {
            for c in 0..C {
                acc[c] += in_line[lastx * C + c] as u32 - in_line[c] as u32;
            }
            save_px(out_line, x, &acc, 0, lastx, in_line, p);
        }
        for x in p.edge_a..=lastx {
            for c in 0..C {
                acc[c] +=
                    in_line[lastx * C + c] as u32 - in_line[(x - p.radius - 1) * C + c] as u32;
            }
            save_px(out_line, x, &acc, x - p.radius - 1, lastx, in_line, p);
        }
    }
}

/// Three horizontal passes, in-place style (Pillow applies the filter three
/// times, each pass reading the previous one's 8-bit result).
fn box_blur_h<const C: usize>(
    src: &[u8],
    dst: &mut [u8],
    width: usize,
    height: usize,
    radius_f: f32,
) {
    let p = box_params(radius_f, width);
    for y in 0..height {
        let start = y * width * C;
        let line_in = &src[start..start + width * C];
        let line_out = &mut dst[start..start + width * C];
        box_blur_line::<C>(line_in, line_out, width, &p);
    }
}

fn transpose<const C: usize>(src: &[u8], width: usize, height: usize) -> Vec<u8> {
    let mut out = vec![0u8; src.len()];
    for y in 0..height {
        for x in 0..width {
            let si = (y * width + x) * C;
            let di = (x * height + y) * C;
            out[di..di + C].copy_from_slice(&src[si..si + C]);
        }
    }
    out
}

/// Pillow's `GaussianBlur(radius)` for `C` interleaved channels.
pub fn gaussian_blur<const C: usize>(
    src: &[u8],
    width: usize,
    height: usize,
    radius: f32,
) -> Vec<u8> {
    let radius_f = gaussian_box_radius(radius, 3);
    let mut a = src.to_vec();
    let mut b = vec![0u8; src.len()];

    for _ in 0..3 {
        box_blur_h::<C>(&a, &mut b, width, height, radius_f);
        std::mem::swap(&mut a, &mut b);
    }

    let mut transposed = transpose::<C>(&a, width, height);
    let mut transposed_out = vec![0u8; transposed.len()];
    for _ in 0..3 {
        box_blur_h::<C>(&transposed, &mut transposed_out, height, width, radius_f);
        std::mem::swap(&mut transposed, &mut transposed_out);
    }

    transpose::<C>(&transposed, height, width)
}

// ---------------------------------------------------------------------------
// LANCZOS resize (Pillow's fixed-point 8-bit resampler)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct FilterCoeffs {
    xmin: usize,
    count: usize,
}

struct ResamplePlan {
    ksize: usize,
    coeffs: Vec<i32>,
    bounds: Vec<FilterCoeffs>,
}

fn sinc_filter(x: f64) -> f64 {
    if x == 0.0 {
        return 1.0;
    }
    let x = x * std::f64::consts::PI;
    x.sin() / x
}

fn lanczos_filter(x: f64) -> f64 {
    if (-3.0..3.0).contains(&x) {
        sinc_filter(x) * sinc_filter(x / 3.0)
    } else {
        0.0
    }
}

fn precompute_coeffs(in_size: usize, out_size: usize) -> ResamplePlan {
    let scale = in_size as f64 / out_size as f64;
    let filterscale = scale.max(1.0);
    let support = 3.0 * filterscale;
    let ksize = support.ceil() as usize * 2 + 1;
    let inv_filterscale = 1.0 / filterscale;

    let mut coeffs = Vec::with_capacity(out_size * ksize);
    let mut bounds = Vec::with_capacity(out_size);

    for xx in 0..out_size {
        let center = (xx as f64 + 0.5) * scale;
        let mut weights = vec![0.0f64; ksize];
        let xmin = ((center - support + 0.5) as i32).max(0) as usize;
        let mut xmax = (center + support + 0.5) as i32;
        if xmax > in_size as i32 {
            xmax = in_size as i32;
        }
        let count = (xmax - xmin as i32).max(0) as usize;

        let mut sum = 0.0f64;
        for x in 0..count {
            let w = lanczos_filter((x as f64 + xmin as f64 - center + 0.5) * inv_filterscale);
            weights[x] = w;
            sum += w;
        }
        if sum != 0.0 {
            for w in weights.iter_mut().take(count) {
                *w /= sum;
            }
        }
        for w in &weights {
            let fixed = if *w < 0.0 {
                (-0.5 + *w * (1 << PRECISION_BITS) as f64) as i32
            } else {
                (0.5 + *w * (1 << PRECISION_BITS) as f64) as i32
            };
            coeffs.push(fixed);
        }
        bounds.push(FilterCoeffs { xmin, count });
    }

    ResamplePlan {
        ksize,
        coeffs,
        bounds,
    }
}

#[inline]
fn clip8(value: i64) -> u8 {
    ((value >> PRECISION_BITS).clamp(0, 255)) as u8
}

fn resample_horizontal(
    src: &[u8],
    width: usize,
    height: usize,
    out_width: usize,
    plan: &ResamplePlan,
) -> Vec<u8> {
    let mut out = vec![0u8; out_width * height];
    for y in 0..height {
        let row = &src[y * width..(y + 1) * width];
        for xx in 0..out_width {
            let b = plan.bounds[xx];
            let k = &plan.coeffs[xx * plan.ksize..(xx + 1) * plan.ksize];
            let mut sum: i64 = 1 << (PRECISION_BITS - 1);
            for x in 0..b.count {
                sum += row[b.xmin + x] as i64 * k[x] as i64;
            }
            out[y * out_width + xx] = clip8(sum);
        }
    }
    out
}

/// Pillow's `Image.resize(..., Image.LANCZOS)` for a single 8-bit channel.
pub fn resize_lanczos_l(
    src: &[u8],
    width: usize,
    height: usize,
    out_width: usize,
    out_height: usize,
) -> Vec<u8> {
    if width == out_width && height == out_height {
        return src.to_vec();
    }
    let hplan = precompute_coeffs(width, out_width);
    let horizontal = resample_horizontal(src, width, height, out_width, &hplan);

    let vplan = precompute_coeffs(height, out_height);
    let mut out = vec![0u8; out_width * out_height];
    for yy in 0..out_height {
        let b = vplan.bounds[yy];
        let k = &vplan.coeffs[yy * vplan.ksize..(yy + 1) * vplan.ksize];
        for x in 0..out_width {
            let mut sum: i64 = 1 << (PRECISION_BITS - 1);
            for y in 0..b.count {
                sum += horizontal[(b.xmin + y) * out_width + x] as i64 * k[y] as i64;
            }
            out[yy * out_width + x] = clip8(sum);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// Alpha compositing (Pillow's integer implementation)
// ---------------------------------------------------------------------------

#[inline]
fn shift_for_div255(a: u32) -> u32 {
    ((a >> 8) + a) >> 8
}

/// `Image.alpha_composite(dst, src)` for RGBA buffers.
pub fn alpha_composite(dst: &[u8], src: &[u8]) -> Vec<u8> {
    debug_assert_eq!(dst.len(), src.len());
    let mut out = vec![0u8; dst.len()];
    for i in (0..dst.len()).step_by(4) {
        let da = dst[i + 3] as u32;
        let sa = src[i + 3] as u32;
        if sa == 0 {
            out[i..i + 4].copy_from_slice(&dst[i..i + 4]);
            continue;
        }
        let blend = da * (255 - sa);
        let outa255 = sa * 255 + blend;
        let coef1 = sa * 255 * 255 * (1 << 7) / outa255;
        let coef2 = 255 * (1 << 7) - coef1;
        for c in 0..3 {
            let tmp = src[i + c] as u32 * coef1 + dst[i + c] as u32 * coef2;
            out[i + c] = (shift_for_div255(tmp + (0x80 << 7)) >> 7) as u8;
        }
        out[i + 3] = shift_for_div255(outa255 + 0x80) as u8;
    }
    out
}

// ---------------------------------------------------------------------------
// ImageDraw (RGBA, replace semantics; Pillow's draw object with blend = 0)
// ---------------------------------------------------------------------------

pub struct Canvas {
    pub width: usize,
    pub height: usize,
    pub data: Vec<u8>,
}

impl Canvas {
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            width,
            height,
            data: vec![0u8; width * height * 4],
        }
    }

    #[inline]
    fn put(&mut self, x: i32, y: i32, ink: &[u8; 4]) {
        if x >= 0 && y >= 0 && (x as usize) < self.width && (y as usize) < self.height {
            let i = (y as usize * self.width + x as usize) * 4;
            self.data[i..i + 4].copy_from_slice(ink);
        }
    }

    /// Pillow's `hline32`: replace a horizontal span, clipped.
    fn hline(&mut self, y: i32, x0: i32, x1: i32, ink: &[u8; 4]) {
        if y < 0 || y as usize >= self.height {
            return;
        }
        let mut x0 = x0;
        let mut x1 = x1;
        if x0 < 0 {
            x0 = 0;
        } else if x0 as usize >= self.width {
            return;
        }
        if x1 < 0 {
            return;
        } else if x1 as usize >= self.width {
            x1 = self.width as i32 - 1;
        }
        if x0 > x1 {
            return;
        }
        for x in x0..=x1 {
            self.put(x, y, ink);
        }
    }

    /// Pillow's `line32` (single-pixel Bresenham line).
    fn line32(&mut self, mut x0: i32, mut y0: i32, x1: i32, y1: i32, ink: &[u8; 4]) {
        let mut dx = x1 - x0;
        let xs = if dx < 0 {
            dx = -dx;
            -1
        } else {
            1
        };
        let mut dy = y1 - y0;
        let ys = if dy < 0 {
            dy = -dy;
            -1
        } else {
            1
        };

        if dx == 0 {
            for _ in 0..dy {
                self.put(x0, y0, ink);
                y0 += ys;
            }
        } else if dy == 0 {
            for _ in 0..dx {
                self.put(x0, y0, ink);
                x0 += xs;
            }
        } else if dx > dy {
            let n = dx;
            dy += dy;
            let mut e = dy - dx;
            dx += dx;
            for _ in 0..n {
                self.put(x0, y0, ink);
                if e >= 0 {
                    y0 += ys;
                    e -= dx;
                }
                e += dy;
                x0 += xs;
            }
        } else {
            let n = dy;
            dx += dx;
            let mut e = dx - dy;
            dy += dy;
            for _ in 0..n {
                self.put(x0, y0, ink);
                if e >= 0 {
                    x0 += xs;
                    e -= dy;
                }
                e += dx;
                y0 += ys;
            }
        }
    }

    /// `ImageDraw.line` with two points: the binding truncates coordinates to
    /// integers, draws `width`-1 segments and finally the last vertex.
    pub fn line(&mut self, x0: f64, y0: f64, x1: f64, y1: f64, ink: [i32; 4], width: i32) {
        let ink = clamp_ink(ink);
        let (x0, y0, x1, y1) = (x0 as i32, y0 as i32, x1 as i32, y1 as i32);
        if width <= 1 {
            self.line32(x0, y0, x1, y1, &ink);
            self.put(x1, y1, &ink);
        } else {
            self.wide_line(x0, y0, x1, y1, width, &ink);
        }
    }

    /// `ImagingDrawWideLine`: a quad around the segment, filled by Pillow's
    /// scanline polygon rasteriser.
    fn wide_line(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, width: i32, ink: &[u8; 4]) {
        let dx = x1 - x0;
        let dy = y1 - y0;
        if dx == 0 && dy == 0 {
            self.put(x0, y0, ink);
            return;
        }
        let big_hypotenuse = ((dx * dx + dy * dy) as f64).sqrt();
        let small_hypotenuse = (width - 1) as f64 / 2.0;
        let ratio_max = round_up_f64(small_hypotenuse) / big_hypotenuse;
        let ratio_min = round_down_f64(small_hypotenuse) / big_hypotenuse;

        let dxmin = round_down_f64(ratio_min * dy as f64) as i32;
        let dxmax = round_down_f64(ratio_max * dy as f64) as i32;
        let dymin = round_down_f64(ratio_min * dx as f64) as i32;
        let dymax = round_down_f64(ratio_max * dx as f64) as i32;

        let vertices = [
            (x0 - dxmin, y0 + dymax),
            (x1 - dxmin, y1 + dymax),
            (x1 + dxmax, y1 - dymin),
            (x0 + dxmax, y0 - dymin),
        ];
        let mut edges = Vec::with_capacity(4);
        for i in 0..4 {
            let (ax, ay) = vertices[i];
            let (bx, by) = vertices[(i + 1) % 4];
            edges.push(Edge::new(ax, ay, bx, by));
        }
        self.polygon_fill(&edges, ink);
    }

    /// `polygon_generic` for an opaque ink (the non-`*rgba` hline path).
    fn polygon_fill(&mut self, edges: &[Edge], ink: &[u8; 4]) {
        if edges.is_empty() {
            return;
        }
        let mut ymin = self.height as i32 - 1;
        let mut ymax = 0i32;
        let mut edge_table: Vec<&Edge> = Vec::new();
        for e in edges {
            ymin = ymin.min(e.ymin);
            ymax = ymax.max(e.ymax);
            if e.ymin == e.ymax {
                self.hline(e.ymin, e.xmin, e.xmax, ink);
            } else {
                edge_table.push(e);
            }
        }
        if ymin < 0 {
            ymin = 0;
        }
        if ymax > self.height as i32 {
            ymax = self.height as i32;
        }
        let mut xx: Vec<f32> = Vec::new();
        for y in ymin..=ymax {
            xx.clear();
            for (i, current) in edge_table.iter().enumerate() {
                if y >= current.ymin && y <= current.ymax {
                    xx.push((y - current.y0) as f32 * current.dx + current.x0 as f32);
                    if y == current.ymax && y < ymax {
                        let last = *xx.last().unwrap();
                        xx.push(last);
                    } else if (y == current.ymin || y == current.ymax) && current.dx != 0.0 {
                        for other in edge_table.iter().take(i) {
                            if (y != other.ymin && y != other.ymax) || other.dx == 0.0 {
                                continue;
                            }
                            let last = *xx.last().unwrap();
                            let other_x = (y - other.y0) as f32 * other.dx + other.x0 as f32;
                            if last.round() == other_x.round() {
                                let offset = if y == current.ymax { -1 } else { 1 };
                                let adjacent_line_x = (y + offset - current.y0) as f32 * current.dx
                                    + current.x0 as f32;
                                if y + offset >= other.ymin && y + offset <= other.ymax {
                                    let adjacent_other =
                                        (y + offset - other.y0) as f32 * other.dx + other.x0 as f32;
                                    let idx = xx.len() - 1;
                                    if xx[idx] > adjacent_line_x + 1.0
                                        && xx[idx] > adjacent_other + 1.0
                                    {
                                        xx[idx] = adjacent_line_x.max(adjacent_other).round() + 1.0;
                                    } else if xx[idx] < adjacent_line_x - 1.0
                                        && xx[idx] < adjacent_other - 1.0
                                    {
                                        xx[idx] = adjacent_line_x.min(adjacent_other).round() - 1.0;
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            xx.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
            let mut i = 1;
            while i < xx.len() {
                let x0 = round_up_f32(xx[i - 1]);
                let x1 = round_down_f32(xx[i]);
                self.hline(y, x0, x1, ink);
                i += 2;
            }
        }
    }

    /// `ImageDraw.ellipse` with a fill and no outline (Pillow's ellipse
    /// scanline algorithm).
    pub fn ellipse(&mut self, x0: f64, y0: f64, x1: f64, y1: f64, ink: [i32; 4]) {
        let ink = clamp_ink(ink);
        let (x0, y0, x1, y1) = (x0 as i32, y0 as i32, x1 as i32, y1 as i32);
        let a = x1 - x0;
        let b = y1 - y0;
        if a < 0 || b < 0 {
            return;
        }
        let mut st = EllipseState::new(a, b, a + b);
        while let Some((px0, py, px1)) = st.next() {
            self.hline(
                y0 + (py + b) / 2,
                x0 + (px0 + a) / 2,
                x0 + (px1 + a) / 2,
                &ink,
            );
        }
    }
}

fn clamp_ink(ink: [i32; 4]) -> [u8; 4] {
    ink.map(|v| v.clamp(0, 255) as u8)
}

fn round_up_f64(f: f64) -> f64 {
    if f >= 0.0 {
        (f + 0.5).floor()
    } else {
        -((-f) + 0.5).floor()
    }
}

fn round_down_f64(f: f64) -> f64 {
    if f >= 0.0 {
        (f - 0.5).ceil()
    } else {
        -((-f) - 0.5).ceil()
    }
}

fn round_up_f32(f: f32) -> i32 {
    if f >= 0.0 {
        (f + 0.5).floor() as i32
    } else {
        -((-f) + 0.5).floor() as i32
    }
}

fn round_down_f32(f: f32) -> i32 {
    if f >= 0.0 {
        (f - 0.5).ceil() as i32
    } else {
        -((-f) - 0.5).ceil() as i32
    }
}

#[derive(Clone, Copy)]
struct Edge {
    x0: i32,
    y0: i32,
    xmin: i32,
    ymin: i32,
    xmax: i32,
    ymax: i32,
    dx: f32,
}

impl Edge {
    fn new(x0: i32, y0: i32, x1: i32, y1: i32) -> Self {
        let (xmin, xmax) = if x0 <= x1 { (x0, x1) } else { (x1, x0) };
        let (ymin, ymax) = if y0 <= y1 { (y0, y1) } else { (y1, y0) };
        let dx = if y0 == y1 {
            0.0
        } else {
            (x1 - x0) as f32 / (y1 - y0) as f32
        };
        Self {
            x0,
            y0,
            xmin,
            ymin,
            xmax,
            ymax,
            dx,
        }
    }
}

// --- Pillow ellipse rasteriser --------------------------------------------

struct QuarterState {
    cx: i32,
    cy: i32,
    ex: i32,
    ey: i32,
    a2: i64,
    b2: i64,
    a2b2: i64,
    finished: bool,
}

impl QuarterState {
    fn new(a: i32, b: i32) -> Self {
        if a < 0 || b < 0 {
            return Self {
                cx: 0,
                cy: 0,
                ex: 0,
                ey: 0,
                a2: 0,
                b2: 0,
                a2b2: 0,
                finished: true,
            };
        }
        let a2 = a as i64 * a as i64;
        let b2 = b as i64 * b as i64;
        Self {
            cx: a,
            cy: b % 2,
            ex: a % 2,
            ey: b,
            a2,
            b2,
            a2b2: a2 * b2,
            finished: false,
        }
    }

    fn delta(&self, x: i64, y: i64) -> i64 {
        (self.a2 * y * y + self.b2 * x * x - self.a2b2).abs()
    }

    fn next(&mut self) -> Option<(i32, i32)> {
        if self.finished {
            return None;
        }
        let (rx, ry) = (self.cx, self.cy);
        if self.cx == self.ex && self.cy == self.ey {
            self.finished = true;
        } else {
            let mut nx = self.cx;
            let mut ny = self.cy + 2;
            let mut ndelta = self.delta(nx as i64, ny as i64);
            if nx > 1 {
                let mut newdelta = self.delta((self.cx - 2) as i64, (self.cy + 2) as i64);
                if ndelta > newdelta {
                    nx = self.cx - 2;
                    ny = self.cy + 2;
                    ndelta = newdelta;
                }
                newdelta = self.delta((self.cx - 2) as i64, self.cy as i64);
                if ndelta > newdelta {
                    nx = self.cx - 2;
                    ny = self.cy;
                }
            }
            self.cx = nx;
            self.cy = ny;
        }
        Some((rx, ry))
    }
}

struct EllipseState {
    st_o: QuarterState,
    st_i: QuarterState,
    py: i32,
    pl: i32,
    pr: i32,
    cl: [i32; 4],
    cy: [i32; 4],
    cr: [i32; 4],
    bufcnt: usize,
    finished: bool,
    leftmost: i32,
}

impl EllipseState {
    fn new(a: i32, b: i32, w: i32) -> Self {
        let mut st = Self {
            st_o: QuarterState::new(a, b),
            st_i: QuarterState::new(a, b),
            py: 0,
            pl: 0,
            pr: 0,
            cl: [0; 4],
            cy: [0; 4],
            cr: [0; 4],
            bufcnt: 0,
            finished: false,
            leftmost: a % 2,
        };
        if w < 1 {
            st.finished = true;
            return st;
        }
        match st.st_o.next() {
            None => st.finished = true,
            Some((pr, py)) => {
                st.pr = pr;
                st.py = py;
                st.st_i = QuarterState::new(a - 2 * (w - 1), b - 2 * (w - 1));
                st.pl = st.leftmost;
            }
        }
        st
    }

    fn next(&mut self) -> Option<(i32, i32, i32)> {
        if self.bufcnt == 0 {
            if self.finished {
                return None;
            }
            let y = self.py;
            let mut l = self.pl;
            let r = self.pr;

            let outer_result = loop {
                match self.st_o.next() {
                    None => break None,
                    Some((cx, cy)) => {
                        if cy > y {
                            break Some((cx, cy));
                        }
                    }
                }
            };
            match outer_result {
                None => self.finished = true,
                Some((cx, cy)) => {
                    self.pr = cx;
                    self.py = cy;
                }
            }

            let inner_result = loop {
                match self.st_i.next() {
                    None => break None,
                    Some((cx, cy)) => {
                        if cy > y {
                            break Some(cx);
                        }
                        l = cx;
                    }
                }
            };
            self.pl = match inner_result {
                None => self.leftmost,
                Some(cx) => cx,
            };

            if (l > 0 || l < r) && y > 0 {
                self.cl[self.bufcnt] = if l == 0 { 2 } else { l };
                self.cy[self.bufcnt] = y;
                self.cr[self.bufcnt] = r;
                self.bufcnt += 1;
            }
            if y > 0 {
                self.cl[self.bufcnt] = -r;
                self.cy[self.bufcnt] = y;
                self.cr[self.bufcnt] = -l;
                self.bufcnt += 1;
            }
            if l > 0 || l < r {
                self.cl[self.bufcnt] = if l == 0 { 2 } else { l };
                self.cy[self.bufcnt] = -y;
                self.cr[self.bufcnt] = r;
                self.bufcnt += 1;
            }
            self.cl[self.bufcnt] = -r;
            self.cy[self.bufcnt] = -y;
            self.cr[self.bufcnt] = -l;
            self.bufcnt += 1;
        }
        self.bufcnt -= 1;
        Some((
            self.cl[self.bufcnt],
            self.cy[self.bufcnt],
            self.cr[self.bufcnt],
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn gaussian_blur_matches_pillow_impulse() {
        let mut img = vec![0u8; 7 * 7];
        img[3 * 7 + 3] = 255;
        let out = gaussian_blur::<1>(&img, 7, 7, 1.0);
        let expected = [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 6, 3, 0, 0, 0, 3, 14, 24, 14, 3, 0, 1, 6, 24, 42, 24, 6,
            1, 0, 3, 14, 24, 14, 3, 0, 0, 0, 3, 6, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ];
        assert_eq!(out, expected);
    }

    #[test]
    fn lanczos_resize_matches_pillow() {
        let img = [
            0u8, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150,
        ];
        let out = resize_lanczos_l(&img, 4, 4, 2, 2);
        assert_eq!(out, [27, 47, 103, 123]);
    }

    #[test]
    fn alpha_composite_matches_pillow() {
        let dst = [10u8, 20, 30, 40];
        let src = [200u8, 150, 100, 128];
        let out = alpha_composite(&dst, &src);
        assert_eq!(out, [174, 132, 91, 148]);
    }

    #[test]
    fn ellipse_fills_its_centre_and_clips_off_canvas() {
        let mut canvas = Canvas::new(20, 20);
        canvas.ellipse(1.2, 1.7, 12.9, 13.1, [255, 255, 255, 128]);
        assert_eq!(canvas.data[(7 * 20 + 7) * 4 + 3], 128);
        // Fully outside the canvas: must not panic and must not paint anything.
        canvas.ellipse(-50.0, -50.0, -10.0, -10.0, [255, 0, 0, 200]);
        assert_eq!(canvas.data[3], 0);
    }

    #[test]
    fn wide_line_replaces_pixels_with_its_ink() {
        let mut canvas = Canvas::new(20, 10);
        canvas.line(0.0, 5.0, 19.0, 5.0, [255, 0, 0, 255], 3);
        let painted = canvas.data.chunks(4).filter(|px| px[0] == 255).count();
        assert!(painted > 0);
    }
}
