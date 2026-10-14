//! What the shader is told: the lamp's handles, laid out the way std140 wants.
//!
//! Two things live here. `Tokens` is the theme's vocabulary — the numbers and
//! colours `Theme/greeter.jsonc` turns — read once and then overlayed by `--set`
//! so a candidate value can be previewed without touching a file. `Uniforms` is
//! the packed std140 block; its field offsets are parsed from the rewritten
//! shader at run time (`Block`), so a shader edit that adds or moves a uniform
//! moves this tool's bytes with it instead of silently reading the wrong field.

use anyhow::{anyhow, Context, Result};

/// A colour as the theme stores it: #AARRGGBB, or #RRGGBB with alpha 1.
/// The length and the digits are validated up front: a short token like "#12"
/// is a normal error, not an index panic.
pub fn colour(token: &str) -> Result<[f32; 4]> {
    let hex = token.trim().trim_start_matches('#');
    if (hex.len() != 6 && hex.len() != 8) || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(anyhow!(
            "{token:?} is not a colour: want #rrggbb or #aarrggbb (6 or 8 hex digits)"
        ));
    }
    // every byte was checked above, so the slices below cannot split a character
    let v = |s: &str| u8::from_str_radix(s, 16).unwrap_or(0) as f32 / 255.0;
    Ok(if hex.len() == 8 {
        // the theme writes alpha first, the way Qt does
        [v(&hex[2..4]), v(&hex[4..6]), v(&hex[6..8]), v(&hex[0..2])]
    } else {
        [v(&hex[0..2]), v(&hex[2..4]), v(&hex[4..6]), 1.0]
    })
}

/// The first literal token after `needle`: a `"quoted string"` or a bare word
/// (`1.4`, `true`, `full`). `None` when the key is absent, so a theme that has
/// not grown a new token yet keeps the frozen default. `what` names the file in
/// the error, so a missing key is not blamed on the wrong source.
fn literal_after(src: &str, needle: &str, what: &str) -> Result<Option<String>> {
    let Some(at) = src.find(needle) else {
        return Ok(None);
    };
    let rest = src[at + needle.len()..].trim_start();
    if let Some(s) = rest.strip_prefix('"') {
        let mut out = String::new();
        let mut chars = s.chars();
        while let Some(c) = chars.next() {
            match c {
                '"' => return Ok(Some(out)),
                '\\' => {
                    if let Some(escaped) = chars.next() {
                        out.push(escaped);
                    }
                }
                _ => out.push(c),
            }
        }
        return Err(anyhow!(
            "the {what} has an unterminated string after {needle:?}"
        ));
    }
    let token: String = rest
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '+'))
        .collect();
    if token.is_empty() {
        return Err(anyhow!("the {what} has no value after {needle:?}"));
    }
    Ok(Some(token))
}

/// Every knob in Theme/greeter.jsonc the workbench can honour. The values are
/// read from the theme, never written here twice; a key the theme does not have
/// yet falls back to the default the greeter itself uses, so the workbench can
/// run against an older part.
#[derive(Debug, Clone)]
pub struct Tokens {
    // the row's geometry, in logical pixels before `scale`
    pub digit_size: f32,  // nixieDigitSize
    pub ui_scale: f32,    // uiScale
    pub tube_margin: f32, // nixieTubeMargin
    pub spacing: f32,     // nixieSpacing: multiplier on both row gaps
    // the discharge
    pub glow: f32,       // nixieGlow
    pub wire: f32,       // nixieWire
    pub temp: f32,       // nixieTempK
    pub exposure: f32,   // nixieExposure
    pub flicker_ms: f32, // nixieFlickerMs (timing, reported in JSON)
    pub shimmer: f32,    // nixieShimmer
    pub shimmer_ms: f32, // nixieShimmerMs
    pub jitter: f32,     // nixieJitter
    pub age: f32,        // nixieAge
    pub stack: f32,      // nixieStack
    pub highlight: f32,  // nixieHighlight
    pub warmth: f32,     // nixieWarmth
    // the glass and the camera
    pub tint: [f32; 4],          // nixieTint
    pub tint_wallpaper: f32,     // nixieTintWallpaper
    pub view_angle: f32,         // nixieViewAngle
    pub view_distance: f32,      // nixieViewDistance
    pub view_pitch: f32,         // nixieViewPitch: pView.z from P6 on
    pub glow_color: [f32; 4],    // nixieGlowColor
    pub glass_color: [f32; 4],   // nixieGlassColor
    pub cathode_color: [f32; 4], // nixieCathodeColor
    // settings the uniform block may or may not have a slot for
    pub quality: String,    // nixieQuality: full | balanced | lite
    pub flicker: bool,      // nixieFlicker
    pub h24: bool,          // nixie24h
    pub leading_zero: bool, // nixieLeadingZero
    pub base: bool,         // nixieBase
}

