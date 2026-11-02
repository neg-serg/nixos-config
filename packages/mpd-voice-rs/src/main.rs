//! mpd-voice (Rust): voice control for MPD.
//!
//! Stage 1 of the port: the MPD client, the config loader and the read-only
//! commands (`status`, `doctor`, `ping`) are Rust; capture, STT/TTS and the
//! intent parser still come from the Python tree, which keeps building until
//! the port reaches parity. The crate is exposed as `nix build .#mpd-voice-rs`
//! for exactly that reason — it is not the installed `mpd-voice` yet.

mod config;
mod intents;
mod mpd;
mod rex;
mod song;
mod toml;

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use config::Config;
use mpd::{Meta, MpdClient, MpdError};

const DOC: &str = "\
mpd-voice — voice control for MPD (Rust port, stage 1).

Usage:
  mpd-voice [--config PATH] [--json] <command>

Commands:
  parse TEXT...     the intent a phrase maps to (JSON)
  phrases           every supported phrase, both languages
  status [--json]   what MPD is playing, or `stopped`
  doctor            MPD reachability plus the config files in effect
  ping              connect, greet, disconnect
  config            the effective configuration as TOML

`--config PATH` reads one file instead of the XDG chain; `--json` switches
`status` to machine output.";

const EXIT_OK: u8 = 0;
const EXIT_ERROR: u8 = 1;
const EXIT_UNKNOWN: u8 = 2;

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    ExitCode::from(run(&argv))
}

fn run(argv: &[String]) -> u8 {
    let mut json = false;
    let mut config_path: Option<PathBuf> = None;
    let mut rest: Vec<String> = Vec::new();
    let mut index = 0;
    while index < argv.len() {
        match argv[index].as_str() {
            "--json" => {
                json = true;
                index += 1;
            }
            "--config" if index + 1 < argv.len() => {
                config_path = Some(PathBuf::from(&argv[index + 1]));
                index += 2;
            }
            "-h" | "--help" => {
                println!("{DOC}");
                return EXIT_OK;
            }
            other => {
                rest.push(other.to_string());
                index += 1;
            }
        }
    }
    let (cfg, sources) = config::load(config_path.as_deref());
    let Some(command) = rest.first() else {
        println!("{DOC}");
        return EXIT_OK;
    };
    match command.as_str() {
        "status" => cmd_status(&cfg, json),
        "ping" => cmd_ping(&cfg),
        "doctor" => cmd_doctor(&cfg, &sources),
        "config" => {
            println!("{}", cfg.as_toml());
            EXIT_OK
        }
        "parse" => cmd_parse(&rest[1..]),
        "phrases" => cmd_phrases(),
        // Hidden helper for the parity harness: print what the engine matched.
        "rex" if rest.len() >= 3 => cmd_rex(&rest[1], &rest[2]),
        other => {
            eprintln!("unknown command: {other}");
            println!("{DOC}");
            EXIT_UNKNOWN
        }
    }
}

fn client(cfg: &Config, timeout: Duration) -> MpdClient {
    let password = if cfg.mpd_password.is_empty() {
        None
    } else {
        Some(cfg.mpd_password.clone())
    };
    MpdClient::new(&cfg.mpd_host, cfg.mpd_port as u16, password, timeout)
}

fn cmd_status(cfg: &Config, json: bool) -> u8 {
    let mut client = client(cfg, Duration::from_secs(5));
    let song = match client.current_song() {
        Ok(song) => song,
        Err(exc) => {
            eprintln!("mpd: {exc}");
            return EXIT_ERROR;
        }
    };
    let status = match client.status() {
        Ok(status) => status,
        Err(exc) => {
            eprintln!("mpd: {exc}");
            return EXIT_ERROR;
        }
    };
    if json {
        println!("{}", status_json(&status, &song));
        return EXIT_OK;
    }
    let state = status.get("state").unwrap_or("stop");
    if state == "stop" || song.get("file").is_none() {
        println!("stopped");
        return EXIT_OK;
    }
    println!("{state}: {}", song::describe(&song));
    EXIT_OK
}

fn cmd_ping(cfg: &Config) -> u8 {
    let mut client = client(cfg, Duration::from_secs(5));
    match client.connect() {
        Ok(()) => {
            println!(
                "mpd       ok    {}:{} (MPD {})",
                cfg.mpd_host,
                cfg.mpd_port,
                client.version.clone().unwrap_or_default()
            );
            EXIT_OK
        }
        Err(exc) => {
            println!("mpd       FAIL  {exc}");
            EXIT_ERROR
        }
    }
}

