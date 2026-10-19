//! Text shaping (cosmic-text) and glyph rasterisation into a CPU-side alpha atlas.
//!
//! The face is the user's own Iosevka build (`~/.local/share/fonts/iosevka-neg`), loaded by
//! absolute path: the family name "Iosevka" is shared with a different build in the nix store,
//! so resolving by name would pick the wrong binary. Only these files are registered, which also
//! removes the fontconfig alias that made every generic family resolve to Iosevka anyway.
//!
//! Shaping is cosmic-text's job (it owns the buffer, the fallback chain and the metrics);
//! rasterisation is swash's, called directly rather than through cosmic-text's `SwashCache`.
//! The cache has two behaviours this UI cannot live with: it hints against a *fractional* font
//! size (a hinter grid-fits onto pixels of the size it is handed, so 13 px at 1.75x — 22.75 —
//! is hinted onto nothing) and it bakes a quarter-pixel subpixel phase into every bitmap, which
//! then gets rounded to a whole pixel on screen. Together they smear every stem across two
//! pixels. Rasterising here instead gives one bitmap per whole-pixel ppem, phase zero, drawn at
//! whole-pixel origins — the arrangement FreeType-based toolkits use.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

use cosmic_text::fontdb;
use cosmic_text::{Attrs, Buffer, Family, FontSystem, Metrics, Shaping, Weight, Wrap};
use swash::scale::image::Image as SwashImage;
use swash::scale::{Render, ScaleContext, Source, StrikeWith};
use swash::zeno::{Format, Vector};

use crate::scene::{Atlas, DrawList};
use crate::theme::Face;

/// Whether glyphs are grid-fitted. On, stems snap to whole pixels, which is what makes 11–18 px
/// text crisp — and what makes it heavier than the outline it came from. Off, the outline keeps
/// its fractional stem widths and small text goes grey. `PLAYER_TEXT_HINT=0|1` overrides it, so
/// one capture can be taken both ways.
fn hinted() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| {
        std::env::var("PLAYER_TEXT_HINT")
            .map(|v| v != "0")
            .unwrap_or(true)
    })
}

/// The user's Iosevka, in the weights the UI actually uses. Iosevka is monospaced, so the
/// "mono" faces are the same family: the design relies on tabular digits everywhere.
const IOSEVKA_WEIGHTS: [(&str, Weight); 3] = [
    ("Iosevkaneg-Regular.ttf", Weight::NORMAL),
    ("Iosevkaneg-Medium.ttf", Weight::MEDIUM),
    ("Iosevkaneg-Bold.ttf", Weight::BOLD),
];

fn iosevka_sources() -> Option<Vec<fontdb::Source>> {
    let home = std::env::var_os("HOME")?;
    let dir = PathBuf::from(home).join(".local/share/fonts/iosevka-neg");
    let files: Vec<PathBuf> = IOSEVKA_WEIGHTS
        .iter()
        .map(|(name, _)| dir.join(name))
        .filter(|p| p.is_file())
        .collect();
    if files.len() < 2 {
        return None;
    }
    Some(files.into_iter().map(fontdb::Source::File).collect())
}

#[derive(Clone, Copy, Default)]
struct GlyphPlacement {
    uv: Option<[f32; 4]>,
    w: u32,
    h: u32,
    left: i32,
    top: i32,
}

/// Glyph identity plus the whole-pixel size it was rasterised at. There is no subpixel phase in
/// the key because there is no subpixel phase: a glyph is drawn at a whole device pixel, so one
/// bitmap serves every occurrence at that size.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct GlyphKey {
    font: fontdb::ID,
    glyph: u16,
    ppem_bits: u32,
}

pub struct Fonts {
    pub font_system: FontSystem,
    pub atlas: Atlas,
    /// Bumped whenever new glyphs were added to the atlas, so the GPU copy can be refreshed.
    pub atlas_dirty: bool,
    /// GlyphKey -> atlas rect + placement. Without this the atlas would be re-filled every
    /// frame and would fill up (and then stop drawing text entirely) within seconds.
    /// Placements are kept in *physical* pixels, exactly as the atlas stores them.
    glyph_cache: HashMap<GlyphKey, GlyphPlacement>,
    /// Swash's scaler state. Only the render thread rasterises, so one context is enough.
    scaler: ScaleContext,
    /// Device pixels per logical unit. Glyphs are rasterised at `size * scale` and drawn at
    /// whole-pixel origins, so text is crisp at 1x, 2x and every fractional scale in between.
    scale: f32,
}

impl Fonts {
    pub fn new() -> Self {
        let font_system = match iosevka_sources() {
            Some(sources) => FontSystem::new_with_fonts(sources),
            None => {
                eprintln!("[fonts] ~/.local/share/fonts/iosevka-neg not found, falling back to system fonts");
                FontSystem::new()
            }
        };
        if !font_system
            .db()
            .faces()
            .any(|f| f.families.iter().any(|(n, _)| n == "Iosevka"))
        {
            eprintln!("[fonts] family Iosevka not found in the loaded set");
        }
        Self {
            font_system,
            atlas: Atlas::new(),
            atlas_dirty: false,
            glyph_cache: HashMap::new(),
            scaler: ScaleContext::new(),
            scale: 1.0,
        }
    }

