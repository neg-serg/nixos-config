//! game — Unified game launcher.
//!
//! Replaces: game-run, game-affinity-exec, gamescope-{perf,quality,hdr,targetfps,pinned},
//! game-pinned, game-session, game-session-mangohud, gamescope-run, gamescope-app.

#![warn(unused_extern_crates)]

use std::os::unix::process::CommandExt;
use std::process::Command;

mod app;
mod cli;
mod config;
mod cpu;
mod display;
mod gamemode;
mod gamescope;

use clap::Parser;
use cli::{Cli, Commands};
use gamescope::Preset;

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Run {
            cpus,
            no_gamemode,
            no_pin,
            dry_run,
            command,
        } => cmd_run(cpus, no_gamemode, no_pin, dry_run, command),

        Commands::Scope {
            preset,
            scale,
            fsr_sharpness,
            hdr,
            no_vrr,
            no_pin,
            dry_run,
            command,
        } => cmd_scope(preset, scale, fsr_sharpness, hdr, no_vrr, no_pin, dry_run, command),

        Commands::Session {
            mangohud,
            no_hdr,
            no_pin,
            dry_run,
        } => cmd_session(mangohud, no_hdr, no_pin, dry_run),

        Commands::App {
            resolution,
            filter,
            fullscreen,
            no_wayland,
            sharpness,
            no_pin,
            dry_run,
            command,
        } => cmd_app(resolution, filter, fullscreen, no_wayland, sharpness, no_pin, dry_run, command),

        Commands::Info { json } => cmd_info(json),
    }
}

// ── Helpers ────────────────────────────────────────────────────────────

fn format_cpuset(cpus: &[usize]) -> String {
    if cpus.is_empty() {
        return String::new();
    }
    let mut parts = Vec::new();
    let mut i = 0;
    while i < cpus.len() {
        let start = cpus[i];
        let mut end = start;
        while i + 1 < cpus.len() && cpus[i + 1] == end + 1 {
            end = cpus[i + 1];
            i += 1;
        }
        if start == end {
            parts.push(format!("{start}"));
        } else {
            parts.push(format!("{start}-{end}"));
        }
        i += 1;
    }
    parts.join(",")
}

fn resolve_cpuset(cli_arg: &str) -> Vec<usize> {
    match cli_arg {
        "auto" => cpu::auto_cpuset().unwrap_or_default(),
        "" => Vec::new(),
        s => cpu::parse_cpuset(s),
    }
}

fn detect_hdr_from_env() -> bool {
    std::env::var("DXVK_HDR").map(|v| v == "1").unwrap_or(false)
        || std::env::var("ENABLE_HDR_WSI").map(|v| v == "1").unwrap_or(false)
}

fn resolve_steam_app_id(cmd: &[String]) -> Option<String> {
    // First check SteamAppId env var
    if let Ok(id) = std::env::var("SteamAppId") {
        return Some(id);
    }
    // Fall back to path parsing
    config::extract_app_id(cmd)
}

// ── Run ────────────────────────────────────────────────────────────────

fn cmd_run(
    cpus_arg: String,
    no_gamemode: bool,
    no_pin: bool,
    dry_run: bool,
    command: Vec<String>,
) {
    if command.is_empty() {
        eprintln!("game run: no command specified");
        std::process::exit(1);
    }

    // Resolve CPU set
    let cpus = if no_pin {
        Vec::new()
    } else {
        resolve_cpuset(&cpus_arg)
    };

    // Check gamemode availability
    let use_gamemode = !no_gamemode && gamemode::is_available();

    // Build systemd-run command
    let mut cmd_parts: Vec<String> = vec![
        "systemd-run".into(),
        "--user".into(),
        "--scope".into(),
        "--same-dir".into(),
        "--collect".into(),
    ];
    cmd_parts.push("-p".into());
    cmd_parts.push("Slice=games.slice".into());
    cmd_parts.push("-p".into());
    cmd_parts.push("CPUWeight=10000".into());
    cmd_parts.push("-p".into());
    cmd_parts.push("IOWeight=10000".into());
    cmd_parts.push("-p".into());
    cmd_parts.push("TasksMax=infinity".into());

    if !cpus.is_empty() {
        let cpu_str = format_cpuset(&cpus);
        cmd_parts.push("-p".into());
        cmd_parts.push(format!("AllowedCPUs={cpu_str}"));
        // Also set AllowedMemoryNodes=0 to avoid cross-CCD memory access
        cmd_parts.push("-p".into());
        cmd_parts.push("AllowedMemoryNodes=0".into());
    }

    cmd_parts.push("--".into());

    if use_gamemode {
        cmd_parts.push("gamemoderun".into());
    }

    cmd_parts.extend(command.clone());

    if dry_run {
        let cpu_desc = if cpus.is_empty() {
            "none".to_string()
        } else {
            format_cpuset(&cpus)
        };
        eprintln!("[game] mode: run");
        eprintln!("[game] cpuset: {cpu_desc}");
        eprintln!("[game] gamemode: {}", if use_gamemode { "yes" } else { "no" });
        eprintln!("[game] exec: {}", cmd_parts.join(" "));
        return;
    }

    // Execute via execvp (replaces this process)
    let err = Command::new(&cmd_parts[0]).args(&cmd_parts[1..]).exec();
    eprintln!("game run: failed to execute: {err}");
    std::process::exit(1);
}

