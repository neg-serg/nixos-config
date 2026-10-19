//! The player's overlays as pure draw functions: server facts, the clock and the mode strip.
//!
//! Each function takes the frame size, a theme and a plain data struct, measures with `Fonts`,
//! pushes primitives into a `DrawList` and returns the geometry it used. Nothing here knows about
//! Vulkan, MPD or the app's state, so the caller decides when an overlay is on screen and this
//! module only answers "what does it look like, and how much room does it take". That split is
//! also what makes the layout testable: a test builds a real `Fonts`, draws into a `DrawList` and
//! asserts the rects, with no GPU and no window.
//!
//! The visual language is the one `src/bin/player.rs` already uses for its overlays: a rounded
//! surface at `Theme::pane_raised` elevation with `GEOM.radius_lg` corners and a one-pixel
//! `Theme::border_hi` highlight along its top edge, a `TYPE.micro` header in the faint ink, rows
//! laid out with
//! `Fonts::layout_line`, and long text truncated by `Fonts::fit` / `Fonts::layout_fitted_end`
//! instead of a guessed width. Copy is data, never code: every Russian string this UI shows is
//! passed in by the caller.

use crate::scene::DrawList;
use crate::text::Fonts;
use crate::theme::{with_alpha, Face, Rgba, Theme, GEOM, TYPE};

// ---------------------------------------------------------------- geometry

/// Axis-aligned rect in logical units — the space every draw function here is authored in.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl Rect {
    pub fn right(&self) -> f32 {
        self.x + self.w
    }

    pub fn bottom(&self) -> f32 {
        self.y + self.h
    }

    /// True when this rect covers `other`, allowing `slack` logical px of float noise. Used to
    /// prove "the panel is inside the frame" and "a row is inside its panel" arithmetically
    /// instead of by eye.
    pub fn covers(&self, other: Rect, slack: f32) -> bool {
        other.x >= self.x - slack
            && other.y >= self.y - slack
            && other.right() <= self.right() + slack
            && other.bottom() <= self.bottom() + slack
    }
}

/// What one draw call put on screen. Returning this instead of nothing is what lets the caller
/// keep its footer clear of an overlay, and what lets the tests assert "rows never overlap"
/// without reading pixels.
#[derive(Clone, Debug, Default)]
pub struct Drawn {
    /// Outer rect of the overlay itself. A full-frame scrim, when one is drawn, is not included:
    /// the caller cares about the panel, not the dim layer.
    pub bounds: Rect,
    /// One entry per drawn line — table rows, clock lines or chips — in reading order.
    pub rows: Vec<Rect>,
}

/// Horizontal content inset of a panel. It is the frame's own padding, so an overlay's text lines
/// up with the text of the panes behind it.
const PAD_X: f32 = GEOM.pad;

/// Vertical content inset of a panel: one block gap, which is how `GEOM.stack` is used elsewhere
/// in the app (a header sits this far below the top edge).
const PAD_Y: f32 = GEOM.stack;

/// Air between an overlay panel and the frame edge, so a panel clamped to the frame still reads as
/// a panel and not as a surface that fell off the window.
const EDGE: f32 = GEOM.pad + GEOM.gap;

/// Narrower than this and a panel reads as a broken strip, so such a frame gets no overlay at all.
const MIN_PANEL_W: f32 = 160.0;

/// Same rule vertically: below this there is no room for a header plus one row.
const MIN_PANEL_H: f32 = 72.0;

/// Air between a table row's label and its value.
const COL_GAP: f32 = GEOM.stack;

/// Chip metrics, taken from the mode-chips block the now-playing pane already draws: an 11 px
/// caption inside a 22 px pill, 9 px of air either side and 6 px between chips. Reusing those
/// numbers is what makes the strip look like the same widget in a second place.
const CHIP_H: f32 = 22.0;
const CHIP_PAD_X: f32 = 9.0;
const CHIP_GAP: f32 = GEOM.row_gap + 2.0;
/// `layout_line` takes the top of the line box, and an 11 px caption's ink starts about 5 px down
/// inside a 22 px pill; the existing chips use the same offset.
const CHIP_TEXT_DY: f32 = 5.0;

/// Height of one line box. `Fonts` shapes every buffer with a 1.32 line height
/// (`Metrics::new(size, size * 1.32)` in `src/text.rs`), and `text.rs` exposes no accessor for
/// that factor, so it is repeated here: a row that owns exactly one line is this tall, and every
/// cell in this module is placed on that grid. A public `Fonts::line_height` would remove the
/// copy.
fn line_h(size: f32) -> f32 {
    (size * 1.32).ceil()
}

