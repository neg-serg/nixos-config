//! Text shaping (cosmic-text) and glyph rasterisation into a CPU-side alpha atlas.

use std::collections::HashMap;

use cosmic_text::{
    Attrs, Buffer, CacheKey, Family, FontSystem, Metrics, Shaping, SwashCache, Weight, Wrap,
};

use crate::theme::Face;

/// Families we prefer, in order. Both are installed on this host; if neither resolves the
/// shaper falls back to the generic sans/mono families, so the app still works elsewhere.
const UI_FAMILIES: [&str; 3] = ["Inter", "Inter Display", "DejaVu Sans"];
/// JetBrains Mono's digits are exactly 0.600 em, so timers stop jittering; Inter's are
/// proportional (1 = 0.4067 em vs 4 = 0.6460 em), and cosmic-text 0.14 cannot enable `tnum`.
const MONO_FAMILIES: [&str; 3] = [
    "JetBrainsMono Nerd Font",
    "FiraCode Nerd Font Mono",
    "DejaVu Sans Mono",
];
/// Geometric symbols (▸ ▮ ◀ ▶ ♪) are missing from Inter and from JetBrains Mono; DejaVu Sans is
/// the only family on this host that covers all of them.
const SYMBOL_FAMILIES: [&str; 2] = ["DejaVu Sans", "DejaVu Sans Mono"];

use crate::scene::{Atlas, DrawList};

#[derive(Clone, Copy, Default)]
struct GlyphPlacement {
    uv: Option<[f32; 4]>,
    w: u32,
    h: u32,
    left: i32,
    top: i32,
}

pub struct Fonts {
    pub font_system: FontSystem,
    pub swash: SwashCache,
    pub atlas: Atlas,
    /// Bumped whenever new glyphs were added to the atlas, so the GPU copy can be refreshed.
    pub atlas_dirty: bool,
    /// CacheKey -> atlas rect + placement. Without this the atlas would be re-filled every
    /// frame and would fill up (and then stop drawing text entirely) within seconds.
    glyph_cache: HashMap<CacheKey, GlyphPlacement>,
}

impl Fonts {
    pub fn new() -> Self {
        let font_system = FontSystem::new();
        for fam in UI_FAMILIES
            .iter()
            .chain(MONO_FAMILIES.iter())
            .chain(SYMBOL_FAMILIES.iter())
        {
            if !font_system
                .db()
                .faces()
                .any(|f| f.families.iter().any(|(n, _)| n == fam))
            {
                eprintln!("[fonts] family not installed: {fam}");
            }
        }
        Self {
            font_system,
            swash: SwashCache::new(),
            atlas: Atlas::new(),
            atlas_dirty: false,
            glyph_cache: HashMap::new(),
        }
    }

    fn attrs(face: Face) -> Attrs<'static> {
        let (families, weight): (&[&'static str], Weight) = match face {
            Face::UiRegular => (&UI_FAMILIES[..], Weight::NORMAL),
            Face::UiMedium => (&UI_FAMILIES[..], Weight::MEDIUM),
            Face::UiSemiBold => (&UI_FAMILIES[..], Weight::SEMIBOLD),
            Face::Mono => (&MONO_FAMILIES[..], Weight::NORMAL),
            Face::MonoMedium => (&MONO_FAMILIES[..], Weight::MEDIUM),
            Face::Symbols => (&SYMBOL_FAMILIES[..], Weight::NORMAL),
        };
        // Family names are &'static str, so borrowing them into Attrs<'static> is sound.
        Attrs::new()
            .family(Family::Name(families[0]))
            .weight(weight)
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
        for run in buffer.layout_runs() {
            for glyph in run.glyphs.iter() {
                let physical = glyph.physical((0.0, 0.0), 1.0);
                let key = physical.cache_key;
                let placement = match self.glyph_cache.get(&key) {
                    Some(p) => *p,
                    None => {
                        let mut p = GlyphPlacement::default();
                        if let Some(image) = self.swash.get_image(&mut self.font_system, key) {
                            let (gw, gh) = (image.placement.width, image.placement.height);
                            if gw > 0
                                && gh > 0
                                && matches!(image.content, cosmic_text::SwashContent::Mask)
                            {
                                p.w = gw;
                                p.h = gh;
                                p.left = image.placement.left;
                                p.top = image.placement.top;
                                p.uv = self.atlas.insert(gw, gh, &image.data, gw);
                                if p.uv.is_some() {
                                    self.atlas_dirty = true;
                                }
                            }
                        }
                        self.glyph_cache.insert(key, p);
                        p
                    }
                };
                if let Some(uv) = placement.uv {
                    let gx = x + physical.x as f32 + placement.left as f32;
                    let gy = y + run.line_y + physical.y as f32 - placement.top as f32;
                    list.glyph(gx, gy, placement.w as f32, placement.h as f32, uv, color);
                }
            }
            width = width.max(run.line_w);
        }
        width
    }

    /// Convenience: fit + layout one line inside `max_w`, returns the width used.
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
        let fitted = self.fit(text, size, max_w, face);
        self.layout_line(list, &fitted, x, y, size, face, color)
    }
}
