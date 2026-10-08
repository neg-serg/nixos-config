//! What the shader is told: the lamp's handles, laid out the way std140 wants.

use crate::drawing::{number_after, Drawing};
use anyhow::Result;

/// A colour as the theme stores it: #AARRGGBB.
pub fn colour(token: &str) -> [f32; 4] {
    let hex = token.trim_start_matches('#');
    let (a, r, g, b) = if hex.len() == 8 {
        (&hex[0..2], &hex[2..4], &hex[4..6], &hex[6..8])
    } else {
        ("ff", &hex[0..2], &hex[2..4], &hex[4..6])
    };
    let v = |s: &str| u8::from_str_radix(s, 16).unwrap_or(0) as f32 / 255.0;
    [v(r), v(g), v(b), v(a)]
}

/// The block declared in nixie.frag, minus Qt's two members.
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Uniforms {
    pub size: [f32; 2],
    pub backdrop: [f32; 2],
    pub inset: f32,
    pub radius: f32,
    pub base: f32,
    pub glow: f32,
    pub digit: f32,
    pub bulb: f32,
    pub wire: f32,
    pub stack: f32,
    pub highlight: f32,
    pub warmth: f32,
    pub flicker: f32,
    // std140 puts the vec4s on a 16-byte boundary: eleven floats take 44 bytes,
    // so four bytes of padding keep Rust and the shader reading the same block
    pub pad0: f32,
    pub core: [f32; 4],
    pub halo: [f32; 4],
    pub glass: [f32; 4],
    pub cathode: [f32; 4],
    pub thick: f32,
    pub mm: f32,
    pub refract: f32,
    pub pad1: f32, // std140: the block's size is a multiple of 16
}

/// The knobs in Theme/greeter.jsonc that are numbers. They are read from the
/// theme and not written into this file twice: the login screen turns them, and
/// a copy here would quietly disagree with what it shows.
#[derive(Debug, Clone, Copy)]
pub struct Tokens {
    pub wire: f32,
    pub stack: f32,
    pub highlight: f32,
    pub warmth: f32,
}

impl Tokens {
    pub fn read(theme: &str) -> Result<Self> {
        Ok(Self {
            wire: number_after(theme, "\"nixieWire\": ")? as f32,
            stack: number_after(theme, "\"nixieStack\": ")? as f32,
            highlight: number_after(theme, "\"nixieHighlight\": ")? as f32,
            warmth: number_after(theme, "\"nixieWarmth\": ")? as f32,
        })
    }
}

impl Uniforms {
    /// The values the login screen's theme hands the tube, unless a handle says
    /// otherwise: `nixieGlow`, `nixieHighlight`, `nixieWarmth` and the four
    /// colours in Theme/greeter.jsonc.
    pub fn from_drawing(d: &Drawing, t: &Tokens, mm: f32, size: [f32; 2], digit: i32) -> Self {
        Self {
            size,
            backdrop: size,
            inset: 16.0,
            radius: d.bulb_r as f32 * mm,
            base: 7.0 * mm,
            glow: 1.0,
            digit: digit as f32,
            bulb: 0.0,
            wire: t.wire,
            stack: t.stack,
            highlight: t.highlight,
            warmth: t.warmth,
            flicker: 1.0,
            pad0: 0.0,
            core: colour("#ffa04b"),
            halo: colour("#ff5a10"),
            glass: colour("#4d120b06"),
            cathode: colour("#aab6c4"),
            thick: 0.9 * mm,
            mm,
            refract: 1.0,
            pad1: 0.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The block has to land on the same offsets the shader declares: std140
    /// rounds each vec4 up to a 16-byte boundary and the whole block too.
    #[test]
    fn the_block_is_std140() {
        use std::mem::{align_of, size_of};
        assert_eq!(
            size_of::<Uniforms>() % 16,
            0,
            "the block must be a multiple of 16"
        );
        assert!(align_of::<Uniforms>() <= 16);
        let base = Uniforms {
            size: [0.0; 2],
            backdrop: [0.0; 2],
            inset: 0.0,
            radius: 0.0,
            base: 0.0,
            glow: 0.0,
            digit: 0.0,
            bulb: 0.0,
            wire: 0.0,
            stack: 0.0,
            highlight: 0.0,
            warmth: 0.0,
            flicker: 0.0,
            pad0: 0.0,
            core: [0.0; 4],
            halo: [0.0; 4],
            glass: [0.0; 4],
            cathode: [0.0; 4],
            thick: 0.0,
            mm: 0.0,
            refract: 0.0,
            pad1: 0.0,
        };
        let offset = |field: *const f32| field as usize - &base as *const _ as usize;
        assert_eq!(offset(base.core.as_ptr()), 64, "pCore must sit at 64");
        assert_eq!(offset(base.halo.as_ptr()), 80);
        assert_eq!(offset(base.glass.as_ptr()), 96);
        assert_eq!(offset(base.cathode.as_ptr()), 112);
        assert_eq!(offset(&base.thick as *const f32), 128);
    }
}