    /// Rasterise one glyph at a whole device ppem with no subpixel offset, so the bitmap is the
    /// exact pixels that go on screen.
    fn raster(&mut self, font_id: fontdb::ID, glyph_id: u16, ppem: f32) -> Option<SwashImage> {
        let font = self.font_system.get_font(font_id)?;
        let mut scaler = self
            .scaler
            .builder(font.as_swash())
            .size(ppem)
            .hint(hinted())
            .build();
        Render::new(&[
            Source::ColorOutline(0),
            Source::ColorBitmap(StrikeWith::BestFit),
            Source::Outline,
        ])
        .format(Format::Alpha)
        .offset(Vector::new(0.0, 0.0))
        .render(&mut scaler, glyph_id)
    }

    fn attrs(face: Face) -> Attrs<'static> {
        // One family, three weights: Iosevka carries the UI, the digits and the symbols.
        let weight = match face {
            Face::UiRegular | Face::Mono | Face::Symbols => Weight::NORMAL,
            Face::UiMedium | Face::MonoMedium => Weight::MEDIUM,
            Face::UiSemiBold => Weight::BOLD,
        };
        Attrs::new().family(Family::Name("Iosevka")).weight(weight)
    }

    pub fn set_scale(&mut self, scale: f32) {
        // No atlas reset here on purpose. A new scale simply misses the cache (the ppem is part
        // of the key) and adds new bitmaps next to the old ones, which is what makes a resize
        // storm harmless: the ratio moves by a fraction of a percent from frame to frame while
        // the compositor settles, and clearing the atlas on every such step would re-rasterise
        // every glyph and leave the frame half-drawn. The atlas is recycled only when it is
        // actually full — see `placement`.
        self.scale = scale.max(0.5);
    }

    /// Atlas slot for one glyph. A glyph with no ink (a space) has no slot and that is not an
    /// error; a glyph that *has* ink but got no slot means the atlas is full, and then — and only
    /// then — the atlas is recycled. Retried once, because after a reset the same glyph is alone
    /// in a fresh atlas.
    fn placement(&mut self, key: GlyphKey, ppem: f32) -> GlyphPlacement {
        if let Some(p) = self.glyph_cache.get(&key) {
            return *p;
        }
        let (mut p, full) = self.raster_into(key, ppem);
        if full {
            // Full: the bitmaps of the sizes nothing draws any more are the ones to lose.
            self.atlas = Atlas::new();
            self.glyph_cache.clear();
            self.atlas_dirty = true;
            p = self.raster_into(key, ppem).0;
        }
        self.glyph_cache.insert(key, p);
        p
    }

    /// Rasterise one glyph into the atlas. The flag says whether the atlas refused the bitmap.
    fn raster_into(&mut self, key: GlyphKey, ppem: f32) -> (GlyphPlacement, bool) {
        let mut p = GlyphPlacement::default();
        if let Some(image) = self.raster(key.font, key.glyph, ppem) {
            let (gw, gh) = (image.placement.width, image.placement.height);
            if gw > 0 && gh > 0 && matches!(image.content, swash::scale::image::Content::Mask) {
                p.w = gw;
                p.h = gh;
                p.left = image.placement.left;
                p.top = image.placement.top;
                p.uv = self.atlas.insert(gw, gh, &image.data, gw);
                match p.uv {
                    Some(_) => self.atlas_dirty = true,
                    None => return (p, true),
                }
            }
        }
        (p, false)
    }

    /// Snap a logical coordinate to the physical pixel grid.
    #[allow(dead_code)]
    fn snap(&self, v: f32) -> f32 {
        (v * self.scale).round() / self.scale
    }

    fn buffer(&mut self, text: &str, size: f32, face: Face) -> Buffer {
        let metrics = Metrics::new(size, size * 1.32);
        let mut buffer = Buffer::new(&mut self.font_system, metrics);
        buffer.set_size(&mut self.font_system, Some(f32::INFINITY), Some(size * 2.0));
        buffer.set_wrap(&mut self.font_system, Wrap::None);
        let attrs = Self::attrs(face);
        buffer.set_text(&mut self.font_system, text, &attrs, Shaping::Advanced);
        buffer.shape_until_scroll(&mut self.font_system, false);
        buffer
    }

    /// Full run width in pixels (shapes the text; cheap at UI sizes).
    pub fn measure(&mut self, text: &str, size: f32, face: Face) -> f32 {
        let buffer = self.buffer(text, size, face);
        buffer
            .layout_runs()
            .flat_map(|run| run.glyphs.iter().map(|g| g.w))
            .sum()
    }

    /// Truncate with an ellipsis so the text fits `max_w` pixels.
    pub fn fit(&mut self, text: &str, size: f32, max_w: f32, face: Face) -> String {
        if max_w <= 0.0 || self.measure(text, size, face) <= max_w {
            return text.to_string();
        }
        let mut chars: Vec<char> = text.chars().collect();
        while !chars.is_empty() {
            chars.pop();
            let candidate: String = chars.iter().collect::<String>() + "…";
            if self.measure(&candidate, size, face) <= max_w {
                return candidate;
            }
        }
        String::new()
    }

    /// Like [`Self::fit`], but keeps the tail of the string: track titles share long prefixes
    /// ("CD VII. …"), so cutting from the front-middle keeps them distinguishable.
    pub fn fit_middle(&mut self, text: &str, size: f32, max_w: f32, face: Face) -> String {
        if max_w <= 0.0 || self.measure(text, size, face) <= max_w {
            return text.to_string();
        }
        let chars: Vec<char> = text.chars().collect();
        let mut keep = chars.len().saturating_sub(1);
        while keep > 2 {
            let head = (keep + 1) / 2;
            let tail = keep - head;
            let candidate: String = chars[..head].iter().collect::<String>()
                + "…"
                + &chars[chars.len() - tail..].iter().collect::<String>();
            if self.measure(&candidate, size, face) <= max_w {
                return candidate;
            }
            keep -= 1;
        }
        self.fit(text, size, max_w, face)
    }

    /// Shape a single line and emit one quad per glyph. Returns the advanced width.
    pub fn layout_line(
        &mut self,
        list: &mut DrawList,
        text: &str,
        x: f32,
        y: f32,
        size: f32,
        face: Face,
        color: [f32; 4],
    ) -> f32 {
        let buffer = self.buffer(text, size, face);
        let mut width: f32 = 0.0;
        // The layout is logical, the surface is physical. Two rules make the result crisp at
        // any device scale, fractional ones included:
        //
        // 1. The bitmap is rasterised at a *whole* device ppem. A hinter grid-fits stems onto
        //    pixels of the size it is given, so a fractional ppem (13 px at 1.75x is 22.75) gets
        //    hinted onto a 22.75 px grid, i.e. onto nothing — every stem keeps a fractional
        //    width and comes out grey. Rounding the ppem is what gives a 22 or 23 px bitmap with
        //    integer stems. The advance stays the exact fractional one from the layout, so the
        //    text keeps its size and its letter spacing; only the bitmap is quantised.
        // 2. No subpixel phase, and the origin is a whole device pixel. cosmic-text can bin a
        //    glyph to a quarter-pixel phase and bake that phase into the bitmap; drawing that
        //    bitmap at yet another rounded origin is how a renderer ends up with every stem
        //    smeared over two pixels. Zero phase plus an integer origin means the bitmap lands
        //    1:1 on the surface — no resampling anywhere in the path.
        let ppem = (size * self.scale).round().max(1.0);
        let inv = 1.0 / self.scale;
        for run in buffer.layout_runs() {
            for glyph in run.glyphs.iter() {
                let key = GlyphKey {
                    font: glyph.font_id,
                    glyph: glyph.glyph_id,
                    ppem_bits: ppem.to_bits(),
                };
                let placement = self.placement(key, ppem);
                if let Some(uv) = placement.uv {
                    // Baseline and pen position in device pixels, both rounded to whole ones;
                    // the bearings (`left`/`top`) are already whole device pixels themselves.
                    let pen = x + glyph.x + glyph.font_size * glyph.x_offset;
                    let baseline = y + run.line_y + (glyph.y - glyph.font_size * glyph.y_offset);
                    let dx = (pen * self.scale).round() + placement.left as f32;
                    let dy = (baseline * self.scale).round() - placement.top as f32;
                    list.glyph(
                        dx * inv,
                        dy * inv,
                        placement.w as f32 * inv,
                        placement.h as f32 * inv,
                        uv,
                        color,
                    );
                }
            }
            width = width.max(run.line_w);
        }
        width
    }

    /// Convenience: fit + layout one line inside `max_w`, returns the width used.
    /// Truncate from the end. Used where the tail carries no information (song titles in the
    /// now-playing block) - middle truncation is only for lists with shared prefixes.
    pub fn layout_fitted_end(
        &mut self,
        list: &mut DrawList,
        text: &str,
        x: f32,
        y: f32,
        size: f32,
        face: Face,
        color: [f32; 4],
        max_w: f32,
    ) -> f32 {
        let fitted = self.fit(text, size, max_w, face);
        self.layout_line(list, &fitted, x, y, size, face, color)
    }

    pub fn layout_fitted(
        &mut self,
        list: &mut DrawList,
        text: &str,
        x: f32,
        y: f32,
        size: f32,
        face: Face,
        color: [f32; 4],
        max_w: f32,
    ) -> f32 {
        let fitted = self.fit_middle(text, size, max_w, face);
        self.layout_line(list, &fitted, x, y, size, face, color)
    }
}
