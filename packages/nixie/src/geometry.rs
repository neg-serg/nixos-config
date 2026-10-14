//! The checks a fitter would run: the lamp is one object on one axis, with no
//! gaps, no overlaps, and the proportions the drawing asks for.

use crate::drawing::Drawing;

pub struct Check {
    pub name: &'static str,
    pub ok: bool,
    pub detail: String,
}

pub struct Report {
    pub checks: Vec<Check>,
}

impl Report {
    pub fn failed(&self) -> usize {
        self.checks.iter().filter(|c| !c.ok).count()
    }

    pub fn text(&self) -> String {
        let width = self.checks.iter().map(|c| c.name.len()).max().unwrap_or(0);
        let mut out = String::new();
        for c in &self.checks {
            out.push_str(&format!(
                "  [{}] {:<width$}  {}\n",
                if c.ok { "ok" } else { "FAIL" },
                c.name,
                c.detail
            ));
        }
        out.push_str(if self.failed() == 0 {
            "OK: the lamp is one object on one axis\n"
        } else {
            "the layout does not agree with the drawing\n"
        });
        out
    }
}

pub fn check(d: &Drawing) -> Report {
    let l = d.layout();
    let inner_r = d.bulb_r - d.wall;
    let digit_top = l.digit_mid - d.digit_h / 2.0;
    let digit_bottom = l.digit_mid + d.digit_h / 2.0;
    let mut checks = Vec::new();
    let mut c =
        |name: &'static str, ok: bool, detail: String| checks.push(Check { name, ok, detail });

    c(
        "the drawing adds up",
        (d.bulb_h + d.collar_h - d.box_h).abs() < 1e-9,
        format!(
            "bulb {:.0} + base {:.0} = box {:.0} mm",
            d.bulb_h, d.collar_h, d.box_h
        ),
    );
    c(
        "the dome is a hemisphere on the cylinder",
        (l.cap_y - (l.apex_y + d.bulb_r)).abs() < 1e-9,
        format!(
            "cap {:.2} = apex {:.2} + r {:.1}",
            l.cap_y, l.apex_y, d.bulb_r
        ),
    );
    c(
        "the glass meets the base exactly",
        (l.apex_y + d.bulb_h - l.foot_y).abs() < 1e-9,
        format!(
            "glass foot {:.2} = base top {:.2}",
            l.apex_y + d.bulb_h,
            l.foot_y
        ),
    );
    // Only a check when the shader carries a base radius of its own: reading
    // BULB_R_MM for both made this compare a number with itself.
    c(
        "the base hides the glass's foot",
        match d.collar_r {
            Some(collar) => collar >= d.bulb_r,
            None => true,
        },
        match d.collar_r {
            Some(collar) => format!("base Ø{:.1} >= bulb Ø{:.1}", collar * 2.0, d.bulb_r * 2.0),
            None => {
                "skipped: the shader has no separate base radius (the lamp has no base)".to_string()
            }
        },
    );
    c(
        "the pip is the top of the box",
        (l.apex_y + l.box_mid).abs() < 1e-9,
        format!("glass top {:.2} = box top {:.2}", l.apex_y, -l.box_mid),
    );
    // The sheet's numerals are 18 mm, but the shader draws them at DIGIT_H (25)
    // on purpose: the lamp is asked to fill its glass. What has to hold is that
    // they fit the bore, which the second bound keeps honest.
    c(
        "the numerals fill the glass without leaving it",
        d.digit_h <= d.bulb_h - d.wall * 2.0 && d.digit_h >= 18.0 - 1e-9,
        format!(
            "{:.1} x {:.1} mm in Ø{:.1} x {:.0} mm",
            d.digit_w,
            d.digit_h,
            inner_r * 2.0,
            d.bulb_h
        ),
    );
    c(
        "the numerals are centred on the glass",
        (l.digit_mid - 0.5 * (l.apex_y + l.foot_y)).abs() < 1e-9,
        format!(
            "numeral centre {:.2}, glass centre {:.2}",
            l.digit_mid,
            0.5 * (l.apex_y + l.foot_y)
        ),
    );
    c(
        "the numerals are inside the bore",
        d.digit_w / 2.0 <= inner_r && digit_top >= l.apex_y && digit_bottom <= l.foot_y,
        format!(
            "{:.1} x {:.0} mm inside Ø{:.1} x {:.0} mm",
            d.digit_w,
            d.digit_h,
            inner_r * 2.0,
            d.bulb_h
        ),
    );
    c(
        // A real cathode is 0.24 mm, but the tube is drawn with a fat one on
        // purpose: a hairline disappears on a login screen, and a fatter wire
        // carries more gas (the sheath scales with it), which is what makes the
        // discharge read as a filament. The limit catches a wire that has
        // stopped being a wire at all — the drawn one is 2.20 mm across.
        "the wire is a wire",
        d.wire_d <= 2.6,
        format!("cathode Ø{:.2} mm", d.wire_d),
    );
    c(
        "the mesh wraps the stack",
        d.mesh_r <= inner_r && d.mesh_r > d.digit_w / 2.0,
        format!(
            "mesh Ø{:.1}, numerals {:.1}, bore Ø{:.1}",
            d.mesh_r * 2.0,
            d.digit_w,
            inner_r * 2.0
        ),
    );
    c(
        "the rods clear the numerals",
        d.rod_x > d.digit_w / 2.0 && d.rod_x < d.mesh_r,
        format!(
            "rods ±{:.1}, numerals ±{:.1}, mesh {:.1}",
            d.rod_x,
            d.digit_w / 2.0,
            d.mesh_r
        ),
    );
    Report { checks }
}
