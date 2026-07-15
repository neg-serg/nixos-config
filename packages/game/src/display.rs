//! Monitor detection via Hyprland IPC.
//!
//! Queries `hyprctl monitors -j` to get the focused monitor's
//! resolution, refresh rate, and scale.

use serde::Deserialize;
use std::process::Command;

/// Monitor information from Hyprland.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Monitor {
    pub name: Option<String>,
    pub width: i32,
    pub height: i32,
    pub refresh_rate: f64,
    pub scale: Option<f64>,
    pub focused: Option<bool>,
}

/// Detected display parameters.
#[derive(Debug, Clone)]
pub struct DisplayInfo {
    pub width: i32,
    pub height: i32,
    pub refresh_rate: i32,
    pub scale: f64,
    pub monitor_name: Option<String>,
}

/// Query all monitors from Hyprland.
pub fn get_monitors() -> Vec<Monitor> {
    let output = match Command::new("hyprctl")
        .args(["monitors", "-j"])
        .output()
    {
        Ok(o) if o.status.success() => o,
        _ => return Vec::new(),
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout).unwrap_or_default()
}

/// Pick the best monitor: env var `GAMESCOPE_MON` → focused → best by refresh×resolution.
pub fn pick_monitor(monitors: &[Monitor], target: Option<&str>) -> Option<Monitor> {
    if monitors.is_empty() {
        return None;
    }

    // By name
    if let Some(name) = target {
        if let Some(m) = monitors.iter().find(|m| m.name.as_deref() == Some(name)) {
            return Some(m.clone());
        }
    }

    // Focused
    if let Some(m) = monitors.iter().find(|m| m.focused.unwrap_or(false)) {
        return Some(m.clone());
    }

    // Best by refresh rate then resolution
    monitors
        .iter()
        .max_by(|a, b| {
            a.refresh_rate
                .partial_cmp(&b.refresh_rate)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| (a.width * a.height).cmp(&(b.width * b.height)))
        })
        .cloned()
}

/// Resolve display info: env overrides → auto-detect.
pub fn resolve_display() -> DisplayInfo {
    // Env var overrides
    let env_w = std::env::var("GAMESCOPE_OUT_W").ok();
    let env_h = std::env::var("GAMESCOPE_OUT_H").ok();
    let env_rate = std::env::var("GAMESCOPE_RATE").ok();
    let env_mon = std::env::var("GAMESCOPE_MON").ok();

    let monitors = get_monitors();
    let mon = pick_monitor(&monitors, env_mon.as_deref());

    let width = env_w
        .and_then(|v| v.parse().ok())
        .or_else(|| mon.as_ref().map(|m| m.width))
        .unwrap_or(3840);

    let height = env_h
        .and_then(|v| v.parse().ok())
        .or_else(|| mon.as_ref().map(|m| m.height))
        .unwrap_or(2160);

    let refresh_rate = env_rate
        .and_then(|v| v.parse().ok())
        .or_else(|| mon.as_ref().map(|m| m.refresh_rate.round() as i32))
        .unwrap_or(240);

    let scale = mon.as_ref().and_then(|m| m.scale).unwrap_or(2.0);

    DisplayInfo {
        width,
        height,
        refresh_rate,
        scale,
        monitor_name: mon.as_ref().and_then(|m| m.name.clone()),
    }
}

/// Describe the current display setup.
pub fn describe_display() -> String {
    let info = resolve_display();
    let mon_name = info
        .monitor_name
        .as_deref()
        .unwrap_or("unknown");
    format!(
        "Monitor: {mon_name}  {w}x{h}@{rate}Hz  scale={scale}",
        w = info.width,
        h = info.height,
        rate = info.refresh_rate,
        scale = info.scale
    )
}
