//! Styles and their ANSI SGR encoding.
//!
//! A style is a plain value type: colours plus a handful of attributes. The
//! renderer compares the style of consecutive spans and emits an SGR sequence
//! only when it changes, which keeps the byte stream small and the terminal
//! fast even on megabyte-sized outputs.

/// One colour, either a palette index (0-255) or a 24-bit RGB value.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Color {
    /// xterm palette index: 0-15 are the classic ANSI colours, 16-255 the cube.
    Idx(u8),
    /// Direct colour: emitted as-is, the theme decides whether to use it.
    Rgb(u8, u8, u8),
}

/// Text style attached to a span of output.
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Style {
    pub fg: Option<Color>,
    pub bg: Option<Color>,
    pub bold: bool,
    pub dim: bool,
    pub italic: bool,
    pub underline: bool,
}

impl Style {
    pub const NONE: Style = Style {
        fg: None,
        bg: None,
        bold: false,
        dim: false,
        italic: false,
        underline: false,
    };

    /// Palette-indexed foreground.
    pub const fn fg(c: u8) -> Style {
        Style {
            fg: Some(Color::Idx(c)),
            ..Style::NONE
        }
    }

    pub const fn bold(mut self) -> Style {
        self.bold = true;
        self
    }

    pub const fn dim(mut self) -> Style {
        self.dim = true;
        self
    }

    pub const fn underline(mut self) -> Style {
        self.underline = true;
        self
    }

    pub const fn italic(mut self) -> Style {
        self.italic = true;
        self
    }

    /// Append the SGR parameters of this style to `out` (no `ESC [` prefix, no
    /// trailing `m`). A style with nothing set renders as `0` (a reset).
    pub fn push_params(&self, out: &mut Vec<u8>) {
        let mut sep = false;
        let mut code = |out: &mut Vec<u8>, bytes: &[u8]| {
            if sep {
                out.push(b';');
            }
            out.extend_from_slice(bytes);
            sep = true;
        };
        if self.bold {
            code(out, b"1");
        }
        if self.dim {
            code(out, b"2");
        }
        if self.italic {
            code(out, b"3");
        }
        if self.underline {
            code(out, b"4");
        }
        if let Some(c) = self.fg {
            push_color(out, &mut sep, c, false);
        }
        if let Some(c) = self.bg {
            push_color(out, &mut sep, c, true);
        }
        if !sep {
            out.push(b'0');
        }
    }
}

fn push_color(out: &mut Vec<u8>, sep: &mut bool, color: Color, background: bool) {
    if *sep {
        out.push(b';');
    }
    *sep = true;
    match color {
        Color::Idx(c) if c < 8 => push_dec(
            out,
            if background {
                40 + c as u16
            } else {
                30 + c as u16
            },
        ),
        Color::Idx(c) if c < 16 => push_dec(
            out,
            if background {
                100 + (c as u16 - 8)
            } else {
                90 + (c as u16 - 8)
            },
        ),
        Color::Idx(c) => {
            out.extend_from_slice(if background { b"48;5;" } else { b"38;5;" });
            push_dec(out, c as u16);
        }
        Color::Rgb(r, g, b) => {
            out.extend_from_slice(if background { b"48;2;" } else { b"38;2;" });
            push_dec(out, r as u16);
            out.push(b';');
            push_dec(out, g as u16);
            out.push(b';');
            push_dec(out, b as u16);
        }
    }
}

/// Decimal rendering without `format!` machinery (this runs per span).
fn push_dec(out: &mut Vec<u8>, n: u16) {
    let mut buf = [0u8; 5];
    let mut i = buf.len();
    let mut n = n;
    loop {
        i -= 1;
        buf[i] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(&buf[i..]);
}

/// Emits styled spans into a byte buffer, tracking the active style so that a
/// run of identically styled spans costs one SGR sequence for the whole run.
#[derive(Default)]
pub struct SgrWriter {
    active: Option<Style>,
}

impl SgrWriter {
    pub fn new() -> SgrWriter {
        SgrWriter { active: None }
    }

    /// Switch to `style`, writing an escape sequence only when it differs from
    /// the active one.
    pub fn set(&mut self, out: &mut Vec<u8>, style: Style) {
        if self.active == Some(style) {
            return;
        }
        if style == Style::NONE {
            self.reset(out);
        } else {
            out.extend_from_slice(b"\x1b[");
            style.push_params(out);
            out.push(b'm');
            self.active = Some(style);
        }
    }

    /// Return to the terminal default (only writes when a style is active).
    pub fn reset(&mut self, out: &mut Vec<u8>) {
        if self.active.take().is_some() {
            out.extend_from_slice(b"\x1b[0m");
        }
    }
}
