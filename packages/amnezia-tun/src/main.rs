// AmneziaVPN config decoder — extracts sing-box compatible JSON from
// AmneziaVPN.ORG configuration files.
//
// Handles three formats:
//   1. last_config = @ByteArray(<base64>)          — base64-decoded JSON
//   2. serversList = "@ByteArray(<escaped JSON>)"  — Qt QSettings escaped JSON
//   3. serversList = "<raw JSON>"                  — plain JSON (legacy)

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
fn extract_payload(data: &str) -> Result<Value> {
    // --- 1. Primary: last_config = @ByteArray(<base64>) ---
    let re_b64 =
        Regex::new(r"(?s)last_config\s*=\s*@ByteArray\(([^)]*)\)").unwrap();
    if let Some(caps) = re_b64.captures(data) {
        let blob: String = caps[1].chars().filter(|c| !c.is_whitespace()).collect();
        let padding = (4 - blob.len() % 4) % 4;
        let padded = format!("{}{}", blob, "=".repeat(padding));
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(&padded)
            .context("invalid base64 in last_config payload")?;
        let payload: Value = serde_json::from_slice(&decoded)
            .context("invalid JSON in last_config payload")?;
        return Ok(payload);
    }

    // --- 2. serversList with @ByteArray wrapper (Qt QSettings format) ---
    let re_ba =
        Regex::new(r#"(?s)serversList="@ByteArray\(([^)]*)\)"#).unwrap();
    if let Some(caps) = re_ba.captures(data) {
        let inner = &caps[1];
        // Unescape Qt-style escapes via serde_json (handles \n, \", \\, etc.)
        let unescaped: String =
            serde_json::from_str(&format!("\"{}\"", inner))
                .context("invalid @ByteArray content in serversList")?;
        let payload = parse_server_last_config(&unescaped)?;
        return Ok(payload);
    }

    // --- 3. Legacy fallback: serversList = "<plain JSON>" ---
    let re_fallback =
        Regex::new(r#"(?s)serversList="(.*?)"\s*$"#).unwrap();
    if let Some(caps) = re_fallback.captures(data) {
        let cleaned = caps[1].replace("\\n", "");
        let unescaped: String =
            serde_json::from_str(&format!("\"{}\"", cleaned))
                .context("invalid serversList string")?;
        let payload = parse_server_last_config(&unescaped)?;
        return Ok(payload);
    }

    bail!("could not locate valid config in AmneziaVPN.conf");
}

/// Given the servers list JSON string, navigate to containers[0].xray.last_config
/// and parse the double-encoded inner JSON.
fn parse_server_last_config(servers_json: &str) -> Result<Value> {
    let servers: Value = serde_json::from_str(servers_json)
        .context("invalid serversList JSON")?;

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
    let payload: Value = serde_json::from_str(last_config_str)
        .context("invalid last_config JSON")?;
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

    let data = std::fs::read_to_string(&src)
        .with_context(|| format!("failed to read {}", src.display()))?;
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
        rules.retain(|rule| {
            rule.get("tag") != Some(&Value::String("vpn-split-router-managed".into()))
        });
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