impl Tokens {
    pub fn read(theme: &str) -> Result<Self> {
        let what = "theme";
        let num = |key: &str, default: f32| -> Result<f32> {
            let needle = format!("\"{key}\": ");
            match literal_after(theme, &needle, what)? {
                Some(token) => token
                    .parse::<f32>()
                    .with_context(|| format!("theme: {key} = {token:?} is not a number")),
                None => Ok(default),
            }
        };
        let col = |key: &str, default: [f32; 4]| -> Result<[f32; 4]> {
            let needle = format!("\"{key}\": ");
            match literal_after(theme, &needle, what)? {
                Some(token) => colour(&token).with_context(|| format!("theme: {key}")),
                None => Ok(default),
            }
        };
        let boolean = |key: &str, default: bool| -> Result<bool> {
            let needle = format!("\"{key}\": ");
            match literal_after(theme, &needle, what)? {
                Some(token) => match token.as_str() {
                    "true" => Ok(true),
                    "false" => Ok(false),
                    other => Err(anyhow!("theme: {key} = {other:?} is not a boolean")),
                },
                None => Ok(default),
            }
        };
        let quality = || -> Result<String> {
            let needle = "\"nixieQuality\": ";
            match literal_after(theme, needle, what)? {
                Some(token) => match token.as_str() {
                    "full" | "balanced" | "lite" => Ok(token),
                    other => Err(anyhow!(
                        "theme: nixieQuality = {other:?} is not full, balanced or lite"
                    )),
                },
                None => Ok("full".to_string()),
            }
        };
        Ok(Self {
            digit_size: num("nixieDigitSize", 92.0)?,
            ui_scale: num("uiScale", 1.2)?,
            tube_margin: num("nixieTubeMargin", 16.0)?,
            spacing: num("nixieSpacing", 1.0)?,
            glow: num("nixieGlow", 1.0)?,
            wire: num("nixieWire", 0.044)?,
            temp: num("nixieTempK", 2100.0)?,
            exposure: num("nixieExposure", 2.5)?,
            flicker_ms: num("nixieFlickerMs", 320.0)?,
            shimmer: num("nixieShimmer", 1.0)?,
            shimmer_ms: num("nixieShimmerMs", 66.0)?,
            jitter: num("nixieJitter", 1.0)?,
            age: num("nixieAge", 1.0)?,
            stack: num("nixieStack", 0.5)?,
            highlight: num("nixieHighlight", 0.8)?,
            warmth: num("nixieWarmth", 0.45)?,
            tint: col("nixieTint", [0.0, 0.0, 0.0, 0.0])?,
            tint_wallpaper: num("nixieTintWallpaper", 0.0)?,
            view_angle: num("nixieViewAngle", 16.0)?,
            view_distance: num("nixieViewDistance", 8.0)?,
            view_pitch: num("nixieViewPitch", 0.0)?,
            glow_color: col("nixieGlowColor", colour("#ff5a10")?)?,
            glass_color: col("nixieGlassColor", colour("#4d120b06")?)?,
            cathode_color: col("nixieCathodeColor", colour("#aab6c4")?)?,
            quality: quality()?,
            flicker: boolean("nixieFlicker", true)?,
            h24: boolean("nixie24h", true)?,
            leading_zero: boolean("nixieLeadingZero", false)?,
            base: boolean("nixieBase", false)?,
        })
    }