/// The panel surface every overlay shares: elevation (surface + shadow together, since a modal is
/// exactly the pane that owns the keyboard), rounded corners, and the 1 px top highlight that is
/// the only thing separating two dark surfaces on this palette.
fn panel_surface(list: &mut DrawList, th: &Theme, r: Rect) {
    list.shadow(
        r.x,
        r.y + 2.0,
        r.w,
        r.h,
        GEOM.radius_lg,
        24.0,
        th.pane_raised.shadow,
    );
    list.rounded(
        r.x,
        r.y,
        r.w,
        r.h,
        GEOM.radius_lg,
        th.pane_raised.surface,
        th.pane_raised.surface,
    );
    list.rect(r.x, r.y, r.w, GEOM.line, th.border_hi);
}

/// Fit, measure, then place one line centred on `cx`.
///
/// `layout_fitted` cannot be used here: it truncates and draws in one step, so the width needed to
/// compute the centred x is only known after the text is already on screen. Fitting first — the
/// same `Fonts::fit` call `layout_fitted` makes — keeps its truncation behaviour and yields the
/// exact width to centre by, so a truncated line stays centred instead of drifting left.
#[allow(clippy::too_many_arguments)]
fn centred_line(
    list: &mut DrawList,
    fonts: &mut Fonts,
    text: &str,
    cx: f32,
    y: f32,
    size: f32,
    face: Face,
    color: Rgba,
    max_w: f32,
) -> Rect {
    let fitted = fonts.fit(text, size, max_w, face);
    let w = fonts.measure(&fitted, size, face);
    let x = (cx - w * 0.5).round();
    fonts.layout_line(list, &fitted, x, y, size, face, color);
    Rect {
        x,
        y,
        w,
        h: line_h(size),
    }
}

// ---------------------------------------------------------------- server info

/// Server facts, already formatted by the caller: one `(label, value)` pair per row, in the order
/// they should be read. Both halves are data, which is how the Russian strings stay out of this
/// module.
#[derive(Clone, Debug, Default)]
pub struct ServerInfo {
    pub lines: Vec<(String, String)>,
}

