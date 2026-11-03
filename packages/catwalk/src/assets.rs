// Embedded art. The background is the user's wallpaper, byte for byte; the
// mascot is cut out of it by tools/extract_crab.py. Masks for the animated
// water are derived from the same pixels at startup, so the effects only ever
// appear where the painting actually has water.

use sdl2::pixels::{Color, PixelFormatEnum};
use sdl2::render::{Texture, TextureAccess, TextureCreator};
use sdl2::video::WindowContext;

use crate::effects::{waterfall_columns, FallColumn};
use crate::math::hash01;

const WORLD_JPG: &[u8] = include_bytes!("../assets/world.jpg");
const CAT_PNG: &[u8] = include_bytes!("../assets/cat.png");
const BADNIK_PNG: &[u8] = include_bytes!("../assets/badnik.png");
// The painting's own crab sits exactly where the player spawns; this patch
// (cloned from the clean ledge by tools/make_world_patch.py) hides it so
// Sonic is the only character on the ledge. Everything else stays untouched.
const WORLD_PATCH_PNG: &[u8] = include_bytes!("../assets/world_patch.png");
const PATCH_X: i64 = 4533;
const PATCH_Y: i64 = 1772;

#[derive(Clone, Copy)]
pub struct Palette {
    pub cream: Color,
    pub ink: Color,
    pub foam: Color,
}

impl Default for Palette {
    fn default() -> Self {
        Self {
            cream: Color::RGB(246, 238, 212),
            ink: Color::RGB(10, 16, 17),
            foam: Color::RGB(214, 238, 240),
        }
    }
}

pub struct Shimmer {
    pub x: f32,
    pub y: f32,
    pub seed: u32,
}
impl Shimmer {
    pub fn phrase(&self) -> f32 {
        hash01(self.seed)
    }
}

pub struct Assets<'a> {
    pub world: Texture<'a>,
    pub cat: Texture<'a>,
    pub badnik: Texture<'a>,
    pub cat_frame_w: f32,
    pub cat_frame_h: f32,
    pub palette: Palette,
    pub falls: Vec<FallColumn>,
    pub shimmer: Vec<Shimmer>,
}

impl<'a> Assets<'a> {
    pub fn load(creator: &'a TextureCreator<WindowContext>) -> Result<Self, String> {
        let decoded = image::load_from_memory(WORLD_JPG).map_err(|e| e.to_string())?;
        let mut rgba = decoded.to_rgba8();
        let patch = image::load_from_memory(WORLD_PATCH_PNG).map_err(|e| e.to_string())?;
        image::imageops::overlay(&mut rgba, &patch.to_rgba8(), PATCH_X, PATCH_Y);
        let (w, h) = rgba.dimensions();

        let mut texture = creator
            .create_texture(PixelFormatEnum::RGBA32, TextureAccess::Static, w, h)
            .map_err(|e| e.to_string())?;
        texture
            .update(None, rgba.as_raw(), (w * 4) as usize)
            .map_err(|e| e.to_string())?;

        let rgb = decoded.to_rgb8();
        let raw = rgb.as_raw();
        let falls = waterfall_columns(raw, w as usize, h as usize);
        let shimmer = collect_shimmer(raw, w as usize, h as usize);

        // Sprite sheet: 9 frames of 40x48 (idle 0..1, run 2..5, spin 6..8).
        let cat_image = image::load_from_memory(CAT_PNG).map_err(|e| e.to_string())?;
        let cat_rgba = cat_image.to_rgba8();
        let (sw, sh) = cat_rgba.dimensions();
        let mut cat = creator
            .create_texture(PixelFormatEnum::RGBA32, TextureAccess::Static, sw, sh)
            .map_err(|e| e.to_string())?;
        cat.update(None, cat_rgba.as_raw(), (sw * 4) as usize)
            .map_err(|e| e.to_string())?;
        cat.set_blend_mode(sdl2::render::BlendMode::Blend);
        let frame_w = 40.0;
        let frame_h = 48.0;

        // Opponent sheet: 3 frames of 36x36 (hover A, hover B, destroyed).
        let badnik_image = image::load_from_memory(BADNIK_PNG).map_err(|e| e.to_string())?;
        let badnik_rgba = badnik_image.to_rgba8();
        let (bw, bh) = badnik_rgba.dimensions();
        let mut badnik = creator
            .create_texture(PixelFormatEnum::RGBA32, TextureAccess::Static, bw, bh)
            .map_err(|e| e.to_string())?;
        badnik
            .update(None, badnik_rgba.as_raw(), (bw * 4) as usize)
            .map_err(|e| e.to_string())?;
        badnik.set_blend_mode(sdl2::render::BlendMode::Blend);

        Ok(Self {
            world: texture,
            cat,
            badnik,
            cat_frame_w: frame_w,
            cat_frame_h: frame_h,
            palette: Palette::default(),
            falls,
            shimmer,
        })
    }
}

/// Points on the lake surface, used for the drifting highlights.
fn collect_shimmer(rgb: &[u8], width: usize, height: usize) -> Vec<Shimmer> {
    let mut points = Vec::new();
    let mut x = 20usize;
    while x < 4380 {
        let mut y = 1880usize;
        while y < height - 4 {
            let i = (y * width + x) * 3;
            let (r, g, b) = (rgb[i] as i32, rgb[i + 1] as i32, rgb[i + 2] as i32);
            if b > r + 12 && b > 72 && g > 60 && (b as f32) < 220.0 {
                let seed =
                    (x as u32).wrapping_mul(73_856_093) ^ (y as u32).wrapping_mul(19_349_663);
                points.push(Shimmer {
                    x: x as f32,
                    y: y as f32,
                    seed,
                });
                y += 14;
                continue;
            }
            y += 8;
        }
        x += 18;
    }
    points
}
