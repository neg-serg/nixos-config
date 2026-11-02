//! The client side of the `genlc daemon` socket.
//!
//! The daemon owns the GLM adapter and keeps the lease/poll cycle running; these
//! helpers are the human side of it: one command per run, one reply line back,
//! printed in a shape a person can read. They own no state and touch no hardware —
//! everything goes through the daemon's socket.
//!
//! Socket protocol (one command per line, one reply line each, the daemon serves it):
//! ```text
//! status            -> one JSON line: cycles, volume_db, leases, telemetry
//! volume -30.5      -> ok queued
//! mute on|off       -> ok queued
//! lease             -> ok queued
//! ```
//!
//! The status JSON is read with plain string handling, not a parser: the shape is
//! fixed by the daemon's own `to_json`, four fields do not justify a JSON dependency,
//! and the raw line is printed alongside whenever it is short enough to check by eye.
//! A reply that does not have that shape is reported as unreadable instead of being
//! guessed at.

use anyhow::{Context, Result};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

/// A status reply shorter than this is printed verbatim after the summary: it then
/// fits on a couple of terminal lines, and the exact text is worth more than the
/// extractor above it. Longer replies are only summarised, so that a full telemetry
/// dump cannot bury the numbers.
const RAW_JSON_LIMIT: usize = 200;

/// The daemon's default socket, resolved the way `genlc daemon` resolves it: the
/// session's runtime directory, with the same `/run/user/1000` fallback so a run from
/// cron or a bare shell still finds the daemon on this single-user host.
pub fn default_socket() -> PathBuf {
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())
        .unwrap_or_else(|| "/run/user/1000".into());
    Path::new(&runtime).join("genlc.sock")
}

fn connect(path: &Path) -> Result<UnixStream> {
    UnixStream::connect(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => anyhow::anyhow!(
            "genlc is not running (no socket at {}) — start it with: systemctl --user start genlc",
            path.display()
        ),
        // The file is there but nobody accepts on it: a daemon killed without its
        // shutdown path leaves exactly this, and the remedy is the same one.
        std::io::ErrorKind::ConnectionRefused => anyhow::anyhow!(
            "genlc is not accepting connections on {} (stale socket from an earlier run?) — \
             start it with: systemctl --user start genlc",
            path.display()
        ),
        std::io::ErrorKind::PermissionDenied => anyhow::Error::new(e).context(format!(
            "connecting to {} (the socket belongs to another user's session?)",
            path.display()
        )),
        _ => anyhow::Error::new(e).context(format!("connecting to {}", path.display())),
    })
}

/// Send one command line, read one reply line. The daemon speaks request/reply on a
/// plain connection, so a single exchange per connection is all this needs.
pub fn round_trip(socket: &Path, request: &str) -> Result<String> {
    let mut stream = connect(socket)?;
    writeln!(stream, "{request}").with_context(|| format!("sending {request:?} to genlc"))?;
    // `UnixStream`'s `Write` is unbuffered, so the line is already gone; the flush
    // documents the intent and costs one syscall-free call.
    stream.flush().ok();

    let mut reply = String::new();
    BufReader::new(stream)
        .read_line(&mut reply)
        .with_context(|| format!("reading genlc's reply to {request:?}"))?;
    let reply = reply.trim_end().to_string();
    if reply.is_empty() {
        anyhow::bail!(
            "genlc closed the connection without answering {request:?} — check its log: \
             journalctl --user -u genlc"
        );
    }
    Ok(reply)
}

pub fn print_status(json: &str, socket: &Path) -> Result<()> {
    let cycles = scalar_field(json, "cycles").context(
        "genlc's status reply carries no \"cycles\" field — is it a genlc this client knows?",
    )?;
    let volume = match scalar_field(json, "volume_db").unwrap_or("null") {
        "null" => "not set yet (nothing sent this run)".to_string(),
        value => format!("{value} dB"),
    };
    let telemetry = container_field(json, "telemetry", '{', '}').unwrap_or_default();
    let leases = container_field(json, "leases", '[', ']')
        .map(lease_entries)
        .unwrap_or_default();

    println!("cycles  {cycles}");
    println!("volume  {volume}");
    if leases.is_empty() {
        // An empty list means no monitor answered the probe since the daemon started;
        // `lease` forces a probe cycle instead of waiting for the next one.
        println!("leases  0 (no monitor holds a lease — force a probe with: genlc lease --now)");
    } else {
        println!("leases  {}", leases.len());
        println!("  hw id     session  telemetry");
        for (hardware_id, session) in leases {
            let seen = match telemetry_for(telemetry, session) {
                Some(hex) if hex.is_empty() => "polled (no bytes)".to_string(),
                Some(hex) => format!("yes ({})", shorten(&hex, 23)),
                None => "no — poll it with: genlc lease --now".to_string(),
            };
            // The session is printed in hex because that is how the protocol, the
            // daemon's telemetry keys and every capture refer to it; the JSON numbers
            // it in decimal, which the raw line below shows when it is short enough.
            println!("  {hardware_id:<9} {session:02X}       {seen}");
        }
    }

    if json.len() < RAW_JSON_LIMIT {
        println!("raw reply (unparsed JSON): {json}");
    } else {
        // Say that the summary is all there is, rather than letting the reader assume
        // the table is the complete reply.
        println!(
            "raw reply omitted: {} bytes, over the {RAW_JSON_LIMIT}-byte raw limit — \
             ask the daemon directly for it: printf 'status\\n' | socat - UNIX-CONNECT:{}",
            json.len(),
            socket.display()
        );
    }
    Ok(())
}

