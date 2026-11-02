//! mpd-voice (Rust): voice control for MPD.
//!
//! Stage 1 of the port: the MPD client, the config loader and the read-only
//! commands (`status`, `doctor`, `ping`) are Rust; capture, STT/TTS and the
//! intent parser still come from the Python tree, which keeps building until
//! the port reaches parity. The crate is exposed as `nix build .#mpd-voice-rs`
//! for exactly that reason — it is not the installed `mpd-voice` yet.

mod audio;
mod cli;
mod config;
mod http;
mod intents;
mod json;
mod mpd;
mod rex;
mod session;
mod song;
mod stt;
mod testing;
mod toml;
mod tts;

use std::io::Write;
use std::process::ExitCode;

use cli::{EXIT_ERROR, EXIT_OK};

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let command = argv.first().map(String::as_str);
    let code = match command {
        // Hidden helpers for the parity harness; not part of the CLI surface.
        Some("rex") if argv.len() >= 3 => cmd_rex(&argv[1], &argv[2]),
        Some("audio-sim") => cmd_audio_sim(argv.get(1).map(String::as_str).unwrap_or("0.8")),
        Some("stt-sim") if argv.len() >= 3 => {
            cmd_stt_sim(&argv[1], &argv[2], argv.get(3).map(String::as_str))
        }
        Some("tts-sim") if argv.len() >= 3 => cmd_tts_sim(&argv[1], &argv[2]),
        _ => cli::run(&argv),
    };
    let _ = std::io::stdout().flush();
    ExitCode::from(code)
}

/// Transcribe one WAV file through the HTTP backend and print the transcript.
fn cmd_stt_sim(base_url: &str, wav: &str, language: Option<&str>) -> u8 {
    use stt::SpeechToText;
    let backend = stt::HttpStt::new(base_url, "", "ru", std::time::Duration::from_secs(10));
    match backend.transcribe(std::path::Path::new(wav), language) {
        Ok(text) => {
            println!("{{\"text\": {}}}", json_string(&text));
            EXIT_OK
        }
        Err(exc) => {
            println!("{{\"error\": {}}}", json_string(&exc.0));
            EXIT_ERROR
        }
    }
}

/// Synthesize one phrase through the HTTP backend; print the audio size (no playback).
fn cmd_tts_sim(base_url: &str, text: &str) -> u8 {
    let backend = tts::HttpTts::new(base_url, "default", std::time::Duration::from_secs(10));
    match backend.synthesize(text) {
        Ok(audio) => {
            println!(
                "{{\"bytes\": {}, \"wav\": {}}}",
                audio.len(),
                tts::is_wav(&audio)
            );
            EXIT_OK
        }
        Err(exc) => {
            println!("{{\"error\": {}}}", json_string(&exc.0));
            EXIT_ERROR
        }
    }
}

/// Feed raw s16le mono PCM from stdin through the gate and report the result:
/// the event sequence, the utterance length and a checksum both sides can
/// compute (the sum of the bytes, mod 2^32).
fn cmd_audio_sim(silence: &str) -> u8 {
    use std::io::Read;
    let silence_seconds: f64 = silence.trim().parse().unwrap_or(0.8);
    let mut pcm = Vec::new();
    if std::io::stdin().read_to_end(&mut pcm).is_err() {
        eprintln!("cannot read stdin");
        return EXIT_ERROR;
    }
    let mut gate = audio::SpeechGate::new(audio::PCM_RATE, audio::FRAME_MS, silence_seconds);
    let mut events: Vec<&str> = Vec::new();
    for frame in pcm.chunks(gate.frame_bytes) {
        events.push(gate.push(frame).as_str());
    }
    let checksum: u32 = gate
        .utterance
        .iter()
        .fold(0u32, |acc, byte| acc.wrapping_add(u32::from(*byte)));
    println!(
        "{{\"frames\": {}, \"events\": \"{}\", \"utterance\": {}, \"checksum\": {}, \"speech\": {}, \"seconds\": {:.6}}}",
        pcm.chunks(gate.frame_bytes).count(),
        events.join(","),
        gate.utterance.len(),
        checksum,
        gate.has_speech(),
        gate.speech_seconds()
    );
    EXIT_OK
}

fn cmd_rex(pattern: &str, text: &str) -> u8 {
    let Some(regex) = rex::Regex::new(pattern) else {
        println!("{{\"error\": \"bad pattern\"}}");
        return 3;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_escapes_quotes_and_keeps_unicode() {
        assert_eq!(json_string("a\"b"), "\"a\\\"b\"");
        assert_eq!(json_string("Зиновия"), "\"Зиновия\"");
    }
}
