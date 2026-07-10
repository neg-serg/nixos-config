// Rofi wrapper with auto-computed panel offsets from Quickshell theme
// + Hyprland monitor scale.
//
// Replaces files/rofi/rofi-wrapper.sh — same logic, Rust.

use clap::Parser;
use serde::Deserialize;
use std::os::unix::process::CommandExt;
use std::process::Command;

// ── CLI ──────────────────────────────────────────────────────────────────────

/// Rofi wrapper with auto-computed panel offsets from Quickshell theme
/// + Hyprland monitor scale.
///
/// Environment variables:
///   ROFIW_ROFI     path to rofi binary (default: rofi)
///   ROFIW_HYPRCTL  path to hyprctl binary (default: hyprctl)
#[derive(Parser)]
#[command(name = "rofiw", version, trailing_var_arg = true)]
struct Cli {
    /// Path to rofi binary (env: ROFIW_ROFI)
    #[arg(long, env = "ROFIW_ROFI", default_value = "rofi", hide = true)]
    rofi_bin: String,

    /// Path to hyprctl binary (env: ROFIW_HYPRCTL)
    #[arg(long, env = "ROFIW_HYPRCTL", default_value = "hyprctl", hide = true)]
    hyprctl_bin: String,

    /// Arguments to pass through to rofi
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    rofi_args: Vec<String>,
}

// ── JSON schemas ─────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct ThemeRoot {
    panel: PanelConfig,
}

#[derive(Deserialize)]
struct PanelConfig {
    #[serde(rename = "sideMargin", default = "default_side")]
    side_margin: f64,
    #[serde(rename = "menuYOffset", default = "default_offset")]
    menu_y_offset: f64,
    #[serde(rename = "menuYOffsetAdjust")]
    menu_y_offset_adjust: Option<f64>,
}

fn default_side() -> f64 {
    18.0
}
fn default_offset() -> f64 {
    8.0
}

#[derive(Deserialize)]
struct Monitor {
    focused: bool,
    scale: Option<f64>,
}

// ── Intercepted-flag tracking ────────────────────────────────────────────────

struct Intercepted {
    theme_name: Option<String>,
    have_cfg: bool,
    have_xoff: bool,
    have_yoff: bool,
    have_loc: bool,
    have_kb_cancel: bool,
    have_kb_secondary_copy: bool,
    have_auto_select: bool,
    have_no_auto_select: bool,
    cd_dir: String,
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn xdg_config_home() -> String {
    std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_default();
        format!("{home}/.config")
    })
}

fn xdg_data_home() -> String {
    std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_default();
        format!("{home}/.local/share")
    })
}