    /// Apply one `--set nixieToken=value` override. Any token in the frozen
    /// vocabulary is accepted (numbers, colours, booleans and the quality
    /// choice), so a preset sweep can be scripted without editing a file.
    pub fn apply(&mut self, key: &str, value: &str) -> Result<()> {
        let key = key.strip_prefix("greeter.").unwrap_or(key);
        let num = |v: &str| -> Result<f32> {
            v.parse::<f32>()
                .with_context(|| format!("--set {key}={v}: not a number"))
        };
        let boolean = |v: &str| -> Result<bool> {
            match v {
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(anyhow!("--set {key}={v}: not a boolean (true or false)")),
            }
        };
        match key {
            "nixieDigitSize" => self.digit_size = num(value)?,
            "uiScale" => self.ui_scale = num(value)?,
            "nixieTubeMargin" => self.tube_margin = num(value)?,
            "nixieSpacing" => self.spacing = num(value)?,
            "nixieGlow" => self.glow = num(value)?,
            "nixieWire" => self.wire = num(value)?,
            "nixieTempK" => self.temp = num(value)?,
            "nixieExposure" => self.exposure = num(value)?,
            "nixieFlickerMs" => self.flicker_ms = num(value)?,
            "nixieShimmer" => self.shimmer = num(value)?,
            "nixieShimmerMs" => self.shimmer_ms = num(value)?,
            "nixieJitter" => self.jitter = num(value)?,
            "nixieAge" => self.age = num(value)?,
            "nixieStack" => self.stack = num(value)?,
            "nixieHighlight" => self.highlight = num(value)?,
            "nixieWarmth" => self.warmth = num(value)?,
            "nixieTintWallpaper" => self.tint_wallpaper = num(value)?,
            "nixieViewAngle" => self.view_angle = num(value)?,
            "nixieViewDistance" => self.view_distance = num(value)?,
            "nixieViewPitch" => self.view_pitch = num(value)?,
            "nixieTint" => self.tint = colour(value).with_context(|| format!("--set {key}"))?,
            "nixieGlowColor" => {
                self.glow_color = colour(value).with_context(|| format!("--set {key}"))?
            }
            "nixieGlassColor" => {
                self.glass_color = colour(value).with_context(|| format!("--set {key}"))?
            }
            "nixieCathodeColor" => {
                self.cathode_color = colour(value).with_context(|| format!("--set {key}"))?
            }
            "nixieQuality" => match value {
                "full" | "balanced" | "lite" => self.quality = value.to_string(),
                _ => {
                    return Err(anyhow!(
                        "--set {key}={value}: not a quality (full, balanced or lite)"
                    ))
                }
            },
            "nixieFlicker" => self.flicker = boolean(value)?,
            "nixie24h" => self.h24 = boolean(value)?,
            "nixieLeadingZero" => self.leading_zero = boolean(value)?,
            "nixieBase" => self.base = boolean(value)?,
            other => {
                return Err(anyhow!(
                    "--set {other}: unknown theme token; known tokens are nixieDigitSize, \
                     uiScale, nixieTubeMargin, nixieSpacing, nixieGlow, nixieWire, nixieTempK, \
                     nixieExposure, nixieFlickerMs, nixieShimmer, nixieShimmerMs, nixieJitter, \
                     nixieAge, nixieStack, nixieHighlight, nixieWarmth, nixieTint, \
                     nixieGlowColor, nixieGlassColor, nixieCathodeColor, nixieTintWallpaper, \
                     nixieViewAngle, nixieViewDistance, nixieViewPitch, nixieQuality, \
                     nixieFlicker, nixie24h, nixieLeadingZero, nixieBase"
                ))
            }
        }
        Ok(())
    }
}

/// The std140 block declared in nixie.frag, parsed: a name is resolved to its
/// byte offset and its width in floats, so the workbench writes each uniform
/// where the shader actually declared it.
#[derive(Debug, Clone)]
pub struct Block {
    size: usize,
    fields: Vec<(String, usize, usize)>,
}

