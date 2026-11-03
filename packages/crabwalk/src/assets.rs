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
const CRAB_PNG: &[u8] = include_bytes!("../assets/crab.png");

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
    pub crab: Texture<'a>,
    pub crab_w: f32,
    pub crab_h: f32,
    pub palette: Palette,
    pub falls: Vec<FallColumn>,
    pub shimmer: Vec<Shimmer>,
}

impl<'a> Assets<'a> {
    pub fn load(creator: &'a TextureCreator<WindowContext>) -> Result<Self, String> {
        let decoded = image::load_from_memory(WORLD_JPG).map_err(|e| e.to_string())?;
        let rgba = decoded.to_rgba8();
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

        let crab_image = image::load_from_memory(CRAB_PNG).map_err(|e| e.to_string())?;
        let crab_rgba = crab_image.to_rgba8();
        let (cw, ch) = crab_rgba.dimensions();
        let mut crab = creator
            .create_texture(PixelFormatEnum::RGBA32, TextureAccess::Static, cw, ch)
            .map_err(|e| e.to_string())?;
        crab.update(None, crab_rgba.as_raw(), (cw * 4) as usize)
            .map_err(|e| e.to_string())?;
        crab.set_blend_mode(sdl2::render::BlendMode::Blend);

        Ok(Self {
            world: texture,
            crab,
            crab_w: cw as f32,
            crab_h: ch as f32,
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