/// Extract theme base name from a `-theme` value.
/// Bash equivalent: `sed -E 's#.*/##; s/\.rasi(:.*)?$//'`
fn theme_name_from(val: &str) -> Option<String> {
    let basename = val.rsplit('/').next().unwrap_or(val);
    // Strip .rasi and optional :suffix from end (e.g. "catppuccin.rasi:dark" → "catppuccin")
    let name = basename.split(".rasi").next().unwrap_or(basename);
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

// ── Arg parsing ──────────────────────────────────────────────────────────────

/// Parse intercepted flags from the rofi_args slice.
/// Returns intercepted state + passthrough args that should reach rofi.
fn parse_intercepted(args: &[String]) -> (Intercepted, Vec<String>) {
    let mut state = Intercepted {
        theme_name: None,
        have_cfg: false,
        have_xoff: false,
        have_yoff: false,
        have_loc: false,
        have_kb_cancel: false,
        have_kb_secondary_copy: false,
        have_auto_select: false,
        have_no_auto_select: false,
        cd_dir: format!("{}/rofi", xdg_config_home()),
    };

    let mut passthrough = Vec::with_capacity(args.len());
    let mut prev_is_theme = false;

    for arg in args {
        // Handle value following a bare `-theme` flag
        if prev_is_theme {
            prev_is_theme = false;
            update_from_theme(&mut state, arg);
            passthrough.push(arg.clone());
            continue;
        }

        match arg.as_str() {
            "-theme" => {
                prev_is_theme = true;
            }
            s if s.starts_with("-theme=") => {
                update_from_theme(&mut state, &s["-theme=".len()..]);
            }
            "-no-config" | "-config" => state.have_cfg = true,
            s if s.starts_with("-config=") => state.have_cfg = true,
            "-xoffset" => state.have_xoff = true,
            s if s.starts_with("-xoffset=") => state.have_xoff = true,
            "-yoffset" => state.have_yoff = true,
            s if s.starts_with("-yoffset=") => state.have_yoff = true,
            "-location" => state.have_loc = true,
            s if s.starts_with("-location=") => state.have_loc = true,
            "-kb-cancel" => state.have_kb_cancel = true,
            s if s.starts_with("-kb-cancel=") => state.have_kb_cancel = true,
            "-kb-secondary-copy" => state.have_kb_secondary_copy = true,
            s if s.starts_with("-kb-secondary-copy=") => state.have_kb_secondary_copy = true,
            "-auto-select" => state.have_auto_select = true,
            "-no-auto-select" => state.have_no_auto_select = true,
            _ => {}
        }

        passthrough.push(arg.clone());
    }

    (state, passthrough)
}

/// Update Intercepted state from a -theme value.
fn update_from_theme(state: &mut Intercepted, val: &str) {
    state.theme_name = theme_name_from(val);

    // Determine cd_dir: for bare .rasi filenames (no path components), switch to
    // the themes data dir so @import resolves relative includes.
    if val.starts_with('/') || val.contains('/') {
        // Absolute or relative path — keep config dir default
        state.cd_dir = format!("{}/rofi", xdg_config_home());
    } else if val.ends_with(".rasi") || val.contains(".rasi:") {
        state.cd_dir = format!("{}/rofi/themes", xdg_data_home());
    } else {
        state.cd_dir = format!("{}/rofi", xdg_config_home());
    }
}

// ── Main ─────────────────────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();
    let (intercepted, passthrough) = parse_intercepted(&cli.rofi_args);

    // cd to rofi directory so @import in .rasi files resolves correctly
    let _ = std::env::set_current_dir(&intercepted.cd_dir);

    // ── Compute panel offsets (bash lines 71-99) ─────────────────────────────
    let want_offsets = match &intercepted.theme_name {
        Some(name) if name == "pass" || name.starts_with("askpass") => false,
        _ => true,
    };

    let (mut xoff, mut yoff): (i64, i64) = (0, 0);
    let mut computed_loc = false;

    if want_offsets && !intercepted.have_xoff && !intercepted.have_yoff {
        let theme_json_path = format!("{}/quickshell/Theme/.theme.json", xdg_config_home());

        // Read theme values (defaults matching bash: sideMargin=18, menuYOffset=8)
        let (side_margin, menu_y_offset, menu_y_offset_adjust) =
            std::fs::read_to_string(&theme_json_path)
                .ok()
                .and_then(|content| serde_json::from_str::<ThemeRoot>(&content).ok())
                .map(|root| {
                    let p = root.panel;
                    (p.side_margin, p.menu_y_offset, p.menu_y_offset_adjust)
                })
                .unwrap_or((18.0, 8.0, None));

        // extra defaults to menuYOffset if absent/non-numeric (bash lines 81-86)
        let extra = menu_y_offset_adjust.unwrap_or(menu_y_offset);

        // adjusted_y = max(0, menuYOffset - extra)
        let adjusted_y = (menu_y_offset - extra).max(0.0);

        // Hyprland monitor scale (focused), default 1.0
        let scale = Command::new(&cli.hyprctl_bin)
            .args(["-j", "monitors"])
            .output()
            .ok()
            .and_then(|out| {
                if out.status.success() {
                    serde_json::from_slice::<Vec<Monitor>>(&out.stdout).ok()
                } else {
                    None
                }
            })
            .and_then(|monitors| {
                monitors.iter().find(|m| m.focused).and_then(|m| m.scale)
            })
            .unwrap_or(1.0);

        // Round to nearest int (bash: printf '%.0f')
        xoff = (side_margin * scale).round() as i64;
        yoff = (-adjusted_y * scale).round() as i64;

        computed_loc = !intercepted.have_loc;
    }

    // ── Build final args ─────────────────────────────────────────────────────
    // Order (matching bash prepend/append sequence):
    //   [default pre] [passthrough] [offset post]
    // where default pre mirrors bash's set -- X "$@" prepends in reverse order:
    //   -kb-cancel Control+c,Escape -kb-secondary-copy "" -auto-select -no-config

    let mut final_args: Vec<String> = Vec::new();

    // Default prepends (bash lines 103-121, executed in prepend order;
    // we build them so the final vec has bash's execution order)
    if !intercepted.have_cfg {
        if !intercepted.have_kb_secondary_copy {
            final_args.push("-kb-secondary-copy".into());
            final_args.push(String::new());
        }
        if !intercepted.have_kb_cancel {
            final_args.push("-kb-cancel".into());
            final_args.push("Control+c,Escape".into());
        }
    }
    if !intercepted.have_auto_select && !intercepted.have_no_auto_select {
        final_args.push("-auto-select".into());
    }
    if !intercepted.have_cfg {
        final_args.push("-no-config".into());
    }

    // Reverse so first prepended in bash ends up first in final_args
    // (bash prepends are a stack: last prepended = first in argv)
    final_args.reverse();

    // Passthrough
    final_args.extend(passthrough);

    // Offset / location appends (bash lines 94-98)
    if want_offsets && !intercepted.have_xoff && !intercepted.have_yoff {
        final_args.push("-xoffset".into());
        final_args.push(xoff.to_string());
        final_args.push("-yoffset".into());
        final_args.push(yoff.to_string());
        if computed_loc {
            final_args.push("-location".into());
            final_args.push("7".into());
        }
    }

    // ── Exec rofi ────────────────────────────────────────────────────────────
    let err = Command::new(&cli.rofi_bin).args(&final_args).exec();
    eprintln!("rofiw: failed to exec {}: {}", cli.rofi_bin, err);
    std::process::exit(1);
}
