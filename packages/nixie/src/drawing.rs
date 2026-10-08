//! The drawing the tube is built from, read out of the shader.
//!
//! The numbers are Reflector's IN-12A/B data sheet (1988): bulb Ø19 x 28, base
//! Ø21 x 7, the whole lamp 35 without its pins, the pins Ø1 on an 11.5 mm
//! circle, the pip Ø3.5, the numerals 18 mm. They live in the fragment shader,
//! and this reads them from there — a second copy of them would drift. The one
//! exception is the cathode: its thickness is a theme token the login screen can
//! turn (Theme/greeter.jsonc, nixieWire), so it is read from there.

use anyhow::{anyhow, Context, Result};

/// Where the tube's tokens live when nothing else is said.
pub const THEME: &str = "/etc/nixos/files/quickshell/Theme/greeter.jsonc";

/// The first number after `needle`, e.g. `number_after(src, "float bulbR = ")`.
pub fn number_after(src: &str, needle: &str) -> Result<f64> {
    let at = src
        .find(needle)
        .with_context(|| format!("the shader does not contain {needle:?}"))?
        + needle.len();
    let token: String = src[at..]
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    token
        .parse::<f64>()
        .map_err(|e| anyhow!("{needle:?}: {token:?} is not a number ({e})"))
}

/// The parts of the lamp the layout is checked against, all in millimetres.
#[derive(Debug, Clone, Copy)]
pub struct Drawing {
    pub box_w: f64,
    pub box_h: f64,
    pub bulb_r: f64,
    pub bulb_h: f64,
    pub collar_r: f64,
    pub collar_h: f64,
    pub pip_r: f64,
    pub digit_h: f64,
    pub digit_w: f64,
    pub wire_d: f64,
    pub mesh_r: f64,
    pub rod_x: f64,
    pub wall: f64,
}

impl Drawing {
    /// `src` is the fragment shader, `theme` the token file the wire's own
    /// thickness comes from.
    pub fn read(src: &str, theme: &str) -> Result<Self> {
        let box_w = number_after(src, "float boxW = ")?;
        let box_h = number_after(src, ", boxH = ")?;
        let bulb_r = number_after(src, "const float BULB_R_MM = ")?;
        let bulb_h = number_after(src, "const float BULB_H_MM = ")?;
        let pip_r = number_after(src, "float pipR = ")?;
        let collar_r = number_after(src, "const float BULB_R_MM = ")?;
        let collar_h = number_after(src, "const float COLLAR_H_MM = ")?;
        let digit_h = number_after(src, "const float DIGIT_H = ")?;
        let digit_w = number_after(src, "const float DIGIT_W = ")?;
        // the wire's radius is the theme's share of the numeral's height
        let wire_r = number_after(theme, "\"nixieWire\": ")? * digit_h;
        let mesh_r = number_after(src, "float cageR = ")?;
        let rod_x = number_after(src, "float rods = min(abs(abs(p.x) - ")?;
        Ok(Drawing {
            box_w,
            box_h,
            bulb_r,
            bulb_h,
            collar_r,
            collar_h,
            pip_r,
            digit_h,
            digit_w,
            wire_d: wire_r * 2.0,
            mesh_r,
            rod_x,
            wall: 0.9,
        })
    }

    /// Where the parts sit along the tube's axis, in millimetres from the box's
    /// middle: y runs down, so the dome's apex has the smallest y.
    pub fn layout(&self) -> Layout {
        let box_mid = self.box_h / 2.0;
        let foot_y = box_mid - self.collar_h;
        let apex_y = foot_y - self.bulb_h;
        Layout {
            box_mid,
            foot_y,
            apex_y,
            cap_y: apex_y + self.bulb_r,
            digit_mid: 0.5 * (apex_y + foot_y),
        }
    }
}

/// The anchors the shader places its parts on.
#[derive(Debug, Clone, Copy)]
pub struct Layout {
    pub box_mid: f64,
    pub foot_y: f64,
    pub apex_y: f64,
    pub cap_y: f64,
    pub digit_mid: f64,
}