/// A centred "server" panel: one row per `(label, value)` pair, labels in the faint ink on the
/// left, values right-aligned in the `Mono` face on the right, plus the caller's `title` as a
/// `TYPE.micro` header.
///
/// The panel is sized to its content — `longest row + 2 * PAD_X`, floored at `MIN_PANEL_W` and
/// clamped to the frame — because a fixed-width dialog would leave a sea of surface next to four
/// short facts, while an unclamped one would push a long value off the window. Rows are one
/// `TYPE.body` line box plus `GEOM.row_gap`, and a table longer than the frame is cut at the frame
/// edge: the panel never grows past the window.
///
/// Nothing is drawn for an empty `lines` list, or for a frame too small to hold a readable panel
/// (`None` is returned and `list` is left untouched). A full-frame scrim is drawn first, so the
/// caller must not add its own dim layer for this one overlay.
pub fn draw_server_info(
    list: &mut DrawList,
    fonts: &mut Fonts,
    frame: (f32, f32),
    th: &Theme,
    title: &str,
    info: &ServerInfo,
) -> Option<Drawn> {
    let (w, h) = frame;
    // No facts means no panel: a header over an empty body reads as a broken overlay, so the
    // caller gets nothing drawn rather than a suspicious empty surface.
    if info.lines.is_empty() {
        return None;
    }
    let avail_w = w - 2.0 * EDGE;
    let avail_h = h - 2.0 * EDGE;
    if avail_w < MIN_PANEL_W || avail_h < MIN_PANEL_H {
        return None;
    }

    // --- measure the table. Labels and values share one type size on purpose: with two sizes the
    // two baselines inside a row would differ by an offset that `text.rs` does not expose, and a
    // table whose labels float half a pixel above their values looks broken. The hierarchy is
    // carried by ink instead — faint label, bright value — which costs no metrics.
    let size = TYPE.body;
    let row_h = line_h(size);
    let pitch = row_h + GEOM.row_gap;
    let mut widest_row = 0.0_f32;
    let mut widest_label = 0.0_f32;
    for (label, value) in &info.lines {
        let lw = fonts.measure(label, size, Face::UiRegular);
        let vw = fonts.measure(value, size, Face::Mono);
        widest_label = widest_label.max(lw);
        widest_row = widest_row.max(lw + COL_GAP + vw);
    }
    let title_w = if title.is_empty() {
        0.0
    } else {
        fonts.measure(title, TYPE.micro, Face::UiMedium)
    };

    // --- width: content + inset, floored, then clamped to the frame.
    let content_w = widest_row.max(title_w);
    let panel_w = (content_w + 2.0 * PAD_X).clamp(MIN_PANEL_W, avail_w);
    let inner_w = panel_w - 2.0 * PAD_X;
    // The label column never takes more than half of the inner width, so one long label cannot
    // squeeze the value column out of existence.
    let label_col = widest_label.min(inner_w * 0.5);
    let value_col = (inner_w - label_col - COL_GAP).max(0.0);

    // --- height: header (if any) plus as many rows as the frame can hold.
    let header_h = if title.is_empty() {
        0.0
    } else {
        line_h(TYPE.micro) + GEOM.inner
    };
    let body_budget = avail_h - 2.0 * PAD_Y - header_h;
    let max_rows = ((body_budget + GEOM.row_gap) / pitch).floor().max(0.0) as usize;
    let shown = info.lines.len().min(max_rows);
    if shown == 0 {
        return None;
    }
    let panel_h = 2.0 * PAD_Y + header_h + shown as f32 * pitch - GEOM.row_gap;

    let panel = Rect {
        x: ((w - panel_w) * 0.5).round(),
        y: ((h - panel_h) * 0.5).round(),
        w: panel_w,
        h: panel_h,
    };

    // --- surface: dim the frame, then the panel over it.
    list.rect(0.0, 0.0, w, h, with_alpha(th.bg_bottom, 0.78));
    panel_surface(list, th, panel);
    if !title.is_empty() {
        fonts.layout_line(
            list,
            title,
            panel.x + PAD_X,
            panel.y + PAD_Y,
            TYPE.micro,
            Face::UiMedium,
            th.text_faint,
        );
    }

    // --- rows
    let mut rows = Vec::with_capacity(shown);
    let mut y = panel.y + PAD_Y + header_h;
    for (label, value) in info.lines.iter().take(shown) {
        let row = Rect {
            x: panel.x + PAD_X,
            y,
            w: inner_w,
            h: row_h,
        };
        // A label carries no information in its tail once it is cut, so it truncates from the end.
        fonts.layout_fitted_end(
            list,
            label,
            row.x,
            y,
            size,
            Face::UiRegular,
            th.text_faint,
            label_col,
        );
        // A column of numbers is read by its right edge, so the value is fitted, measured and
        // *then* placed: `layout_fitted` would draw at a given x and reveal its width afterwards.
        let fitted = fonts.fit(value, size, value_col, Face::Mono);
        let vw = fonts.measure(&fitted, size, Face::Mono);
        fonts.layout_line(
            list,
            &fitted,
            row.right() - vw,
            y,
            size,
            Face::Mono,
            th.text,
        );
        rows.push(row);
        y += pitch;
    }

    Some(Drawn {
        bounds: panel,
        rows,
    })
}

// ---------------------------------------------------------------- clock

/// Wall-clock data, formatted by the caller: the time, the date under it, and an optional
/// countdown ("sleep in 00:42:10", "alarm in 6 h" — whatever the caller likes). No MPD state
/// belongs here: a clock that stops when the daemon does is not a clock.
#[derive(Clone, Debug, Default)]
pub struct Clock {
    pub time: String,
    pub date: String,
    pub timer: Option<String>,
}