impl Block {
    /// `src` is the compute shader produced by `shader::to_compute`, i.e. with
    /// Qt's `mat4 qt_Matrix` and `float qt_Opacity` already removed.
    pub fn parse(src: &str) -> Result<Self> {
        let at = src
            .find("uniform buf")
            .ok_or_else(|| anyhow!("the shader has no `uniform buf` block"))?;
        let open = src[at..]
            .find('{')
            .map(|i| i + at)
            .ok_or_else(|| anyhow!("the shader's `uniform buf` block is not opened"))?;
        let close = src[open..]
            .find('}')
            .map(|i| i + open)
            .ok_or_else(|| anyhow!("the shader's `uniform buf` block is not closed"))?;
        let mut offset = 0usize;
        let mut fields: Vec<(String, usize, usize)> = Vec::new();
        for raw in src[open + 1..close].lines() {
            let line = raw.split("//").next().unwrap_or("").trim();
            if line.is_empty() {
                continue;
            }
            let mut words = line.split_whitespace();
            let ty = words.next().unwrap_or("");
            let name = words.next().unwrap_or("").trim_end_matches(';').trim();
            if name.contains('[') {
                return Err(anyhow!(
                    "the uniform block has an array this workbench does not pack: {line:?}"
                ));
            }
            let (size, align) = match ty {
                "float" => (4, 4),
                "vec2" => (8, 8),
                "vec4" => (16, 16),
                "mat4" => (64, 16),
                other => {
                    return Err(anyhow!(
                        "unknown uniform type {other:?} in the block: {line:?}"
                    ))
                }
            };
            offset = offset.div_ceil(align) * align;
            fields.push((name.to_string(), offset, size / 4));
            offset += size;
        }
        if fields.is_empty() {
            return Err(anyhow!("the shader's `uniform buf` block is empty"));
        }
        Ok(Self {
            size: offset.div_ceil(16) * 16,
            fields,
        })
    }

    pub fn has(&self, name: &str) -> bool {
        self.fields.iter().any(|(n, _, _)| n == name)
    }

    /// The byte offset the shader declared for `name` (asserted by the tests;
    /// also how a future field finder asks the block where it lives).
    #[allow(dead_code)]
    pub fn offset(&self, name: &str) -> Option<usize> {
        self.fields
            .iter()
            .find(|(n, _, _)| n == name)
            .map(|(_, off, _)| *off)
    }
    /// Write `values` into `buf` at the named member's declared offset.
    pub fn set(&self, buf: &mut [u8], name: &str, values: &[f32]) -> Result<()> {
        let (off, width) = self
            .fields
            .iter()
            .find(|(n, _, _)| n == name)
            .map(|(_, off, width)| (*off, *width))
            .ok_or_else(|| anyhow!("the shader's uniform block has no {name}; cannot pack it"))?;
        if values.len() != width {
            return Err(anyhow!(
                "{name} is {width} floats in the shader, but {} were given",
                values.len()
            ));
        }
        for (i, value) in values.iter().enumerate() {
            let at = off + i * 4;
            buf[at..at + 4].copy_from_slice(&value.to_ne_bytes());
        }
        Ok(())
    }
}

/// The block's values, typed for the rest of the tool. `pack` resolves them to
/// the offsets `Block` parsed from the shader.
#[derive(Debug, Clone, Copy)]
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
    pub temp: f32,
    pub exposure: f32,
    pub halo: [f32; 4],
    pub glass: [f32; 4],
    pub cathode: [f32; 4],
    pub thick: f32,
    pub mm: f32,
    pub refract: f32,
    pub time: f32,
    pub row_x: [f32; 4],
    pub row_digit: [f32; 4],
    pub row_flicker: [f32; 4],
    pub tile: [f32; 4],      // width, height, the tube's margin, 1 = the row pass
    pub tint: [f32; 4],      // coloured glass: the hue, and how much of it
    pub wallpaper: [f32; 4], // x: tint with the wallpaper's accent instead
    pub view: [f32; 4],      // x: yaw, degrees; y: distance, tube widths; z: pitch, degrees
    pub quality: f32,        // 0 full, 1 balanced, 2 lite (pQuality, if the shader has it)
    pub shimmer: f32,        // nixieShimmer (pShimmer, if the shader has it)
    pub age: f32,            // nixieAge (pAge, if the shader has it)
    pub base_on: f32,        // nixieBase (pBaseOn, if the shader has it)
}

