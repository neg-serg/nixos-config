//! Text shaping (cosmic-text) and glyph rasterisation into a CPU-side alpha atlas.
//!
//! The face is the user's own Iosevka build (`~/.local/share/fonts/iosevka-neg`), loaded by
//! absolute path: the family name "Iosevka" is shared with a different build in the nix store,
//! so resolving by name would pick the wrong binary. Only these files are registered, which also
//! removes the fontconfig alias that made every generic family resolve to Iosevka anyway.

use std::collections::HashMap;
use std::path::PathBuf;

use cosmic_text::fontdb;
use cosmic_text::{
    Attrs, Buffer, CacheKey, Family, FontSystem, Metrics, Shaping, SwashCache, Weight, Wrap,
};

use crate::scene::{Atlas, DrawList};
use crate::theme::Face;

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

pub struct Fonts {
    pub font_system: FontSystem,
    pub swash: SwashCache,
    pub atlas: Atlas,
    /// Bumped whenever new glyphs were added to the atlas, so the GPU copy can be refreshed.
    pub atlas_dirty: bool,
    /// CacheKey -> atlas rect + placement. Without this the atlas would be re-filled every
    /// frame and would fill up (and then stop drawing text entirely) within seconds.
    glyph_cache: HashMap<CacheKey, GlyphPlacement>,
    /// Physical pixels per logical unit; glyph positions are snapped to this grid so text stays
    /// crisp on a 2x panel instead of landing on half pixels.
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
            swash: SwashCache::new(),
            atlas: Atlas::new(),
            atlas_dirty: false,
            glyph_cache: HashMap::new(),
            scale: 1.0,
        }
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
        self.scale = scale.max(0.5);
    }

    /// Snap a logical coordinate to the physical pixel grid.
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
                    let gx = self.snap(x + physical.x as f32 + placement.left as f32);
                    let gy = self.snap(y + run.line_y + physical.y as f32 - placement.top as f32);
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
