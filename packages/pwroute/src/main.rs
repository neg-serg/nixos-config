// PipeWire audio router for RME HDSPe AIO Pro.
//
// Routes the monitored playback stream (monitor_AUX0/1) to different physical
// output channels depending on the selected route:
//   aes    → playback_AUX2/AUX3
//   an     → playback_AUX0/AUX1
//   spdif  → playback_AUX4/AUX5
//   phones → playback_AUX6/AUX7
//

// Also monitors hardware inputs through PipeWire (`pwroute in <src>`): an
// `pw-loopback` instance captures the input pair and plays it back into the RME
// sink's currently active output pair. Analog and SPDIF arrive on AUX0/1 and
// AUX4/5; AES/EBU does not — the card exposes it on capture_AUX0 and
// capture_AUX2, so that pair had to be spelled out per input instead of being
// derived from the output route.
//
// Replicates the logic of the original pw-route.sh script in Rust.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use regex::Regex;
use serde::Serialize;
use std::collections::BTreeSet;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

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
    Route {
        key: "an",
        label: "Analog",
        left_aux: 0,
        right_aux: 1,
    },
    Route {
        key: "aes",
        label: "AES/EBU",
        left_aux: 2,
        right_aux: 3,
    },
    Route {
        key: "spdif",
        label: "SPDIF",
        left_aux: 4,
        right_aux: 5,
    },
    Route {
        key: "phones",
        label: "Headphones",
        left_aux: 6,
        right_aux: 7,
    },
];

fn find_route(key: &str) -> Option<&'static Route> {
    ROUTES.iter().find(|r| r.key == key)
}

// ---------------------------------------------------------------------------
// Input monitor definitions (capture side of the same AUX pairs)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy)]
struct InputRoute {
    key: &'static str,
    label: &'static str,
    /// Capture ports to monitor, as (left, right). These are the card's own
    /// indices and do not have to match the output route's pair: AES/EBU in is
    /// capture_AUX0 / capture_AUX2 while its output is playback_AUX2/AUX3.
    capture_left: u8,
    capture_right: u8,
}

const INPUTS: [InputRoute; 3] = [
    InputRoute {
        key: "an",
        label: "Analog in",
        capture_left: 0,
        capture_right: 1,
    },
    InputRoute {
        key: "aes",
        label: "AES/EBU in",
        capture_left: 0,
        capture_right: 2,
    },
    InputRoute {
        key: "spdif",
        label: "SPDIF in",
        capture_left: 4,
        capture_right: 5,
    },
];

fn find_input(key: &str) -> Option<&'static InputRoute> {
    INPUTS.iter().find(|i| i.key == key)
}

