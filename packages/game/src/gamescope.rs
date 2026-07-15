//! Gamescope flag assembly and preset system.
//!
//! Builds gamescope command-line flags from named presets,
//! environment variables, and per-game overrides.

use crate::display::DisplayInfo;

/// Available gamescope presets.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Preset {
    /// Native resolution, adaptive sync, no upscaling.
    Quality,
    /// FSR downscale (2/3 render resolution), adaptive sync.
    Perf,
    /// Native resolution, HDR, adaptive sync.
    Hdr,
    /// Dynamic resolution scaling based on target FPS heuristic.
    TargetFps,
    /// Minimal: only env-overridable flags.
    Pinned,
    /// Unity/nested mode: expose Wayland, force grab cursor.
    Unity,
    /// Skip gamescope entirely (run directly).
    Skip,
}

impl Preset {
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "quality" => Some(Self::Quality),
            "perf" => Some(Self::Perf),
            "hdr" => Some(Self::Hdr),
            "targetfps" => Some(Self::TargetFps),
            "pinned" => Some(Self::Pinned),
            "unity" => Some(Self::Unity),
            "skip" => Some(Self::Skip),
            _ => None,
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Quality => "quality",
            Self::Perf => "perf",
            Self::Hdr => "hdr",
            Self::TargetFps => "targetfps",
            Self::Pinned => "pinned",
            Self::Unity => "unity",
            Self::Skip => "skip",
        }
    }

    pub fn description(&self) -> &'static str {
        match self {
            Self::Quality => "Native resolution, adaptive sync, no upscaling",
            Self::Perf => "FSR downscale (66% render), adaptive sync",
            Self::Hdr => "Native resolution, HDR, adaptive sync",
            Self::TargetFps => "Dynamic resolution based on target FPS",
            Self::Pinned => "Minimal flags (env-overridable)",
            Self::Unity => "Nested mode for Unity/Wayland games",
            Self::Skip => "Run directly without gamescope",
        }
    }
}

/// Assembled gamescope command.
pub struct GamescopeCmd {
    pub preset: Preset,
    pub gamescope_flags: Vec<String>,
    pub command: Vec<String>,
    pub env_vars: Vec<(String, String)>,
    pub use_game_run: bool,
}

