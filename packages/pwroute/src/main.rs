// PipeWire audio router for RME HDSPe AIO Pro.
//
// Routes the monitored playback stream (monitor_AUX0/1) to different physical
// output channels depending on the selected route:
//   aes    → playback_AUX2/AUX3
//   an     → playback_AUX0/AUX1
//   spdif  → playback_AUX4/AUX5
//   phones → playback_AUX6/AUX7
//
// Replicates the logic of the original pw-route.sh script in Rust.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use regex::Regex;
use serde::Serialize;
use std::process::Command;

// ---------------------------------------------------------------------------
// Route definitions
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
struct Route {
    key: &'static str,
    label: &'static str,
    left_aux: u8,
    right_aux: u8,
}

/// Order matters: iteration order for `current` detection and `toggle` cycling.
const ROUTES: [Route; 4] = [
    Route { key: "an",    label: "Analog",       left_aux: 0, right_aux: 1 },
    Route { key: "aes",   label: "AES/EBU",      left_aux: 2, right_aux: 3 },
    Route { key: "spdif", label: "SPDIF",        left_aux: 4, right_aux: 5 },
    Route { key: "phones",label: "Headphones",   left_aux: 6, right_aux: 7 },
];

fn find_route(key: &str) -> Option<&'static Route> {
    ROUTES.iter().find(|r| r.key == key)
}