fn input_keys() -> String {
    INPUTS.iter().map(|i| i.key).collect::<Vec<_>>().join("|")
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
    /// Monitor a hardware input pair through PipeWire (an|aes|spdif)
    ///
    /// Starts an `pw-loopback` named pwroute-in-<src>: the RME capture pair
    /// of that input is played back into the RME sink's output pair.
    In {
        /// Input to monitor: an (analog), aes (AES/EBU), spdif
        source: String,
        /// Output pair: current|an|aes|spdif|phones (default: active route)
        #[arg(long, default_value = "current")]
        out: String,
    },
    /// Stop input monitors started with `pwroute in`
    InOff,
    /// Show running input monitors and their links
    InStatus,
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
        anyhow::bail!(
            "{prog} exited with status {:?}: {}",
            output.status.code(),
            stderr.trim()
        );
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

/// Find the RME AIO Pro source (capture) node that belongs to `sink`.
///
/// The sink name is `alsa_output.pci-0000_05_00.0.pro-output-0`; the matching
/// capture node shares the card component (`pci-0000_05_00.0`).
fn find_source_name(sink: &str) -> Result<String> {
    let out = run_cmd("pw-cli", &["list-objects", "Node"])?;

    let name_re = Regex::new(r#"node\.name\s*=\s*"([^"]+)""#).unwrap();
    let card = sink.split('.').nth(1).unwrap_or("");
    let mut fallback: Option<String> = None;

    for line in out.lines() {
        if let Some(caps) = name_re.captures(line) {
            let name = caps[1].to_string();
            if !name.contains("alsa_input") {
                continue;
            }
            if !card.is_empty() && name.contains(card) {
                return Ok(name);
            }
            fallback.get_or_insert(name);
        }
    }

    fallback.ok_or_else(|| anyhow::anyhow!("RME AIO Pro capture node (alsa_input) not found"))
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

/// Disconnect every link that touches `port` (as source or destination).
fn drop_port_links(links: &[(String, String)], port: &str) {
    for (src, dst) in links {
        if src == port || dst == port {
            let _ = Command::new("pw-link").args(["-d", src, dst]).output();
        }
    }
}
/// Disconnect all links from a specific source port. Ignores errors (the link
/// may already be gone or never existed).
fn disconnect_from(links: &[(String, String)], source: &str) {
    for (src, dst) in links {
        if src == source {
            let _ = Command::new("pw-link").args(["-d", src, dst]).output();
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

        let has_left = links
            .iter()
            .any(|(src, dst)| *src == left_mon && *dst == left_pb);
        let has_right = links
            .iter()
            .any(|(src, dst)| *src == right_mon && *dst == right_pb);

        if has_left && has_right {
            return Some(route);
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Input monitoring (pw-loopback based)
// ---------------------------------------------------------------------------

/// Loopback (and stream) name prefix for an input monitor, e.g. `pwroute-in-aes`.
fn loopback_node(input_key: &str) -> String {
    format!("pwroute-in-{input_key}")
}

/// PIDs of the `pw-loopback` processes started for the given node name.
fn loopback_pids(node: &str) -> Vec<u32> {
    let pattern = format!("pw-loopback -n {node}");
    let Ok(output) = Command::new("pgrep").args(["-f", &pattern]).output() else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| line.trim().parse::<u32>().ok())
        .collect()
}

/// Node ids of the loopback streams for `node` currently present in the graph.
///
/// Used instead of `loopback_pids` for existence checks so that `pwroute in`
/// keeps working without procps in `PATH`.
fn loopback_stream_ids(node: &str) -> Vec<u64> {
    let Some(dump) = run_cmd("pw-cli", &["list-objects", "Node"]).ok() else {
        return Vec::new();
    };

    let capture = format!("node.name = \"{node}.capture\"");
    let playback = format!("node.name = \"{node}.playback\"");
    let mut ids = Vec::new();
    let mut current: Option<u64> = None;

    for line in dump.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("id ") {
            current = rest
                .split(|c: char| c == ',' || c.is_whitespace())
                .next()
                .and_then(|value| value.parse().ok());
            continue;
        }
        if (trimmed.starts_with(&capture) || trimmed.starts_with(&playback)) && current.is_some() {
            ids.push(current.expect("checked above"));
        }
    }

    ids
}

/// Start `pw-loopback` for an input monitor, detached from this process.
///
/// Autoconnect is disabled: both links (capture side and playback side) are
/// made explicitly, otherwise WirePlumber would grab AUX0/1 (analog) on both
/// ends — the very bug this command exists to avoid.
fn spawn_loopback(node: &str, source: &str, sink: &str) -> Result<()> {
    let capture = format!("{node}.capture");
    let playback = format!("{node}.playback");

    Command::new("pw-loopback")
        .args(["-n", node, "-m", "[ FL, FR ]"])
        .args(["-i", &format!("node.name={capture}")])
        .args(["-i", &format!("node.description=\"{node} capture\"")])
        .args(["-i", &format!("node.target={source}")])
        .args(["-i", "node.autoconnect=false"])
        .args(["-o", &format!("node.name={playback}")])
        .args(["-o", &format!("node.description=\"{node} playback\"")])
        .args(["-o", &format!("node.target={sink}")])
        .args(["-o", "node.autoconnect=false"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .context("failed to start pw-loopback (is pipewire installed?)")?;

    Ok(())
}

/// Wait until both loopback streams exist in the graph.
fn wait_for_loopback(node: &str, tries: u32) -> Result<()> {
    let capture = format!("node.name = \"{node}.capture\"");
    let playback = format!("node.name = \"{node}.playback\"");

    for _ in 0..tries {
        let dump = run_cmd("pw-cli", &["list-objects", "Node"]).unwrap_or_default();
        if dump.contains(&capture) && dump.contains(&playback) {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(250));
    }

    anyhow::bail!("loopback streams {node}.capture/{node}.playback did not appear in the graph")
}

/// Point the loopback capture side at the requested input pair.
fn ensure_input_links(node: &str, source: &str, input: &InputRoute) -> Result<()> {
    let links = parse_link_dump(&run_cmd("pw-link", &["-l"]).unwrap_or_default());

    let cap_l = format!("{node}.capture:input_FL");
    let cap_r = format!("{node}.capture:input_FR");
    drop_port_links(&links, &cap_l);
    drop_port_links(&links, &cap_r);

    let src_l = format!("{source}:capture_AUX{}", input.capture_left);
    let src_r = format!("{source}:capture_AUX{}", input.capture_right);
    run_cmd("pw-link", &[&src_l, &cap_l])
        .with_context(|| format!("failed to connect {src_l} -> {cap_l}"))?;
    run_cmd("pw-link", &[&src_r, &cap_r])
        .with_context(|| format!("failed to connect {src_r} -> {cap_r}"))?;

    Ok(())
}

/// Point the loopback playback side at the requested output pair.
fn ensure_output_links(node: &str, sink: &str, route: &Route) -> Result<()> {
    let links = parse_link_dump(&run_cmd("pw-link", &["-l"]).unwrap_or_default());

    let pb_l = format!("{node}.playback:output_FL");
    let pb_r = format!("{node}.playback:output_FR");
    drop_port_links(&links, &pb_l);
    drop_port_links(&links, &pb_r);

    let dst_l = format!("{sink}:playback_AUX{}", route.left_aux);
    let dst_r = format!("{sink}:playback_AUX{}", route.right_aux);
    run_cmd("pw-link", &[&pb_l, &dst_l])
        .with_context(|| format!("failed to connect {pb_l} -> {dst_l}"))?;
    run_cmd("pw-link", &[&pb_r, &dst_r])
        .with_context(|| format!("failed to connect {pb_r} -> {dst_r}"))?;

    Ok(())
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

    let route = find_route(next_key).expect("toggle route not found — this is a bug");
    route_to(sink, route)?;
    println!(
        "{} -> AUX{}/AUX{}",
        route.key, route.left_aux, route.right_aux
    );
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

/// Monitor a hardware input pair: capture it and play it back into `route`.
fn cmd_in(source_key: &str, out_key: &str, sink: &str) -> Result<()> {
    let input = find_input(source_key).ok_or_else(|| {
        anyhow::anyhow!("unknown input '{source_key}' (expected {})", input_keys())
    })?;

    let links = parse_link_dump(&run_cmd("pw-link", &["-l"]).unwrap_or_default());
    let (route, route_note) = if out_key == "current" {
        match detect_current(&links, sink) {
            Some(route) => (route, ""),
            None => (find_route("aes").unwrap(), " (no active route, using aes)"),
        }
    } else {
        let route = find_route(out_key).ok_or_else(|| {
            anyhow::anyhow!("unknown output '{out_key}' (expected current|an|aes|spdif|phones)")
        })?;
        (route, "")
    };

    let source = find_source_name(sink)?;
    let node = loopback_node(input.key);

    if loopback_stream_ids(&node).is_empty() {
        spawn_loopback(&node, &source, sink)?;
        wait_for_loopback(&node, 20)?;
    }

    ensure_input_links(&node, &source, input)?;
    ensure_output_links(&node, sink, route)?;

    println!(
        "{} ({}) in {}: capture_AUX{}/AUX{} -> playback_AUX{}/AUX{}{}",
        input.key,
        input.label,
        node,
        input.capture_left,
        input.capture_right,
        route.left_aux,
        route.right_aux,
        route_note
    );
    Ok(())
}

/// Stop every input monitor started by `pwroute in`.
fn cmd_in_off() -> Result<()> {
    let mut stopped = 0;
    for input in &INPUTS {
        let node = loopback_node(input.key);
        for pid in loopback_pids(&node) {
            let _ = Command::new("kill").arg(pid.to_string()).output();
            stopped += 1;
        }
        // Fallback without procps: destroy the stream nodes instead.
        for id in loopback_stream_ids(&node) {
            let _ = run_cmd("pw-cli", &["destroy", &id.to_string()]);
            stopped += 1;
        }
    }

    if stopped == 0 {
        println!("no input monitors running");
    } else {
        println!("stopped {stopped} input monitor(s)");
    }
    Ok(())
}

/// Print the links of every running input monitor.
fn cmd_in_status() -> Result<()> {
    let links = parse_link_dump(&run_cmd("pw-link", &["-l"]).unwrap_or_default());
    let mut printed = false;

    for input in &INPUTS {
        let node = loopback_node(input.key);
        let pids = loopback_pids(&node);
        let ids = loopback_stream_ids(&node);
        if ids.is_empty() && pids.is_empty() {
            continue;
        }

        let mut pairs = BTreeSet::new();
        let prefix = format!("{node}.");
        for (src, dst) in &links {
            if src.starts_with(&prefix) || dst.starts_with(&prefix) {
                pairs.insert((src.clone(), dst.clone()));
            }
        }

        printed = true;
        println!(
            "{:>5} ({}) {}: nodes [{}]{}:",
            input.key,
            input.label,
            node,
            ids.iter().map(u64::to_string).collect::<Vec<_>>().join(","),
            if pids.is_empty() {
                String::new()
            } else {
                format!(
                    ", pids [{}]",
                    pids.iter()
                        .map(u32::to_string)
                        .collect::<Vec<_>>()
                        .join(",")
                )
            }
        );

        for (src, dst) in &pairs {
            println!("  {src} -> {dst}");
        }
    }

    if !printed {
        println!("nothing monitored ({})", input_keys());
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
            println!(
                "{} -> AUX{}/AUX{}",
                route.key, route.left_aux, route.right_aux
            );
        }
        Commands::An => {
            let route = find_route("an").unwrap();
            route_to(&sink, route)?;
            println!(
                "{} -> AUX{}/AUX{}",
                route.key, route.left_aux, route.right_aux
            );
        }
        Commands::Spdif => {
            let route = find_route("spdif").unwrap();
            route_to(&sink, route)?;
            println!(
                "{} -> AUX{}/AUX{}",
                route.key, route.left_aux, route.right_aux
            );
        }
        Commands::Phones => {
            let route = find_route("phones").unwrap();
            route_to(&sink, route)?;
            println!(
                "{} -> AUX{}/AUX{}",
                route.key, route.left_aux, route.right_aux
            );
        }
        Commands::In { source, out } => cmd_in(&source, &out, &sink)?,
        Commands::InOff => cmd_in_off()?,
        Commands::InStatus => cmd_in_status()?,
    }

    Ok(())
}