/// A centred clock: `time` in `TYPE.display`, `date` under it in `TYPE.label`, and the optional
/// timer as a third, faintest line.
///
/// The block is centred on the frame as a whole (all lines share one centre, each line is centred
/// on its own post-truncation width) and it draws **no surface and no scrim**: this is a
/// whole-frame view, not a dialog, so the caller decides whether the frame behind it gets dimmed —
/// it is the only one of the three that may legitimately sit over live content. Sizes come from
/// `TYPE`, and empty fields are skipped, so a clock with only a time is one big number and nothing
/// else. An entirely empty `Clock` draws nothing.
pub fn draw_clock(
    list: &mut DrawList,
    fonts: &mut Fonts,
    frame: (f32, f32),
    th: &Theme,
    clock: &Clock,
) -> Option<Drawn> {
    let (w, h) = frame;
    let max_w = w - 2.0 * EDGE;
    let avail_h = h - 2.0 * EDGE;
    if max_w <= 0.0 || avail_h <= 0.0 {
        return None;
    }

    // Ink ladder: the time is the reason the overlay exists, the date is context, the timer is a
    // side note. Only the fields that carry text become lines.
    let mut lines: Vec<(String, f32, Face, Rgba, f32)> = Vec::new();
    if !clock.time.trim().is_empty() {
        lines.push((
            clock.time.clone(),
            TYPE.display,
            Face::MonoMedium,
            th.text,
            GEOM.inner,
        ));
    }
    if !clock.date.trim().is_empty() {
        lines.push((
            clock.date.clone(),
            TYPE.label,
            Face::UiRegular,
            th.text_dim,
            GEOM.row_gap,
        ));
    }
    if let Some(timer) = clock.timer.as_deref() {
        if !timer.trim().is_empty() {
            lines.push((
                timer.to_string(),
                TYPE.label,
                Face::Mono,
                th.text_faint,
                0.0,
            ));
        }
    }
    if lines.is_empty() {
        return None;
    }

    // Fit and measure once: the block height and every centred x come from these widths, so
    // shaping here keeps the truncation and the centring consistent with what is drawn.
    let measured: Vec<(String, f32, f32, f32, Face, Rgba, f32)> = lines
        .into_iter()
        .map(|(text, size, face, color, gap_after)| {
            let fitted = fonts.fit(&text, size, max_w, face);
            let width = fonts.measure(&fitted, size, face);
            (fitted, width, size, line_h(size), face, color, gap_after)
        })
        .collect();

    // Trailing lines are dropped rather than allowed to run off a short frame.
    let mut shown = measured.len();
    let total_h = |n: usize| -> f32 {
        let mut sum = 0.0;
        for (i, line) in measured.iter().take(n).enumerate() {
            sum += line.3;
            if i + 1 < n {
                sum += line.6;
            }
        }
        sum
    };
    while shown > 1 && total_h(shown) > avail_h {
        shown -= 1;
    }
    if total_h(shown) > avail_h {
        return None;
    }

    let cx = w * 0.5;
    let mut y = ((h - total_h(shown)) * 0.5).round().max(EDGE);
    let mut rows = Vec::with_capacity(shown);
    for (text, _width, size, height, face, color, gap_after) in measured.iter().take(shown) {
        let row = centred_line(list, fonts, text, cx, y, *size, *face, *color, max_w);
        rows.push(row);
        y += height + gap_after;
    }

    let left = rows.iter().fold(f32::INFINITY, |acc, r| acc.min(r.x));
    let right = rows
        .iter()
        .fold(f32::NEG_INFINITY, |acc, r| acc.max(r.right()));
    let bounds = Rect {
        x: left,
        y: rows[0].y,
        w: right - left,
        h: total_h(shown),
    };
    Some(Drawn { bounds, rows })
}

// ---------------------------------------------------------------- gains / modes

/// The playback modes worth a chip above the footer. Every field is at its default when it is at
/// neutral (`crossfade == 0`, an empty or `off` replay gain, `add_mode == false`,
/// `shuffle_hint == false`), and a strip with nothing to say draws nothing at all.
#[derive(Clone, Debug, Default)]
pub struct Gains {
    pub crossfade: i32,
    pub replay_gain: String,
    pub add_mode: bool,
    pub shuffle_hint: bool,
}

impl Gains {
    /// The pills this state earns, in reading order: `xf 4s` for a non-zero crossfade, `rg album`
    /// for a replay gain that is not off, `add` for add mode and `shuffle` for the shuffle hint.
    ///
    /// The tokens are plain ASCII shorthands because this module owns no UI copy and cannot own
    /// Russian. A caller that wants localised chip text can ignore this list and draw its own
    /// strip; the point of keeping it public is that "which chips are on" is a decision the caller
    /// can inspect without duplicating the default rules.
    pub fn chips(&self) -> Vec<String> {
        let mut out = Vec::new();
        if self.crossfade > 0 {
            out.push(format!("xf {}s", self.crossfade));
        }
        let rg = self.replay_gain.trim();
        if !rg.is_empty() && !rg.eq_ignore_ascii_case("off") {
            out.push(format!("rg {rg}"));
        }
        if self.add_mode {
            out.push("add".to_string());
        }
        if self.shuffle_hint {
            out.push("shuffle".to_string());
        }
        out
    }
}