fn cmd_doctor(cfg: &Config, sources: &[PathBuf]) -> u8 {
    let mut healthy = true;
    let mut client = client(cfg, Duration::from_secs(3));
    match (client.status(), client.current_song()) {
        (Ok(status), Ok(song)) => {
            println!(
                "mpd       ok    {}:{} (MPD {}), state={}, queue={}",
                cfg.mpd_host,
                cfg.mpd_port,
                client.version.clone().unwrap_or_default(),
                status.get("state").unwrap_or("?"),
                status.get("playlistlength").unwrap_or("?")
            );
            if song.get("file").is_some() {
                println!("          now   {}", song::describe(&song));
            }
        }
        (Err(exc), _) | (_, Err(exc)) => {
            healthy = false;
            println!("mpd       FAIL  {exc}");
        }
    }
    println!("capture   n/a   not ported yet (python backend still in use)");
    println!("stt       n/a   not ported yet");
    println!("tts       n/a   not ported yet");
    if sources.is_empty() {
        println!("config    warn  no config file found, using defaults");
    } else {
        for source in sources {
            println!("config    ok    {}", source.display());
        }
    }
    if healthy {
        EXIT_OK
    } else {
        EXIT_ERROR
    }
}

fn cmd_parse(words: &[String]) -> u8 {
    let intent = intents::parse(&words.join(" "));
    let number = match intent.number {
        Some(number) => number.to_string(),
        None => "null".to_string(),
    };
    println!(
        "{{\n  \"name\": {},\n  \"value\": {},\n  \"tag\": {},\n  \"number\": {},\n  \"lang\": {},\n  \"raw\": {}\n}}",
        json_string(&intent.name),
        json_string(&intent.value),
        json_string(&intent.tag),
        number,
        json_string(&intent.lang),
        json_string(&intent.raw)
    );
    if intent.understood() {
        EXIT_OK
    } else {
        EXIT_UNKNOWN
    }
}

fn cmd_phrases() -> u8 {
    for (name, examples) in intents::EXAMPLES {
        println!("{name:16} {}", examples.join(" | "));
    }
    EXIT_OK
}

fn cmd_rex(pattern: &str, text: &str) -> u8 {
    let Some(regex) = rex::Regex::new(pattern) else {
        println!("{{\"error\": \"bad pattern\"}}");
        return EXIT_UNKNOWN;
    };
    if text == "-" {
        println!("{regex:?}");
        return EXIT_OK;
    }
    match regex.search(text) {
        Some(m) => {
            let caps: Vec<String> = m
                .captures
                .iter()
                .map(|(key, value)| format!("{}: {}", json_string(key), json_string(value)))
                .collect();
            println!(
                "{{\"start\": {}, \"end\": {}, \"caps\": {{{}}}}}",
                m.start,
                m.end,
                caps.join(", ")
            );
            EXIT_OK
        }
        None => {
            println!("{{\"start\": null}}");
            EXIT_OK
        }
    }
}

/// `json.dumps({"status": status, "song": song}, ensure_ascii=False, indent=2)`
fn status_json(status: &Meta, song: &Meta) -> String {
    let mut out = String::from("{\n  \"status\": ");
    out.push_str(&json_meta(status, 2));
    out.push_str(",\n  \"song\": ");
    out.push_str(&json_meta(song, 2));
    out.push_str("\n}");
    out
}

fn json_meta(meta: &Meta, indent: usize) -> String {
    if meta.is_empty() {
        return "{}".to_string();
    }
    let pad = " ".repeat(indent + 2);
    let close = " ".repeat(indent);
    let body: Vec<String> = meta
        .0
        .iter()
        .map(|(key, value)| format!("{pad}{}: {}", json_string(key), json_string(value)))
        .collect();
    format!("{{\n{}\n{close}}}", body.join(",\n"))
}

fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for ch in value.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            ch if (ch as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => out.push(ch),
        }
    }
    out.push('"');
    out
}

#[allow(dead_code)]
fn unused(_: MpdError) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_shape_matches_the_python_dump() {
        let status = Meta(vec![
            ("volume".to_string(), "50".to_string()),
            ("state".to_string(), "play".to_string()),
        ]);
        let song = Meta(vec![("file".to_string(), "a b.flac".to_string())]);
        assert_eq!(
            status_json(&status, &song),
            "{\n  \"status\": {\n    \"volume\": \"50\",\n    \"state\": \"play\"\n  },\n  \"song\": {\n    \"file\": \"a b.flac\"\n  }\n}"
        );
    }

    #[test]
    fn json_escapes_quotes_and_keeps_unicode() {
        assert_eq!(json_string("a\"b"), "\"a\\\"b\"");
        assert_eq!(json_string("Зиновия"), "\"Зиновия\"");
    }

    #[test]
    fn empty_maps_render_as_braces() {
        assert_eq!(json_meta(&Meta::new(), 2), "{}");
    }
}
