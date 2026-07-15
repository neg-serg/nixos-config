//! Per-game and global configuration (TOML).
//!
//! Config locations:
//!   - `~/.config/game/config.toml`   — global defaults
//!   - `~/.config/game/games.toml`     — per-game preset overrides

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Global configuration.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[derive(Default)]
pub struct GameConfig {
    #[serde(default)]
    pub cpu: CpuConfig,
    #[serde(default)]
    pub defaults: DefaultsConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CpuConfig {
    /// CPU set for pinning, or "auto" for V-Cache auto-detection.
    #[serde(default = "default_cpu_pin")]
    pub pin_set: String,
    /// Max CPUs to use when auto-detecting (0 = unlimited).
    #[serde(default = "default_auto_limit")]
    pub auto_limit: usize,
}

impl Default for CpuConfig {
    fn default() -> Self {
        Self {
            pin_set: default_cpu_pin(),
            auto_limit: default_auto_limit(),
        }
    }
}

fn default_cpu_pin() -> String {
    "auto".to_string()
}

fn default_auto_limit() -> usize {
    8
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DefaultsConfig {
    /// Default gamescope preset: "quality", "perf", "hdr", "targetfps", "pinned", "skip".
    #[serde(default = "default_preset")]
    pub preset: String,
    /// Target FPS for targetfps preset.
    #[serde(default = "default_target_fps")]
    pub target_fps: i32,
    /// Estimated native FPS baseline for targetfps heuristic.
    #[serde(default = "default_native_base_fps")]
    pub native_base_fps: i32,
}

impl Default for DefaultsConfig {
    fn default() -> Self {
        Self {
            preset: default_preset(),
            target_fps: default_target_fps(),
            native_base_fps: default_native_base_fps(),
        }
    }
}

fn default_preset() -> String {
    "quality".to_string()
}

fn default_target_fps() -> i32 {
    240
}

fn default_native_base_fps() -> i32 {
    60
}

/// Per-game preset overrides.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GamesConfig {
    /// Default preset for unidentified games.
    #[serde(default = "default_preset")]
    pub default: String,
    /// Per-game config keyed by Steam App ID.
    #[serde(default)]
    pub games: HashMap<String, GameEntry>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GameEntry {
    /// Preset name: "quality", "perf", "hdr", "targetfps", "pinned", "skip".
    pub preset: Option<String>,
    /// Render scale override (0.5-1.0).
    pub scale: Option<f64>,
    /// Extra gamescope flags.
    pub extra_flags: Option<String>,
    /// Disable CPU pinning for this game.
    pub no_pin: Option<bool>,
    /// Disable gamemode for this game.
    pub no_gamemode: Option<bool>,
}

impl Default for GamesConfig {
    fn default() -> Self {
        Self {
            default: default_preset(),
            games: HashMap::new(),
        }
    }
}

/// Load global config from `~/.config/game/config.toml`.
pub fn load_config() -> GameConfig {
    let path = config_path("config.toml");
    match fs::read_to_string(&path) {
        Ok(content) => toml::from_str(&content).unwrap_or_default(),
        Err(_) => GameConfig::default(),
    }
}

/// Load per-game config from `~/.config/game/games.toml`.
pub fn load_games_config() -> GamesConfig {
    let path = config_path("games.toml");
    match fs::read_to_string(&path) {
        Ok(content) => toml::from_str(&content).unwrap_or_default(),
        Err(_) => GamesConfig::default(),
    }
}

/// Resolve the preset and overrides for a given Steam App ID.
pub fn resolve_game_preset(app_id: Option<&str>) -> (String, Option<GameEntry>) {
    let games = load_games_config();
    let app_id = match app_id {
        Some(id) if !id.is_empty() => id,
        _ => return (games.default, None),
    };

    // Try exact match
    if let Some(entry) = games.games.get(app_id) {
        let preset = entry.preset.clone().unwrap_or_else(|| games.default.clone());
        return (preset, Some(entry.clone()));
    }

    (games.default, None)
}

/// Extract Steam App ID from the command line (from compatdata paths).
pub fn extract_app_id(args: &[String]) -> Option<String> {
    for arg in args {
        // Patterns: /steamapps/compatdata/APPID/ or steam_app_APPID
        if let Some(pos) = arg.find("compatdata/") {
            let rest = &arg[pos + 11..];
            if let Some(end) = rest.find('/') {
                let id = &rest[..end];
                if id.chars().all(|c| c.is_ascii_digit()) {
                    return Some(id.to_string());
                }
            }
        }
        if let Some(pos) = arg.find("steam_app_") {
            let rest = &arg[pos + 10..];
            let id: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
            if !id.is_empty() {
                return Some(id);
            }
        }
    }
    None
}

fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("~/.config"))
        .join("game")
}

fn config_path(name: &str) -> PathBuf {
    config_dir().join(name)
}