impl Uniforms {
    /// The values the login screen's theme hands the tube. Geometry comes from
    /// the caller in shader-space device pixels; `size` is the item (the tube or
    /// the whole row), and `backdrop` is the wallpaper patch behind it, one
    /// `inset` wider on every side, exactly as NixieTube/NixieClock set it.
    #[allow(clippy::too_many_arguments)]
    pub fn from_drawing(
        t: &Tokens,
        mm: f32,
        inset: f32,
        tile: [f32; 2],
        thick: f32,
        size: [f32; 2],
        digit: i32,
    ) -> Self {
        Self {
            size,
            backdrop: [size[0] + 2.0 * inset, size[1] + 2.0 * inset],
            inset,
            radius: 9.5 * mm,
            base: 0.0,
            glow: t.glow,
            digit: digit as f32,
            bulb: 0.0,
            wire: t.wire,
            stack: t.stack,
            highlight: t.highlight,
            warmth: t.warmth,
            flicker: 1.0,
            temp: t.temp,
            exposure: t.exposure,
            halo: t.glow_color,
            glass: t.glass_color,
            cathode: t.cathode_color,
            thick,
            mm,
            refract: 1.0,
            time: 0.0,
            row_x: [0.0; 4],
            row_digit: [-1.0; 4],
            row_flicker: [1.0; 4],
            tile: [tile[0], tile[1], inset, 0.0],
            tint: t.tint,
            wallpaper: [t.tint_wallpaper, 0.0, 0.0, 0.0],
            view: [t.view_angle, t.view_distance, t.view_pitch, 0.0],
            quality: match t.quality.as_str() {
                "balanced" => 1.0,
                "lite" => 2.0,
                _ => 0.0,
            },
            shimmer: t.shimmer,
            age: t.age,
            base_on: if t.base { 1.0 } else { 0.0 },
        }
    }

    /// The std140 bytes for this block. The fields the workbench understands are
    /// mandatory; the newer ones are set when the shader declares them, so the
    /// tool runs against a shader that has not grown them yet.
    pub fn pack(&self, block: &Block) -> Result<Vec<u8>> {
        let mut buf = vec![0u8; block.size];
        block.set(&mut buf, "pSize", &self.size)?;
        block.set(&mut buf, "pBackdrop", &self.backdrop)?;
        block.set(&mut buf, "pInset", &[self.inset])?;
        block.set(&mut buf, "pRadius", &[self.radius])?;
        block.set(&mut buf, "pBase", &[self.base])?;
        block.set(&mut buf, "pGlow", &[self.glow])?;
        block.set(&mut buf, "pDigit", &[self.digit])?;
        block.set(&mut buf, "pBulb", &[self.bulb])?;
        block.set(&mut buf, "pWire", &[self.wire])?;
        block.set(&mut buf, "pStack", &[self.stack])?;
        block.set(&mut buf, "pHighlight", &[self.highlight])?;
        block.set(&mut buf, "pWarmth", &[self.warmth])?;
        block.set(&mut buf, "pFlicker", &[self.flicker])?;
        block.set(&mut buf, "pTempK", &[self.temp])?;
        block.set(&mut buf, "pExposure", &[self.exposure])?;
        block.set(&mut buf, "pHalo", &self.halo)?;
        block.set(&mut buf, "pGlass", &self.glass)?;
        block.set(&mut buf, "pCathode", &self.cathode)?;
        block.set(&mut buf, "pThick", &[self.thick])?;
        block.set(&mut buf, "pMm", &[self.mm])?;
        block.set(&mut buf, "pRefract", &[self.refract])?;
        block.set(&mut buf, "pTime", &[self.time])?;
        block.set(&mut buf, "pRowX", &self.row_x)?;
        block.set(&mut buf, "pRowDigit", &self.row_digit)?;
        block.set(&mut buf, "pRowFlicker", &self.row_flicker)?;
        block.set(&mut buf, "pTile", &self.tile)?;
        block.set(&mut buf, "pTint", &self.tint)?;
        block.set(&mut buf, "pWallpaper", &self.wallpaper)?;
        block.set(&mut buf, "pView", &self.view)?;
        // the token vocabulary the shader may have grown
        for (name, value) in [
            ("pQuality", self.quality),
            ("pShimmer", self.shimmer),
            ("pAge", self.age),
            ("pBaseOn", self.base_on),
        ] {
            if block.has(name) {
                block.set(&mut buf, name, &[value])?;
            }
        }
        Ok(buf)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The block as `shader::to_compute` leaves it: Qt's two members removed.
    const BLOCK: &str = "\
layout(binding = 0, std140) uniform buf {
vec2 pSize;
vec2 pBackdrop;
float pInset;
float pRadius;
float pBase;
float pGlow;
float pDigit;
float pBulb;
float pWire;
float pStack;
float pHighlight;
float pWarmth;
float pFlicker;
float padCore0;
float pTempK;
float pExposure;
float padCore3;
vec4 pHalo;
vec4 pGlass;
vec4 pCathode;
float pThick;
float pMm;
float pRefract;
float pTime;
vec4 pRowX;
vec4 pRowDigit;
vec4 pRowFlicker;
vec4 pTile;
vec4 pTint;
vec4 pWallpaper;
vec4 pView;
};";