/// A bottom-right strip of mode pills: one `GEOM.radius_pill` pill per non-default value, each a
/// one-line caption. All-default values draw nothing, which is the whole point — the strip is
/// permanent furniture, so it may only take pixels when it carries a fact.
///
/// Not a modal: no scrim, no panel, no title. Geometry: the pills are `CHIP_H` tall (22 px, the
/// same widget the now-playing pane's mode block draws), `CHIP_GAP` apart, and the strip is
/// right-aligned `GEOM.pad` from the right edge and `GEOM.pad` above the bottom edge of the rect
/// it is given. `frame` is that rect, so a caller with a footer passes `(w, h - footer_h)` and the
/// strip lands above the footer instead of on top of it. When the strip would be wider than the
/// frame, every label is truncated by the same budget rather than a chip being dropped: a mode
/// that silently disappears is worse than a clipped word.
pub fn draw_gains(
    list: &mut DrawList,
    fonts: &mut Fonts,
    frame: (f32, f32),
    th: &Theme,
    gains: &Gains,
) -> Option<Drawn> {
    let (w, h) = frame;
    let labels = gains.chips();
    if labels.is_empty() {
        return None;
    }
    let avail_w = w - 2.0 * GEOM.pad;
    if avail_w <= 0.0 || h < CHIP_H + 2.0 * GEOM.pad {
        return None;
    }

    let count = labels.len() as f32;
    let gap_total = CHIP_GAP * (count - 1.0);
    let text_budget = (avail_w - gap_total) / count - 2.0 * CHIP_PAD_X;
    if text_budget <= 0.0 {
        return None;
    }
    let texts: Vec<String> = labels
        .iter()
        .map(|label| fonts.fit(label, TYPE.caption, text_budget, Face::UiMedium))
        .collect();
    let widths: Vec<f32> = texts
        .iter()
        .map(|text| fonts.measure(text, TYPE.caption, Face::UiMedium) + 2.0 * CHIP_PAD_X)
        .collect();
    // An all-padding pill has no label left in it: better to draw nothing than four empty dots.
    if texts.iter().all(|text| text.is_empty()) {
        return None;
    }

    let total: f32 = widths.iter().sum::<f32>() + gap_total;
    let y = h - GEOM.pad - CHIP_H;
    let mut x = (w - GEOM.pad - total).max(GEOM.pad);
    let mut rows = Vec::with_capacity(texts.len());
    for (text, width) in texts.iter().zip(widths.iter()) {
        // The "on" chip treatment the now-playing pane already uses: an accent wash under an
        // accent caption. A gains pill is by definition a mode that is doing something, so it
        // never needs the hollow "off" variant.
        list.rounded(
            x,
            y,
            *width,
            CHIP_H,
            GEOM.radius_pill,
            th.accent_soft,
            with_alpha(th.accent2, 0.12),
        );
        fonts.layout_line(
            list,
            text,
            x + CHIP_PAD_X,
            y + CHIP_TEXT_DY,
            TYPE.caption,
            Face::UiMedium,
            th.accent,
        );
        rows.push(Rect {
            x,
            y,
            w: *width,
            h: CHIP_H,
        });
        x += width + CHIP_GAP;
    }

    Some(Drawn {
        bounds: Rect {
            x: rows[0].x,
            y,
            w: total,
            h: CHIP_H,
        },
        rows,
    })
}