// ── Scope ──────────────────────────────────────────────────────────────

fn cmd_scope(
    preset_name: Option<String>,
    scale_override: Option<f64>,
    fsr_sharpness: Option<i32>,
    hdr_flag: bool,
    _no_vrr: bool,
    no_pin: bool,
    dry_run: bool,
    command: Vec<String>,
) {
    if command.is_empty() {
        eprintln!("game scope: no command specified");
        std::process::exit(1);
    }

    // Soulstone Survivors workaround: skip gamescope
    if gamescope::should_skip_gamescope(&command) {
        if dry_run {
            eprintln!("[game] Soulstone Survivors detected — skipping gamescope");
            eprintln!("[game] exec: {}", command.join(" "));
            return;
        }
        // Exec directly (no gamescope, no systemd-run)
        let err = Command::new(&command[0]).args(&command[1..]).exec();
        eprintln!("game scope: failed to execute: {err}");
        std::process::exit(1);
    }

    // Resolve preset
    let app_id = resolve_steam_app_id(&command);
    let resolved_preset = resolve_preset(preset_name, hdr_flag, app_id.as_deref());

    if resolved_preset == Preset::Skip {
        if dry_run {
            eprintln!("[game] preset: skip — running directly");
            eprintln!("[game] exec: {}", command.join(" "));
            return;
        }
        let err = Command::new(&command[0]).args(&command[1..]).exec();
        eprintln!("game scope: failed to execute: {err}");
        std::process::exit(1);
    }

    // Resolve display
    let display = display::resolve_display();

    // Build gamescope flags
    let gs_flags = gamescope::build_flags(resolved_preset, &display, scale_override, fsr_sharpness);

    // Build full command: gamescope <flags> -- <command>
    let mut full_cmd: Vec<String> = vec!["gamescope".into()];
    full_cmd.extend(gs_flags);
    full_cmd.push("--".into());
    full_cmd.extend(command.clone());

    // Prepend with our run wrapper (CPU pinning + gamemode)
    if no_pin {
        if dry_run {
            eprintln!("[game] mode: scope");
            eprintln!("[game] preset: {}", resolved_preset.name());
            eprintln!("[game] display: {}x{}@{}Hz", display.width, display.height, display.refresh_rate);
            eprintln!("[game] pinning: disabled");
            eprintln!("[game] exec: {}", full_cmd.join(" "));
            return;
        }
        // Direct exec without pinning
        let err = Command::new(&full_cmd[0]).args(&full_cmd[1..]).exec();
        eprintln!("game scope: failed to execute: {err}");
        std::process::exit(1);
    } else {
        // Wrap with game run
        let cpus = cpu::auto_cpuset().unwrap_or_default();
        let use_gamemode = gamemode::is_available();

        let mut sysd_cmd: Vec<String> = vec![
            "systemd-run".into(),
            "--user".into(),
            "--scope".into(),
            "--same-dir".into(),
            "--collect".into(),
        ];
        sysd_cmd.push("-p".into());
        sysd_cmd.push("Slice=games.slice".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("CPUWeight=10000".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("IOWeight=10000".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("TasksMax=infinity".into());

        if !cpus.is_empty() {
            let cpu_str = format_cpuset(&cpus);
            sysd_cmd.push("-p".into());
            sysd_cmd.push(format!("AllowedCPUs={cpu_str}"));
            sysd_cmd.push("-p".into());
            sysd_cmd.push("AllowedMemoryNodes=0".into());
        }

        sysd_cmd.push("--".into());

        if use_gamemode {
            sysd_cmd.push("gamemoderun".into());
        }

        sysd_cmd.extend(full_cmd);

        if dry_run {
            eprintln!("[game] mode: scope");
            eprintln!("[game] preset: {} (from {})", resolved_preset.name(),
                app_id.map(|a| format!("game config for {a}")).unwrap_or_else(|| "cli".into()));
            eprintln!("[game] display: {}x{}@{}Hz", display.width, display.height, display.refresh_rate);
            eprintln!("[game] cpuset: {}", format_cpuset(&cpus));
            eprintln!("[game] gamemode: {}", if use_gamemode { "yes" } else { "no" });
            eprintln!("[game] exec: {}", sysd_cmd.join(" "));
            return;
        }

        let err = Command::new(&sysd_cmd[0]).args(&sysd_cmd[1..]).exec();
        eprintln!("game scope: failed to execute: {err}");
        std::process::exit(1);
    }
}

fn resolve_preset(preset_name: Option<String>, hdr_flag: bool, app_id: Option<&str>) -> Preset {
    // CLI flag takes precedence
    if let Some(name) = preset_name {
        return Preset::from_name(&name).unwrap_or(Preset::Quality);
    }

    // --hdr flag overrides to HDR
    if hdr_flag {
        return Preset::Hdr;
    }

    // HDR env var detection
    if detect_hdr_from_env() {
        return Preset::Hdr;
    }

    // Per-game config
    if let Some(id) = app_id {
        let (preset, _) = config::resolve_game_preset(Some(id));
        if let Some(p) = Preset::from_name(&preset) {
            return p;
        }
    }

    // Global config
    let cfg = config::load_config();
    Preset::from_name(&cfg.defaults.preset).unwrap_or(Preset::Quality)
}

// ── Session ────────────────────────────────────────────────────────────

#[allow(unused_variables)]
#[allow(unused_variables)]
fn cmd_session(mangohud: bool, no_hdr: bool, no_pin: bool, dry_run: bool) {
    let mut gs_flags = Vec::new();

    // Build gamescope args
    if !no_hdr {
        gs_flags.push("--hdr-enabled".into());
        gs_flags.push("--hdr-debug-force-output".into());
    }
    gs_flags.push("--rt".into());
    gs_flags.push("--steam".into());

    if mangohud {
        gs_flags.push("--adaptive-sync".into());
        gs_flags.push("--mangoapp".into());
    }

    let steam_flags = vec!["-pipewire-dmabuf".into(), "-tenfoot".into()];

    // Build full command: game session gamescope <flags> -- steam <steam-flags>
    let mut full_cmd: Vec<String> = vec!["gamescope".into()];
    full_cmd.extend(gs_flags);
    full_cmd.push("--".into());
    full_cmd.push("steam".into());
    full_cmd.extend(steam_flags);

    // Environment variables
    let env_hdr = if !no_hdr {
        Some(("DXVK_HDR".to_string(), "1".to_string()))
    } else {
        None
    };

    let env_mangohud = if mangohud {
        Some(("MANGOHUD".to_string(), "1".to_string()))
    } else {
        None
    };

    if no_pin {
        if dry_run {
            eprintln!("[game] mode: session");
            eprintln!("[game] hdr: {}", if !no_hdr { "yes" } else { "no" });
            eprintln!("[game] mangohud: {}", if mangohud { "yes" } else { "no" });
            eprintln!("[game] exec: {}", full_cmd.join(" "));
            return;
        }

        // Set env vars and exec
        if let Some((k, v)) = env_hdr {
            std::env::set_var(k, v);
        }
        if let Some((k, v)) = env_mangohud {
            std::env::set_var(k, v);
        }

        let err = Command::new(&full_cmd[0]).args(&full_cmd[1..]).exec();
        eprintln!("game session: failed to execute: {err}");
        std::process::exit(1);
    } else {
        // Wrap with systemd-run + gamemode
        let cpus = cpu::auto_cpuset().unwrap_or_default();
        let use_gamemode = gamemode::is_available();

        let mut sysd_cmd: Vec<String> = vec![
            "systemd-run".into(),
            "--user".into(),
            "--scope".into(),
            "--same-dir".into(),
            "--collect".into(),
        ];
        sysd_cmd.push("-p".into());
        sysd_cmd.push("Slice=games.slice".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("CPUWeight=10000".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("IOWeight=10000".into());
        sysd_cmd.push("-p".into());
        sysd_cmd.push("TasksMax=infinity".into());

        if !cpus.is_empty() {
            let cpu_str = format_cpuset(&cpus);
            sysd_cmd.push("-p".into());
            sysd_cmd.push(format!("AllowedCPUs={cpu_str}"));
            sysd_cmd.push("-p".into());
            sysd_cmd.push("AllowedMemoryNodes=0".into());
        }

        sysd_cmd.push("--".into());

        if use_gamemode {
            sysd_cmd.push("gamemoderun".into());
        }

        sysd_cmd.extend(full_cmd);

        if dry_run {
            eprintln!("[game] mode: session");
            eprintln!("[game] hdr: {}", if !no_hdr { "yes" } else { "no" });
            eprintln!("[game] mangohud: {}", if mangohud { "yes" } else { "no" });
            eprintln!("[game] cpuset: {}", format_cpuset(&cpus));
            eprintln!("[game] exec: {}", sysd_cmd.join(" "));
            return;
        }

        // Set env vars
        if let Some((k, v)) = env_hdr {
            std::env::set_var(k, v);
        }
        if let Some((k, v)) = env_mangohud {
            std::env::set_var(k, v);
        }

        let err = Command::new(&sysd_cmd[0]).args(&sysd_cmd[1..]).exec();
        eprintln!("game session: failed to execute: {err}");
        std::process::exit(1);
    }
}

// ── App ────────────────────────────────────────────────────────────────

fn cmd_app(
    resolution: String,
    filter: Option<String>,
    fullscreen: bool,
    no_wayland: bool,
    sharpness: i32,
    _no_pin: bool,
    dry_run: bool,
    command: Vec<String>,
) {
    if command.is_empty() {
        eprintln!("game app: no command specified");
        std::process::exit(1);
    }

    // Resolve resolution
    let res = app::Resolution::from_name(&resolution).unwrap_or(app::Resolution::P1080);

    // Resolve filter
    let filter = filter
        .as_ref()
        .and_then(|f| app::Filter::from_name(f))
        .unwrap_or_else(|| {
            // Auto-detect based on resolution
            match res {
                app::Resolution::P1080 | app::Resolution::P720 => app::Filter::Nearest,
                app::Resolution::P1440 => app::Filter::Fsr,
                app::Resolution::Custom(_, _) => app::Filter::Fsr,
            }
        });

    // Scaler auto-detect
    let scaler = match res {
        app::Resolution::P1080 | app::Resolution::P720 => app::Scaler::Integer,
        app::Resolution::P1440 => app::Scaler::Fit,
        app::Resolution::Custom(_, _) => app::Scaler::Fit,
    };

    let display = display::resolve_display();

    let gs_flags = app::build_app_flags(
        &display, &res, filter, scaler, fullscreen, !no_wayland, sharpness,
    );

    let mut full_cmd: Vec<String> = vec!["gamescope".into()];
    full_cmd.extend(gs_flags);
    full_cmd.push("--".into());
    full_cmd.extend(command.clone());

    if dry_run {
        eprintln!("[game] mode: app");
        eprintln!("[game] resolution: inner {}x{} @ {}x{} (outer) @ {}Hz",
            res.dimensions(&display).0, res.dimensions(&display).1,
            display.width, display.height, display.refresh_rate);
        eprintln!("[game] filter: {}, scaler: {}", filter.as_str(), scaler.as_str());
        eprintln!("[game] exec: {}", full_cmd.join(" "));
        return;
    }

    let err = Command::new(&full_cmd[0]).args(&full_cmd[1..]).exec();
    eprintln!("game app: failed to execute: {err}");
    std::process::exit(1);
}

// ── Info ───────────────────────────────────────────────────────────────

fn cmd_info(json: bool) {
    if json {
        let info = serde_json::json!({
            "cpu": {
                "topology": cpu::describe_topology(),
            },
            "display": display::describe_display(),
            "gamemode": gamemode::describe(),
        });
        println!("{}", serde_json::to_string_pretty(&info).unwrap());
    } else {
        println!("── CPU ──────────────────────────────────────");
        println!("{}", cpu::describe_topology());
        println!();
        println!("── Display ───────────────────────────────────");
        println!("{}", display::describe_display());
        println!();
        println!("── Gamemode ──────────────────────────────────");
        println!("{}", gamemode::describe());
    }
}
