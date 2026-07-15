//! Desktop app mode — runs a desktop application inside gamescope
//! with pixel-perfect integer scaling or FSR upscaling.
//!
//! Replaces `gamescope-app` (zsh script).

use crate::display::DisplayInfo;

/// Resolution preset or custom WxH.
pub enum Resolution {
    P1080,
    P1440,
    P720,
    Custom(i32, i32),
}

impl Resolution {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "1080" => Some(Self::P1080),
            "1440" => Some(Self::P1440),
            "720" => Some(Self::P720),
            _ => {
                // Try parsing "WxH"
                if let Some((w, h)) = name.split_once('x') {
                    let w = w.parse().ok()?;
                    let h = h.parse().ok()?;
                    Some(Self::Custom(w, h))
                } else {
                    None
                }
            }
        }
    }

    pub fn dimensions(&self, _display: &DisplayInfo) -> (i32, i32) {
        match self {
            Self::P1080 => (1920, 1080),
            Self::P1440 => (2560, 1440),
            Self::P720 => (1280, 720),
            Self::Custom(w, h) => (*w, *h),
        }
    }
}

/// Upscale filter.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Filter {
    Nearest,
    Fsr,
    Nis,
    Linear,
    Pixel,
}

impl Filter {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "nearest" => Some(Self::Nearest),
            "fsr" => Some(Self::Fsr),
            "nis" => Some(Self::Nis),
            "linear" => Some(Self::Linear),
            "pixel" => Some(Self::Pixel),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Nearest => "nearest",
            Self::Fsr => "fsr",
            Self::Nis => "nis",
            Self::Linear => "linear",
            Self::Pixel => "pixel",
        }
    }
}

/// Scaler mode.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Scaler {
    Integer,
    Fit,
    Fill,
    Stretch,
}

impl Scaler {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Integer => "integer",
            Self::Fit => "fit",
            Self::Fill => "fill",
            Self::Stretch => "stretch",
        }
    }
}

/// Build gamescope command flags for desktop app mode.
pub fn build_app_flags(
    display: &DisplayInfo,
    resolution: &Resolution,
    filter: Filter,
    scaler: Scaler,
    fullscreen: bool,
    expose_wayland: bool,
    fsr_sharpness: i32,
) -> Vec<String> {
    let (inner_w, inner_h) = resolution.dimensions(display);
    let (outer_w, outer_h) = (display.width, display.height);

    let mut flags = Vec::new();

    flags.extend_from_slice(&["-w".into(), inner_w.to_string()]);
    flags.extend_from_slice(&["-h".into(), inner_h.to_string()]);
    flags.extend_from_slice(&["-W".into(), outer_w.to_string()]);
    flags.extend_from_slice(&["-H".into(), outer_h.to_string()]);
    flags.extend_from_slice(&["-r".into(), display.refresh_rate.to_string()]);
    flags.extend_from_slice(&["-S".into(), scaler.as_str().into()]);
    flags.extend_from_slice(&["-F".into(), filter.as_str().into()]);

    if filter == Filter::Fsr || filter == Filter::Nis {
        flags.extend_from_slice(&["--fsr-sharpness".into(), fsr_sharpness.to_string()]);
    }

    if fullscreen {
        flags.push("-f".into());
    }

    if expose_wayland {
        flags.push("--expose-wayland".into());
    }

    flags
}