    fn base() -> Uniforms {
        Uniforms {
            size: [2.0, 3.0],
            backdrop: [4.0, 5.0],
            inset: 6.0,
            radius: 7.0,
            base: 8.0,
            glow: 9.0,
            digit: 10.0,
            bulb: 11.0,
            wire: 12.0,
            stack: 13.0,
            highlight: 14.0,
            warmth: 15.0,
            flicker: 16.0,
            temp: 17.0,
            exposure: 18.0,
            halo: [19.0; 4],
            glass: [20.0; 4],
            cathode: [21.0; 4],
            thick: 22.0,
            mm: 23.0,
            refract: 24.0,
            time: 25.0,
            row_x: [26.0; 4],
            row_digit: [27.0; 4],
            row_flicker: [28.0; 4],
            tile: [29.0; 4],
            tint: [30.0; 4],
            wallpaper: [31.0; 4],
            view: [32.0; 4],
            quality: 1.0,
            shimmer: 0.0,
            age: 2.0,
            base_on: 1.0,
        }
    }

    fn f32_at(buf: &[u8], off: usize) -> f32 {
        let mut b = [0u8; 4];
        b.copy_from_slice(&buf[off..off + 4]);
        f32::from_ne_bytes(b)
    }

    /// std140 offsets the shader declares, hand-checked once: each vec4 rounds
    /// up to a 16-byte boundary and the block is a multiple of 16.
    #[test]
    fn the_block_is_std140() {
        let block = Block::parse(BLOCK).unwrap();
        assert_eq!(block.offset("pSize"), Some(0));
        assert_eq!(block.offset("pBackdrop"), Some(8));
        assert_eq!(block.offset("pTempK"), Some(64));
        assert_eq!(block.offset("pHalo"), Some(80));
        assert_eq!(block.offset("pIdle"), None);
        assert_eq!(block.offset("pView"), Some(240));
        let buf = base().pack(&block).unwrap();
        assert_eq!(buf.len(), 256);
        assert_eq!(f32_at(&buf, 0), 2.0);
        assert_eq!(f32_at(&buf, 64), 17.0);
        assert_eq!(f32_at(&buf, 80), 19.0);
        assert_eq!(f32_at(&buf, 240), 32.0);
    }

    #[test]
    fn optional_uniforms_are_written_when_present() {
        let with = BLOCK.replace("vec4 pView;", "vec4 pView;\nfloat pQuality;");
        let block = Block::parse(&with).unwrap();
        assert_eq!(block.offset("pQuality"), Some(256));
        assert_eq!(block.size, 272);
        let buf = base().pack(&block).unwrap();
        assert_eq!(f32_at(&buf, 256), 1.0);
    }

    #[test]
    fn colours_are_validated_not_guessed() {
        assert!(colour("#12").is_err());
        assert!(colour("#").is_err());
        assert!(colour("").is_err());
        assert!(colour("#gggggg").is_err());
        assert_eq!(colour("#ff0000").unwrap(), [1.0, 0.0, 0.0, 1.0]);
        let half = colour("#80ff0000").unwrap();
        assert_eq!(half[0], 1.0);
        assert!((half[3] - 128.0 / 255.0).abs() < 1e-6);
    }

    #[test]
    fn overrides_reach_the_vocabulary() {
        let mut t = Tokens::read("{}").unwrap();
        t.apply("nixieGlow", "1.4").unwrap();
        t.apply("greeter.nixieTempK", "2400").unwrap();
        t.apply("nixieTint", "#cc66e0ff").unwrap();
        assert_eq!(t.glow, 1.4);
        assert_eq!(t.temp, 2400.0);
        assert!(t.apply("nixieTintWallpaper", "#12").is_err());
        assert!(t.apply("nixieNope", "1").is_err());
    }
}