/// Build gamescope flags from a preset and display info.
pub fn build_flags(
    preset: Preset,
    display: &DisplayInfo,
    scale_override: Option<f64>,
    fsr_sharpness: Option<i32>,
) -> Vec<String> {
    let mut flags = Vec::new();

    match preset {
        Preset::Quality => {
            flags.extend_from_slice(&["-f".into(), "--adaptive-sync".into()]);
            flags.extend_from_slice(&["-W".into(), display.width.to_string()]);
            flags.extend_from_slice(&["-H".into(), display.height.to_string()]);
        }
        Preset::Perf => {
            flags.extend_from_slice(&["-f".into(), "--adaptive-sync".into()]);
            let scale = scale_override.unwrap_or(2.0 / 3.0);
            let game_w = (display.width as f64 * scale) as i32;
            let game_h = (display.height as f64 * scale) as i32;
            flags.extend_from_slice(&["-w".into(), game_w.to_string()]);
            flags.extend_from_slice(&["-h".into(), game_h.to_string()]);
            flags.extend_from_slice(&["-W".into(), display.width.to_string()]);
            flags.extend_from_slice(&["-H".into(), display.height.to_string()]);
            let sharpness = fsr_sharpness.unwrap_or(3).to_string();
            flags.extend_from_slice(&["--fsr-sharpness".into(), sharpness]);
        }
        Preset::Hdr => {
            flags.extend_from_slice(&["-f".into(), "--adaptive-sync".into(), "--hdr-enabled".into()]);
            flags.extend_from_slice(&["-W".into(), display.width.to_string()]);
            flags.extend_from_slice(&["-H".into(), display.height.to_string()]);
        }
        Preset::TargetFps => {
            flags.extend_from_slice(&["-f".into(), "--adaptive-sync".into()]);

            // Dynamic scale heuristic
            let target_fps = std::env::var("TARGET_FPS")
                .ok()
                .and_then(|v| v.parse::<f64>().ok())
                .or(Some(120.0))
                .unwrap();
            let base_fps = std::env::var("NATIVE_BASE_FPS")
                .ok()
                .and_then(|v| v.parse::<f64>().ok())
                .unwrap_or(60.0);

            let scale = if base_fps > 0.0 && target_fps > 0.0 {
                (base_fps / target_fps).sqrt().clamp(0.5, 1.0)
            } else {
                1.0
            };

            if scale < 1.0 {
                let game_w = (display.width as f64 * scale) as i32;
                let game_h = (display.height as f64 * scale) as i32;
                flags.extend_from_slice(&["-w".into(), game_w.to_string()]);
                flags.extend_from_slice(&["-h".into(), game_h.to_string()]);
            }

            flags.extend_from_slice(&["-W".into(), display.width.to_string()]);
            flags.extend_from_slice(&["-H".into(), display.height.to_string()]);

            let sharpness = fsr_sharpness.unwrap_or(3).to_string();
            flags.extend_from_slice(&["--fsr-sharpness".into(), sharpness]);
        }
        Preset::Pinned => {
            // Read from GAMESCOPE_FLAGS env, default to "-f --adaptive-sync"
            let env_flags = std::env::var("GAMESCOPE_FLAGS")
                .unwrap_or_else(|_| "-f --adaptive-sync".to_string());
            for flag in env_flags.split_whitespace() {
                flags.push(flag.to_string());
            }
        }
        Preset::Unity => {
            flags.extend_from_slice(&["--expose-wayland".into(), "--force-grab-cursor".into()]);
            // Nested mode: use logical resolution
            let logical_w = (display.width as f64 / display.scale) as i32;
            let logical_h = (display.height as f64 / display.scale) as i32;
            flags.extend_from_slice(&["-w".into(), display.width.to_string()]);
            flags.extend_from_slice(&["-h".into(), display.height.to_string()]);
            flags.extend_from_slice(&["-W".into(), logical_w.to_string()]);
            flags.extend_from_slice(&["-H".into(), logical_h.to_string()]);
        }
        Preset::Skip => {}
    }

    // Refresh rate for all non-skip presets
    if preset != Preset::Skip {
        flags.extend_from_slice(&["-r".into(), display.refresh_rate.to_string()]);
        // Apply any GAMESCOPE_EXTRA_FLAGS from env
        if let Ok(extra) = std::env::var("GAMESCOPE_EXTRA_FLAGS") {
            for flag in extra.split_whitespace() {
                flags.push(flag.to_string());
            }
        }
    }

    flags
}

/// Build the full gamescope command.
pub fn build_command(
    preset: Preset,
    display: &DisplayInfo,
    command: Vec<String>,
    scale_override: Option<f64>,
    fsr_sharpness: Option<i32>,
    no_pin: bool,
) -> GamescopeCmd {
    let flags = build_flags(preset, display, scale_override, fsr_sharpness);

    let env_vars = match preset {
        Preset::Unity => vec![("DISABLE_GAMESCOPE_WSI".into(), "1".into())],
        _ => Vec::new(),
    };

    GamescopeCmd {
        preset,
        gamescope_flags: flags,
        command,
        env_vars,
        use_game_run: !no_pin,
    }
}

/// Check if a game should skip gamescope (e.g., Soulstone Survivors workaround).
pub fn should_skip_gamescope(args: &[String]) -> bool {
    let cmd_str = args.join(" ");
    cmd_str.contains("Soulstone") || cmd_str.contains("2066020")
}

/// List available presets as a string.
pub fn list_presets() -> String {
    let mut out = String::from("Available presets:\n");
    for p in &[
        Preset::Quality,
        Preset::Perf,
        Preset::Hdr,
        Preset::TargetFps,
        Preset::Pinned,
        Preset::Unity,
        Preset::Skip,
    ] {
        out.push_str(&format!("  {:<12} {}\n", p.name(), p.description()));
    }
    out
}