/// Where a value starts that follows `"key":`, with the spaces after the colon
/// already skipped. `genlc` writes none, but a reply from anything else (a test stub,
/// `jq -c` output, a future daemon) may have them — accepting both costs one call and
/// avoids reporting "no leases" for a reply that merely has a space there.
fn after_key(json: &str, key: &str) -> Option<usize> {
    let needle = format!("\"{key}\":");
    let index = json.find(&needle)? + needle.len();
    let rest = &json[index..];
    Some(index + (rest.len() - rest.trim_start().len()))
}

/// The value of a `"key":<scalar>` pair, up to the next `,` or `}`. Scalars only:
/// the daemon writes numbers, `null` and short quoted strings there, never nested
/// structure (see `genlc`'s `to_json`).
pub fn scalar_field<'a>(json: &'a str, key: &str) -> Option<&'a str> {
    let rest = &json[after_key(json, key)?..];
    let value = rest[..rest.find([',', '}']).unwrap_or(rest.len())].trim();
    (!value.is_empty()).then_some(value)
}

/// The body of the balanced `{…}` or `[…]` value of `"key":` — the braces are not
/// included. Depth counting has to ignore brackets inside strings, and the daemon
/// emits no escape sequences, so toggling a flag on `"` is enough to keep the
/// telemetry hex (spaces, no brackets) from confusing the scan.
fn container_field<'a>(json: &'a str, key: &str, open: char, close: char) -> Option<&'a str> {
    let start = after_key(json, key)?;
    let rest = json[start..].strip_prefix(open)?;
    let start = json.len() - rest.len();
    let mut depth = 1usize;
    let mut quoted = false;
    for (offset, c) in json[start..].char_indices() {
        if c == '"' {
            quoted = !quoted;
        } else if !quoted {
            if c == open {
                depth += 1;
            } else if c == close {
                depth -= 1;
                if depth == 0 {
                    return Some(&json[start..start + offset]);
                }
            }
        }
    }
    None
}

/// The `{…}` entries of the leases array as (hardware id, session) pairs. A lease
/// object is flat, so splitting on the first `}` of each chunk is enough — anything
/// unexpected is dropped rather than printed wrong.
fn lease_entries(array: &str) -> Vec<(String, u8)> {
    let mut leases = Vec::new();
    for chunk in array.split('{').skip(1) {
        let object = chunk.split('}').next().unwrap_or(chunk);
        let hardware_id = scalar_field(object, "hardware_id").map(|id| id.trim_matches('"'));
        let session = scalar_field(object, "session").and_then(|s| s.parse::<u8>().ok());
        if let (Some(id), Some(session)) = (hardware_id, session) {
            leases.push((id.to_string(), session));
        }
    }
    leases
}

/// The telemetry bytes the daemon holds for one session, if it polled it. Telemetry
/// is keyed by the hex session id (`"03"`), while the lease list numbers sessions in
/// decimal — that mismatch is exactly what this lookup bridges.
fn telemetry_for(telemetry: &str, session: u8) -> Option<String> {
    let start = after_key(telemetry, &format!("{session:02X}"))?;
    let rest = telemetry[start..].strip_prefix('"')?;
    let end = rest.find('"').unwrap_or(rest.len());
    Some(rest[..end].to_string())
}

/// Shorten a telemetry hex dump for the table: the daemon keeps only the last frame,
/// but a full one is still wider than a terminal column.
fn shorten(text: &str, max_chars: usize) -> String {
    if text.chars().count() <= max_chars {
        text.to_string()
    } else {
        let head: String = text.chars().take(max_chars).collect();
        format!("{head}…")
    }
}
