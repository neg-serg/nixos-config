//! The drawing the tube is built from, read out of the shader.
//!
//! The numbers are Reflector's IN-12A/B data sheet (1988): bulb Ø19, the base
//! Ø21 x 7 (not drawn by the current envelope: COLLAR_H_MM is 0, so the 35 mm
//! bulb is the whole lamp), the pins Ø1 on an 11.5 mm circle, the pip Ø3.5, the
//! numerals 18 mm. They live in the fragment shader, and this reads them from
//! there — a second copy of them would drift. The one exception is the cathode:
//! its thickness is a theme token the login screen can turn (Theme/greeter.jsonc,
//! nixieWire), so it is handed in from the theme.

use anyhow::{anyhow, Result};

/// The first number after `needle`, e.g. `number_after(src, "float bulbR = ",
/// "shader")`. `what` names the source in the error, so a theme token read
/// through the same helper is not reported as a missing shader line.
pub fn number_after(src: &str, needle: &str, what: &str) -> Result<f64> {
    match number_after_opt(src, needle, what)? {
        Some(value) => Ok(value),
        None => Err(anyhow!("the {what} does not contain {needle:?}")),
    }
}

/// Like `number_after`, but `None` when the marker is absent — a new optional
/// constant in the shader must not break an older drawing.
pub fn number_after_opt(src: &str, needle: &str, what: &str) -> Result<Option<f64>> {
    let Some(at) = src.find(needle) else {
        return Ok(None);
    };
    let token: String = src[at + needle.len()..]
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    token
        .parse::<f64>()
        .map(Some)
        .map_err(|e| anyhow!("the {what}: {needle:?} is followed by {token:?}, not a number ({e})"))
}

/// The parts of the lamp the layout is checked against, all in millimetres.
#[derive(Debug, Clone, Copy)]
pub struct Drawing {
    pub box_w: f64,
    pub box_h: f64,
    pub bulb_r: f64,
    pub bulb_h: f64,
    /// The base's radius from the drawing, when the shader carries a constant of
    /// its own: reading BULB_R_MM twice made the base check tautological.
    pub collar_r: Option<f64>,
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
    /// `src` is the fragment shader; `wire` is the theme's nixieWire, the
    /// cathode's radius as a fraction of the numeral's height.
    pub fn read(src: &str, wire: f64) -> Result<Self> {
        let what = "shader";
        let box_w = number_after(src, "float boxW = ", what)?;
        let box_h = number_after(src, ", boxH = ", what)?;
        let bulb_r = number_after(src, "const float BULB_R_MM = ", what)?;
        let bulb_h = number_after(src, "const float BULB_H_MM = ", what)?;
        let pip_r = number_after(src, "float pipR = ", what)?;
        let collar_r = number_after_opt(src, "const float COLLAR_R_MM = ", what)?;
        let collar_h = number_after(src, "const float COLLAR_H_MM = ", what)?;
        let digit_h = number_after(src, "const float DIGIT_H = ", what)?;
        let digit_w = number_after(src, "const float DIGIT_W = ", what)?;
        let mesh_r = number_after(src, "float cageR = ", what)?;
        let rod_x = number_after(src, "float rods = min(abs(abs(p.x) - ", what)?;
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
            // the wire's radius is the theme's share of the numeral's height
            wire_d: wire * digit_h * 2.0,
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
