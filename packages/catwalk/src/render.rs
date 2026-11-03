// All drawing goes through these helpers: world coordinates in, physical
// pixels out. Integer scale plus nearest sampling is what keeps the painting
// pixel-exact.

use sdl2::pixels::Color;
use sdl2::rect::Rect as SdlRect;
use sdl2::render::{Canvas, RenderTarget, Texture};

use crate::font;
use crate::math::Rect;

#[derive(Clone, Copy, Default)]
pub struct Cam {
    pub x: f32,
    pub y: f32,
}

pub fn screen(cam: Cam, scale: i32, x: f32, y: f32) -> (i32, i32) {
    (
        ((x - cam.x) * scale as f32).round() as i32,
        ((y - cam.y) * scale as f32).round() as i32,
    )
}

pub fn fill_rect<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    r: Rect,
    col: Color,
) -> Result<(), String> {
    let (x, y) = screen(cam, scale, r.x, r.y);
    let w = (r.w * scale as f32).round().max(1.0) as u32;
    let h = (r.h * scale as f32).round().max(1.0) as u32;
    canvas.set_draw_color(col);
    canvas.fill_rect(SdlRect::new(x, y, w, h))
}

pub fn fill_rects<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    rects: &[Rect],
    col: Color,
) -> Result<(), String> {
    let converted: Vec<SdlRect> = rects
        .iter()
        .map(|r| {
            let (x, y) = screen(cam, scale, r.x, r.y);
            SdlRect::new(
                x,
                y,
                (r.w * scale as f32).round().max(1.0) as u32,
                (r.h * scale as f32).round().max(1.0) as u32,
            )
        })
        .collect();
    canvas.set_draw_color(col);
    canvas.fill_rects(&converted)
}

pub fn draw_texture_frame<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    texture: &Texture,
    src: SdlRect,
    dst: Rect,
    flip_h: bool,
) -> Result<(), String> {
    let (x, y) = screen(cam, scale, dst.x, dst.y);
    let w = (dst.w * scale as f32).round().max(1.0) as u32;
    let h = (dst.h * scale as f32).round().max(1.0) as u32;
    canvas.copy_ex(
        texture,
        Some(src),
        Some(SdlRect::new(x, y, w, h)),
        0.0,
        None,
        flip_h,
        false,
    )
}

pub fn text<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    x: f32,
    y: f32,
    text: &str,
    px: i32,
    col: Color,
) -> Result<(), String> {
    let mut rects = Vec::new();
    let mut cx = x;
    for ch in text.chars() {
        if let Some(glyph) = font::glyph(ch) {
            for (row, bits) in glyph.iter().enumerate() {
                for col_bit in 0..font::GLYPH_W {
                    if bits & (1 << (font::GLYPH_W - 1 - col_bit) as u8) != 0 {
                        rects.push(Rect::new(
                            cx + (col_bit * px) as f32,
                            y + (row as i32 * px) as f32,
                            px as f32,
                            px as f32,
                        ));
                    }
                }
            }
        }
        cx += ((font::GLYPH_W + 1) * px) as f32;
    }
    fill_rects(canvas, cam, scale, &rects, col)
}

/// Text with a one-pixel ink drop shadow, so it stays readable on clouds and
/// on the waterfall alike.
pub fn text_shadow<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    x: f32,
    y: f32,
    content: &str,
    px: i32,
    col: Color,
    shadow: Color,
) -> Result<(), String> {
    text(
        canvas,
        cam,
        scale,
        x + px as f32,
        y + px as f32,
        content,
        px,
        shadow,
    )?;
    text(canvas, cam, scale, x, y, content, px, col)
}

pub fn text_right<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    right_x: f32,
    y: f32,
    content: &str,
    px: i32,
    col: Color,
    shadow: Color,
) -> Result<(), String> {
    let width = font::text_width(content, px) as f32;
    text_shadow(
        canvas,
        cam,
        scale,
        right_x - width,
        y,
        content,
        px,
        col,
        shadow,
    )
}

pub fn text_centered<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    center_x: f32,
    y: f32,
    content: &str,
    px: i32,
    col: Color,
    shadow: Color,
) -> Result<(), String> {
    let width = font::text_width(content, px) as f32;
    text_shadow(
        canvas,
        cam,
        scale,
        center_x - width * 0.5,
        y,
        content,
        px,
        col,
        shadow,
    )
}

/// Pixel ring built from small squares: a circle without antialiasing.
pub fn ring<RT: RenderTarget>(
    canvas: &mut Canvas<RT>,
    cam: Cam,
    scale: i32,
    center: (f32, f32),
    radius: f32,
    thickness: f32,
    segments: usize,
    col: Color,
) -> Result<(), String> {
    let mut rects = Vec::with_capacity(segments);
    for i in 0..segments {
        let a = std::f32::consts::TAU * i as f32 / segments as f32;
        rects.push(Rect::new(
            center.0 + a.cos() * radius - thickness * 0.5,
            center.1 + a.sin() * radius - thickness * 0.5,
            thickness,
            thickness,
        ));
    }
    fill_rects(canvas, cam, scale, &rects, col)
}
