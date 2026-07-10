// AmneziaVPN config decoder — extracts sing-box compatible JSON from
// AmneziaVPN.ORG configuration files. Handles both the @ByteArray base64
// format and the serversList JSON fallback.

use anyhow::{Context, Result, bail};
use base64::Engine;
use clap::{Parser, Subcommand};
use regex::Regex;
use serde_json::Value;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(name = "amnezia-tun", about = "Decode AmneziaVPN config to sing-box compatible JSON")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand)]
enum Command {
    /// Import/convert AmneziaVPN config to sing-box format (default)
    Import,
    /// Print the expected output path
    ShowPath,
    /// Verify output matches source (strips vpn-split-router-managed rules)
    Check,
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

fn home_dir() -> PathBuf {
    PathBuf::from(std::env::var("HOME").as_deref().unwrap_or("/root"))
}

fn src_path() -> PathBuf {
    home_dir().join(".config/AmneziaVPN.ORG/AmneziaVPN.conf")
}

fn out_path() -> PathBuf {
    home_dir().join(".config/sing-box-tun/config.json")
}

// ---------------------------------------------------------------------------
// Decoding
// ---------------------------------------------------------------------------

/// Extract the sing-box config payload from AmneziaVPN.conf content.
///
/// Strategy (mirrors the Python original):
/// 1. Try `last_config=@ByteArray(...)` — base64-decode and parse as JSON.
/// 2. Fall back to `serversList="..."` — parse outer JSON, walk to
///    `containers[0].xray.last_config`, unescape via serde_json.
fn extract_payload(data: &str) -> Result<Value> {
    // Primary: last_config = @ByteArray(<base64>)
    let re_primary =
        Regex::new(r"(?s)last_config\s*=\s*@ByteArray\(([^)]*)\)").unwrap();
    if let Some(caps) = re_primary.captures(data) {
        // Strip all whitespace (same as Python: ''.join(match.group(1).split()))
        let blob: String = caps[1].chars().filter(|c| !c.is_whitespace()).collect();
        // Add base64 padding
        let padding = (4 - blob.len() % 4) % 4;
        let padded = format!("{}{}", blob, "=".repeat(padding));
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(&padded)
            .context("invalid base64 in last_config payload")?;
        let payload: Value =
            serde_json::from_slice(&decoded).context("invalid JSON in last_config payload")?;
        return Ok(payload);
    }

    // Fallback: serversList = "<JSON>"
    let re_fallback =
        Regex::new(r#"(?s)serversList="(.*?)"\n"#).unwrap();
    let caps = re_fallback
        .captures(data)
        .context("could not locate serversList in AmneziaVPN.conf")?;
    let raw = &caps[1];

    // Replicate Python's unescape pipeline via serde_json:
    //   Python: replace('\\n','') → replace('\\"','"') → unicode_escape → json.loads
    //   Rust:   replace("\\n", "") → wrap in quotes → serde_json::from_str<String>
    //           serde_json handles \" and all other JSON escapes natively.
    let cleaned = raw.replace("\\n", "");
    let unescaped: String =
        serde_json::from_str(&format!("\"{}\"", cleaned)).context("invalid serversList string")?;
    let servers: Value =
        serde_json::from_str(&unescaped).context("invalid serversList JSON")?;

    let container = servers[0]
        .get("containers")
        .and_then(|a| a.as_array())
        .and_then(|a| a.first())
        .context("no containers in server")?;
    let last_config_str = container
        .get("xray")
        .and_then(|x| x.get("last_config"))
        .and_then(|v| v.as_str())
        .context("last_config not found in xray container")?;

    // The last_config value is a JSON-encoded string; parse it.
    let payload: Value =
        serde_json::from_str(last_config_str).context("invalid last_config JSON")?;
    Ok(payload)
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmd_import() -> Result<()> {
    let src = src_path();
    let data = std::fs::read_to_string(&src)
        .with_context(|| format!("missing source config: {}", src.display()))?;
    let payload = extract_payload(&data)?;

    let out = out_path();
    if let Some(parent) = out.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }

    let json_str = serde_json::to_string_pretty(&payload)?;
    std::fs::write(&out, json_str + "\n")
        .with_context(|| format!("failed to write {}", out.display()))?;

    // Set permissions to 0o600 (owner rw only)
    std::fs::set_permissions(&out, std::fs::Permissions::from_mode(0o600))
        .with_context(|| format!("failed to set permissions on {}", out.display()))?;

    println!("{}", out.display());
    Ok(())
}

fn cmd_show_path() {
    println!("{}", out_path().display());
}

fn cmd_check() -> Result<()> {
    let src = src_path();
    let out = out_path();

    if !src.exists() {
        bail!("missing source config: {}", src.display());
    }
    if !out.exists() {
        bail!("missing runtime config: {}", out.display());
    }

    let data =
        std::fs::read_to_string(&src).with_context(|| format!("failed to read {}", src.display()))?;
    let expected = extract_payload(&data)?;

    let current: Value = serde_json::from_str(
        &std::fs::read_to_string(&out)
            .with_context(|| format!("failed to read {}", out.display()))?,
    )
    .with_context(|| format!("failed to parse {}", out.display()))?;

    // Strip vpn-split-router-managed rules from current (same as Python original)
    let mut current = current;
    if let Some(rules) = current
        .get_mut("route")
        .and_then(|r| r.get_mut("rules"))
        .and_then(|r| r.as_array_mut())
    {
        rules.retain(|rule| rule.get("tag") != Some(&Value::String("vpn-split-router-managed".into())));
    }

    // Ensure expected has at least an empty rules array in route (matches Python)
    let mut expected = expected;
    if let Some(route) = expected.get_mut("route") {
        if route.get("rules").is_none() {
            route
                .as_object_mut()
                .map(|obj| obj.insert("rules".into(), Value::Array(vec![])));
        }
    }

    if current == expected {
        Ok(())
    } else {
        bail!("{} does not match imported AmneziaVPN payload", out.display());
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command.unwrap_or(Command::Import) {
        Command::Import => cmd_import()?,
        Command::ShowPath => cmd_show_path(),
        Command::Check => cmd_check()?,
    }
    Ok(())
}