#[derive(Debug, Serialize)]
struct RouteJson {
    key: &'static str,
    label: &'static str,
    left: u8,
    right: u8,
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(
    name = "pwroute",
    about = "PipeWire audio router for RME HDSPe AIO Pro"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Route stereo output to AES/EBU digital (AUX2/AUX3)
    Aes,
    /// Route stereo output to Analog line out (AUX0/AUX1)
    An,
    /// Route stereo output to SPDIF digital (AUX4/AUX5)
    Spdif,
    /// Route stereo output to Headphones (AUX6/AUX7)
    Phones,
    /// Toggle active route between AES and Analog
    Toggle,
    /// Print the currently active route key (an|aes|spdif|phones)
    Current,
    /// Show current pw-link connections for the RME sink
    Status,
    /// List all routes as JSON array (for QML UI integration)
    List,
}

// ---------------------------------------------------------------------------
// PipeWire subprocess helpers
// ---------------------------------------------------------------------------

/// Run a command and return trimmed stdout on success.
fn run_cmd(prog: &str, args: &[&str]) -> Result<String> {
    let output = Command::new(prog)
        .args(args)
        .output()
        .with_context(|| format!("failed to run {prog}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("{prog} exited with status {:?}: {}",
            output.status.code(), stderr.trim());
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

/// Find the RME AIO Pro sink name by parsing `pw-cli list-objects Node`.
///
/// Strategy (mirrors the original bash script):
/// 1. Find a node whose `node.name` contains "alsa_output".
/// 2. Confirm it's the RME AIO Pro by checking `node.nick = "RME AIO Pro"`.
/// 3. Return the node name.
fn find_sink_name() -> Result<String> {
    let out = run_cmd("pw-cli", &["list-objects", "Node"])?;

    let name_re = Regex::new(r#"node\.name\s*=\s*"([^"]+)""#).unwrap();
    let nick_re = Regex::new(r#"node\.nick\s*=\s*"RME AIO Pro""#).unwrap();
    let mut current_node: Option<String> = None;

    for line in out.lines() {
        if line.starts_with("id ") {
            current_node = None;
        }
        if let Some(caps) = name_re.captures(line) {
            let name = caps[1].to_string();
            if name.contains("alsa_output") {
                current_node = Some(name);
            }
        }
        if nick_re.is_match(line) {
            if let Some(node) = current_node.take() {
                return Ok(node);
            }
        }
    }

    anyhow::bail!("RME AIO Pro sink not found (no node with alsa_output + RME AIO Pro nick)");
}

/// Parse `pw-link -l` output into a list of (source, destination) pairs.
///
/// Handles both output formats that `pw-link -l` emits:
///   source_port          →  source_port
///       |-> sink_port         |<- source_port
fn parse_link_dump(output: &str) -> Vec<(String, String)> {
    let mut links = Vec::new();
    let mut current: Option<String> = None;

    for line in output.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            current = None;
            continue;
        }
        if line.starts_with(char::is_whitespace) {
            // Indented continuation — extract the linked port.
            if let Some(ref src) = current {
                if let Some(dst) = trimmed.strip_prefix("|-> ") {
                    links.push((src.clone(), dst.to_string()));
                } else if let Some(dst) = trimmed.strip_prefix("|<- ") {
                    links.push((dst.to_string(), src.clone()));
                }
            }
            current = None;
        } else {
            current = Some(trimmed.to_string());
        }
    }

    links
}

/// Disconnect all links from a specific source port. Ignores errors (the link
/// may already be gone or never existed).
fn disconnect_from(links: &[(String, String)], source: &str) {
    for (src, dst) in links {
        if src == source {
            let _ = Command::new("pw-link")
                .args(["-d", src, dst])
                .output();
        }
    }
}

/// Route audio to the given route by:
/// 1. Disconnecting current monitor_AUX0/1 links
/// 2. Connecting monitor_AUX0 → playback_AUX{left_aux}
/// 3. Connecting monitor_AUX1 → playback_AUX{right_aux}
fn route_to(sink: &str, route: &Route) -> Result<()> {
    let link_out = run_cmd("pw-link", &["-l"])?;
    let links = parse_link_dump(&link_out);

    let left_mon = format!("{sink}:monitor_AUX0");
    let right_mon = format!("{sink}:monitor_AUX1");

    disconnect_from(&links, &left_mon);
    disconnect_from(&links, &right_mon);

    let left_dst = format!("{sink}:playback_AUX{}", route.left_aux);
    let right_dst = format!("{sink}:playback_AUX{}", route.right_aux);

    run_cmd("pw-link", &[&left_mon, &left_dst])
        .context("failed to connect monitor_AUX0 → playback_AUX{left_aux}")?;
    run_cmd("pw-link", &[&right_mon, &right_dst])
        .context("failed to connect monitor_AUX1 → playback_AUX{right_aux}")?;

    Ok(())
}

/// Determine which route is currently active by checking whether
/// monitor_AUX0/1 are linked to the route's playback_AUX pair.
fn detect_current(links: &[(String, String)], sink: &str) -> Option<&'static Route> {
    for route in &ROUTES {
        let left_pb = format!("{sink}:playback_AUX{}", route.left_aux);
        let right_pb = format!("{sink}:playback_AUX{}", route.right_aux);
        let left_mon = format!("{sink}:monitor_AUX0");
        let right_mon = format!("{sink}:monitor_AUX1");

        let has_left = links.iter().any(|(src, dst)| *src == left_mon && *dst == left_pb);
        let has_right = links.iter().any(|(src, dst)| *src == right_mon && *dst == right_pb);

        if has_left && has_right {
            return Some(route);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Command handlers
// ---------------------------------------------------------------------------

fn cmd_list() {
    let items: Vec<RouteJson> = ROUTES
        .iter()
        .map(|r| RouteJson {
            key: r.key,
            label: r.label,
            left: r.left_aux,
            right: r.right_aux,
        })
        .collect();
    println!("{}", serde_json::to_string(&items).unwrap());
}

fn cmd_current(sink: &str) -> Result<()> {
    let link_out = run_cmd("pw-link", &["-l"]).unwrap_or_default();
    let links = parse_link_dump(&link_out);
    match detect_current(&links, sink) {
        Some(route) => println!("{}", route.key),
        None => println!("unknown"),
    }
    Ok(())
}

fn cmd_toggle(sink: &str) -> Result<()> {
    let link_out = run_cmd("pw-link", &["-l"]).unwrap_or_default();
    let links = parse_link_dump(&link_out);

    let current = detect_current(&links, sink);
    // Toggle between aes and an. Default to aes if nothing is active.
    let next_key = match current {
        Some(r) if r.key == "aes" => "an",
        _ => "aes",
    };

    let route = find_route(next_key)
        .expect("toggle route not found — this is a bug");
    route_to(sink, route)?;
    println!("{} -> AUX{}/AUX{}", route.key, route.left_aux, route.right_aux);
    Ok(())
}

fn cmd_status(sink: &str) -> Result<()> {
    let link_out = run_cmd("pw-link", &["-l"]).unwrap_or_default();
    let links = parse_link_dump(&link_out);

    // Show playback_AUX ports that are linked from monitor_AUX0/1
    for (src, dst) in &links {
        if dst.starts_with(sink)
            && dst.contains("playback_AUX")
            && (src.ends_with(":monitor_AUX0") || src.ends_with(":monitor_AUX1"))
        {
            println!("{dst}\n\t|<- {src}");
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Commands that don't need the sink name.
    if matches!(cli.command, Commands::List) {
        cmd_list();
        return Ok(());
    }

    let sink = find_sink_name()?;

    match cli.command {
        Commands::List => unreachable!(), // handled above
        Commands::Current => cmd_current(&sink)?,
        Commands::Status => cmd_status(&sink)?,
        Commands::Toggle => cmd_toggle(&sink)?,
        Commands::Aes => {
            let route = find_route("aes").unwrap();
            route_to(&sink, route)?;
            println!("{} -> AUX{}/AUX{}", route.key, route.left_aux, route.right_aux);
        }
        Commands::An => {
            let route = find_route("an").unwrap();
            route_to(&sink, route)?;
            println!("{} -> AUX{}/AUX{}", route.key, route.left_aux, route.right_aux);
        }
        Commands::Spdif => {
            let route = find_route("spdif").unwrap();
            route_to(&sink, route)?;
            println!("{} -> AUX{}/AUX{}", route.key, route.left_aux, route.right_aux);
        }
        Commands::Phones => {
            let route = find_route("phones").unwrap();
            route_to(&sink, route)?;
            println!("{} -> AUX{}/AUX{}", route.key, route.left_aux, route.right_aux);
        }
    }

    Ok(())
}