// ---------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme;

    /// Real metrics or no test. The font is the user's own Iosevka build, loaded by absolute path;
    /// when it is missing the geometry these assertions describe does not exist, so the test says
    /// so on stderr and passes instead of failing on an unrelated machine.
    fn fonts_or_skip() -> Option<Fonts> {
        let dir = std::env::var_os("HOME")
            .map(|home| std::path::PathBuf::from(home).join(".local/share/fonts/iosevka-neg"));
        let present = dir
            .as_deref()
            .map(|dir| {
                dir.join("Iosevkaneg-Regular.ttf").is_file()
                    && dir.join("Iosevkaneg-Medium.ttf").is_file()
            })
            .unwrap_or(false);
        if !present {
            eprintln!(
                "[panels tests] skip: ~/.local/share/fonts/iosevka-neg is missing, \
                 the layout cannot be measured without it"
            );
            return None;
        }
        Some(Fonts::new())
    }

    const SIZES: [(f32, f32); 3] = [(800.0, 600.0), (1440.0, 900.0), (3840.0, 2160.0)];

    fn frame_rect((w, h): (f32, f32)) -> Rect {
        Rect {
            x: 0.0,
            y: 0.0,
            w,
            h,
        }
    }

    /// Bounding box of everything pushed into the list, in logical units (the tests never change
    /// the list's scale, so a device pixel is a logical pixel here).
    fn vertex_bounds(list: &DrawList) -> Option<Rect> {
        let mut min = [f32::INFINITY; 2];
        let mut max = [f32::NEG_INFINITY; 2];
        for vertex in &list.vertices {
            for axis in 0..2 {
                min[axis] = min[axis].min(vertex.pos[axis]);
                max[axis] = max[axis].max(vertex.pos[axis]);
            }
        }
        if list.vertices.is_empty() {
            return None;
        }
        Some(Rect {
            x: min[0],
            y: min[1],
            w: max[0] - min[0],
            h: max[1] - min[1],
        })
    }

    fn sample_info(n: usize) -> ServerInfo {
        let labels = [
            "protocol",
            "daemon",
            "uptime",
            "bitrate",
            "codec",
            "audio output",
            "clients",
            "library",
        ];
        ServerInfo {
            lines: (0..n)
                .map(|i| {
                    (
                        labels[i % labels.len()].to_string(),
                        format!("value {i} / {i}.{i} kHz / 320 kbps"),
                    )
                })
                .collect(),
        }
    }

    #[test]
    fn server_info_panel_fits_the_frame_at_every_size_and_row_count() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        for frame in SIZES {
            let outer = frame_rect(frame);
            for n in [1usize, 2, 3, 5, 8, 13, 24] {
                let mut list = DrawList::new();
                let drawn = draw_server_info(
                    &mut list,
                    &mut fonts,
                    frame,
                    &theme::DARK,
                    "server",
                    &sample_info(n),
                )
                .unwrap_or_else(|| panic!("no panel at {frame:?} with {n} rows"));

                assert!(
                    outer.covers(drawn.bounds, 0.5),
                    "panel {:?} escapes frame {:?}",
                    drawn.bounds,
                    outer
                );
                // Centred: the panel's middle is the frame's middle.
                let cx = drawn.bounds.x + drawn.bounds.w * 0.5;
                assert!(
                    (cx - frame.0 * 0.5).abs() <= 0.5,
                    "panel not centred at {frame:?}: cx {cx}"
                );
                let cy = drawn.bounds.y + drawn.bounds.h * 0.5;
                assert!(
                    (cy - frame.1 * 0.5).abs() <= 0.5,
                    "panel not centred at {frame:?}: cy {cy}"
                );
                // Everything pushed — scrim, surface, glyphs — stays inside the frame.
                let ink = vertex_bounds(&list).expect("drawn list is empty");
                assert!(
                    outer.covers(ink, 1.0),
                    "vertices {:?} escape frame {:?}",
                    ink,
                    outer
                );
                // Short tables show every row; a table taller than the frame is cut at the frame
                // edge, never spilled past it.
                assert!(!drawn.rows.is_empty(), "no rows at {frame:?} with {n} rows");
                assert!(drawn.rows.len() <= n, "more rows than lines at {frame:?}");
                if n <= 13 {
                    assert_eq!(
                        drawn.rows.len(),
                        n,
                        "rows dropped at {frame:?} with {n} rows"
                    );
                }
                let last = drawn.rows.last().expect("a row");
                assert!(
                    last.bottom() <= drawn.bounds.bottom() + 0.5,
                    "last row {:?} leaves the panel {:?}",
                    last,
                    drawn.bounds
                );
            }
        }
    }

    #[test]
    fn server_info_rows_never_overlap_and_stay_inside_the_panel() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        for frame in SIZES {
            for n in [1usize, 2, 3, 8, 13, 24] {
                let mut list = DrawList::new();
                let drawn = draw_server_info(
                    &mut list,
                    &mut fonts,
                    frame,
                    &theme::DARK,
                    "server",
                    &sample_info(n),
                )
                .expect("panel");

                let mut prev: Option<Rect> = None;
                for row in &drawn.rows {
                    assert!(
                        drawn.bounds.covers(*row, 0.5),
                        "row {:?} escapes panel {:?}",
                        row,
                        drawn.bounds
                    );
                    assert!(
                        row.x >= drawn.bounds.x + PAD_X - 0.5,
                        "row starts left of the content inset"
                    );
                    assert!(row.w > 0.0 && row.h > 0.0, "empty row rect {row:?}");
                    if let Some(prev) = prev {
                        assert!(row.y > prev.y, "row y did not advance: {prev:?} -> {row:?}");
                        assert!(
                            row.y - prev.y >= prev.h - 0.001,
                            "rows overlap: {prev:?} then {row:?}"
                        );
                    }
                    prev = Some(*row);
                }
            }
        }
    }

    #[test]
    fn long_server_rows_are_truncated_inside_the_frame() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        // Long enough to force truncation, short enough for `Fonts::fit` (which re-shapes a
        // shrinking candidate per character) to stay a test and not a benchmark.
        let long_label = "label ".repeat(12);
        let long_value = "value ".repeat(20);
        let info = ServerInfo {
            lines: vec![
                (long_label.clone(), long_value.clone()),
                ("daemon".to_string(), "0.23.5".to_string()),
            ],
        };
        for frame in [(800.0, 600.0), (1440.0, 900.0)] {
            let outer = frame_rect(frame);
            let mut list = DrawList::new();
            let drawn =
                draw_server_info(&mut list, &mut fonts, frame, &theme::DARK, "server", &info)
                    .expect("panel");
            // The clamp rule: content wider than the frame is cut at the frame, not pushed off it.
            assert!(
                outer.covers(drawn.bounds, 0.5),
                "clamped panel {:?} escapes {:?}",
                drawn.bounds,
                outer
            );
            let ink = vertex_bounds(&list).expect("drawn list is empty");
            assert!(
                outer.covers(ink, 1.0),
                "truncated text {:?} escapes frame {:?}",
                ink,
                outer
            );
        }
    }

    #[test]
    fn clock_is_centred_and_stacks_its_lines() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        let variants = [
            Clock {
                time: "23:59".to_string(),
                ..Clock::default()
            },
            Clock {
                time: "23:59".to_string(),
                date: "Thu 19 Oct".to_string(),
                timer: None,
            },
            Clock {
                time: "23:59".to_string(),
                date: "Thu 19 Oct".to_string(),
                timer: Some("sleep in 00:42:10".to_string()),
            },
        ];
        for frame in SIZES {
            let outer = frame_rect(frame);
            for variant in &variants {
                let mut list = DrawList::new();
                let drawn =
                    draw_clock(&mut list, &mut fonts, frame, &theme::DARK, variant).expect("clock");
                assert!(
                    !list.is_empty(),
                    "clock returned geometry but pushed nothing"
                );
                assert!(
                    outer.covers(drawn.bounds, 1.0),
                    "clock block {:?} escapes frame {:?}",
                    drawn.bounds,
                    outer
                );
                let ink = vertex_bounds(&list).expect("drawn list is empty");
                assert!(
                    outer.covers(ink, 1.0),
                    "clock ink {:?} escapes frame {:?}",
                    ink,
                    outer
                );
                // Every line shares the frame's centre line.
                for row in &drawn.rows {
                    let cx = row.x + row.w * 0.5;
                    assert!(
                        (cx - frame.0 * 0.5).abs() <= 1.0,
                        "clock line not centred: {row:?} in {frame:?}"
                    );
                    assert!(row.w > 0.0 && row.h > 0.0, "empty clock line {row:?}");
                }
                // Lines stack downward without touching.
                let mut prev: Option<Rect> = None;
                for row in &drawn.rows {
                    if let Some(prev) = prev {
                        assert!(row.y > prev.y, "clock line y did not advance");
                        assert!(
                            row.y - prev.y >= prev.h - 0.5,
                            "clock lines overlap: {prev:?} then {row:?}"
                        );
                    }
                    prev = Some(*row);
                }
                assert_eq!(
                    drawn.rows.len(),
                    1 + usize::from(!variant.date.is_empty())
                        + usize::from(variant.timer.is_some())
                );
            }
        }
    }

    #[test]
    fn gains_draw_one_pill_per_non_default_mode() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        let default = Gains::default();
        let single = [
            Gains {
                crossfade: 4,
                ..default.clone()
            },
            Gains {
                replay_gain: "album".to_string(),
                ..default.clone()
            },
            Gains {
                add_mode: true,
                ..default.clone()
            },
            Gains {
                shuffle_hint: true,
                ..default.clone()
            },
        ];
        for frame in SIZES {
            let outer = frame_rect(frame);
            for gains in &single {
                let mut list = DrawList::new();
                let drawn = draw_gains(&mut list, &mut fonts, frame, &theme::DARK, gains)
                    .expect("one chip");
                assert_eq!(
                    drawn.rows.len(),
                    1,
                    "one non-default value, chips: {gains:?}"
                );
                assert!(
                    outer.covers(drawn.bounds, 1.0),
                    "chip {:?} escapes frame {:?}",
                    drawn.bounds,
                    outer
                );
                // Bottom-right by construction.
                assert!(
                    (drawn.bounds.right() - (frame.0 - GEOM.pad)).abs() <= 0.5,
                    "strip is not flush with the right padding: {:?}",
                    drawn.bounds
                );
                assert!(
                    (drawn.bounds.bottom() - (frame.1 - GEOM.pad)).abs() <= 0.5,
                    "strip is not flush with the bottom padding: {:?}",
                    drawn.bounds
                );
                // A pill has to be tall enough for its caption, and the radius token has to fit.
                assert!(drawn.bounds.h >= line_h(TYPE.caption));
                assert!(drawn.bounds.h <= GEOM.radius_pill * 2.0);
                let ink = vertex_bounds(&list).expect("drawn list is empty");
                assert!(
                    outer.covers(ink, 1.0),
                    "chip ink {:?} escapes frame {:?}",
                    ink,
                    outer
                );
            }

            // Every mode at once: four chips, left to right, CHIP_GAP apart, never overlapping.
            let all = Gains {
                crossfade: 8,
                replay_gain: "track".to_string(),
                add_mode: true,
                shuffle_hint: true,
            };
            let mut list = DrawList::new();
            let drawn =
                draw_gains(&mut list, &mut fonts, frame, &theme::DARK, &all).expect("four chips");
            assert_eq!(drawn.rows.len(), 4);
            let mut prev: Option<Rect> = None;
            for row in &drawn.rows {
                if let Some(prev) = prev {
                    assert!(
                        row.x - prev.right() >= CHIP_GAP - 0.001,
                        "chips violate the gap: {prev:?} then {row:?}"
                    );
                    assert!(row.y == prev.y, "chips are not on one baseline");
                }
                prev = Some(*row);
            }
            assert!(
                drawn.bounds.covers(*drawn.rows.last().unwrap(), 0.5)
                    && (drawn.bounds.right() - drawn.rows.last().unwrap().right()).abs() <= 0.5
            );
            let ink = vertex_bounds(&list).expect("drawn list is empty");
            assert!(
                outer.covers(ink, 1.0),
                "strip ink {:?} escapes {:?}",
                ink,
                outer
            );
        }
    }

    #[test]
    fn empty_and_degenerate_inputs_draw_nothing() {
        let Some(mut fonts) = fonts_or_skip() else {
            return;
        };
        let dark = &theme::DARK;
        let mut list = DrawList::new();

        // An empty table, with and without a header, is not a panel.
        for title in ["server", ""] {
            assert!(draw_server_info(
                &mut list,
                &mut fonts,
                (1440.0, 900.0),
                dark,
                title,
                &ServerInfo::default()
            )
            .is_none());
            assert!(list.is_empty(), "empty ServerInfo pushed primitives");
        }

        // A clock with no fields is not a clock; blanks count as empty.
        for clock in [
            Clock::default(),
            Clock {
                time: String::new(),
                date: "  ".to_string(),
                timer: Some(String::new()),
            },
        ] {
            assert!(draw_clock(&mut list, &mut fonts, (1440.0, 900.0), dark, &clock).is_none());
            assert!(list.is_empty(), "empty Clock pushed primitives");
        }

        // All-default modes mean no strip at all.
        assert!(draw_gains(
            &mut list,
            &mut fonts,
            (1440.0, 900.0),
            dark,
            &Gains::default()
        )
        .is_none());
        assert!(list.is_empty(), "default Gains pushed primitives");

        // A frame that cannot hold a readable overlay gets nothing drawn into it.
        let tiny = (120.0, 60.0);
        assert!(
            draw_server_info(&mut list, &mut fonts, tiny, dark, "server", &sample_info(3))
                .is_none()
        );
        assert!(draw_clock(
            &mut list,
            &mut fonts,
            tiny,
            dark,
            &Clock {
                time: "23:59".to_string(),
                ..Clock::default()
            }
        )
        .is_none());
        assert!(draw_gains(
            &mut list,
            &mut fonts,
            tiny,
            dark,
            &Gains {
                crossfade: 4,
                ..Gains::default()
            }
        )
        .is_none());
        assert!(list.is_empty(), "degenerate frame pushed primitives");
    }

    #[test]
    fn gains_chips_follow_the_default_rules() {
        // "off" in any casing and an empty string are both the neutral replay gain; anything else
        // earns a chip. Crossfade needs to be positive.
        let cases = [
            (Gains::default(), 0usize),
            (
                Gains {
                    replay_gain: "off".to_string(),
                    ..Gains::default()
                },
                0,
            ),
            (
                Gains {
                    replay_gain: "OFF".to_string(),
                    ..Gains::default()
                },
                0,
            ),
            (
                Gains {
                    crossfade: 0,
                    ..Gains::default()
                },
                0,
            ),
            (
                Gains {
                    crossfade: 3,
                    ..Gains::default()
                },
                1,
            ),
            (
                Gains {
                    replay_gain: "track".to_string(),
                    ..Gains::default()
                },
                1,
            ),
            (
                Gains {
                    add_mode: true,
                    shuffle_hint: true,
                    ..Gains::default()
                },
                2,
            ),
        ];
        for (gains, expected) in cases {
            assert_eq!(gains.chips().len(), expected, "chips for {gains:?}");
        }
    }
}
