//! Command line interface: `mpd-voice <command> [options]`.
//!
//! Port of `mpd_voice/cli.py`. Subcommands: `once`, `listen`, `say`, `status`,
//! `parse`, `phrases`, `doctor` — same flags, same output and the same exit
//! codes (0 ok, 1 runtime error, 3 nothing understood).

use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;

use crate::audio;
use crate::config::{self, Config};
use crate::http;
use crate::intents;
use crate::mpd::{Meta, MpdClient};
use crate::session::{Controller, Reply};
use crate::stt::{self, SpeechToText};
use crate::tts::{self, TextToSpeech};

pub const EXIT_OK: u8 = 0;
pub const EXIT_ERROR: u8 = 1;
pub const EXIT_UNKNOWN: u8 = 3;

const DOC: &str = "\
mpd-voice — voice control for MPD (local speech recognition).

Commands:
  once      listen for one utterance and act on it (push-to-talk)
  listen    keep listening; with --wake-word only act after the keyword
  say       run typed commands through the same pipeline (no audio)
  status    print what MPD is doing right now
  parse     show how a phrase is parsed (debugging, docs)
  phrases   list the supported phrases in both languages
  doctor    check MPD, capture, STT and TTS backends

Options: --config FILE, --host, --port, --password, --lang ru|en, --json,
--verbose, --wake-word, --no-confirm, --stt auto|http|cli|cmd|none, --stt-url,
--stt-bin, --stt-model, --stt-cmd, --tts auto|http|cmd|none, --tts-url,
--tts-voice, --tts-cmd, --capture auto|pw-record|arecord|ffmpeg|sox|cmd,
--capture-cmd, --device, --max-seconds, --silence-seconds, --input-wav,
--once, --dry-run, --speak.";

/// Everything the flags can override; `None` means "leave the config alone".
#[derive(Debug, Default, Clone)]
pub struct Options {
    pub config: Option<PathBuf>,
    pub mpd_host: Option<String>,
    pub mpd_port: Option<i64>,
    pub mpd_password: Option<String>,
    pub language: Option<String>,
    pub verbose: bool,
    pub json: bool,
    pub wake_word: Option<String>,
    pub confirm: Option<bool>,
    pub stt: Option<String>,
    pub stt_url: Option<String>,
    pub stt_bin: Option<String>,
    pub stt_model: Option<String>,
    pub stt_cmd: Option<String>,
    pub tts: Option<String>,
    pub tts_url: Option<String>,
    pub tts_voice: Option<String>,
    pub tts_cmd: Option<String>,
    pub capture: Option<String>,
    pub capture_cmd: Option<String>,
    pub device: Option<String>,
    pub max_seconds: Option<f64>,
    pub silence_seconds: Option<f64>,
    pub input_wav: Option<PathBuf>,
    pub once: bool,
    pub dry_run: bool,
    pub speak: bool,
    pub help: bool,
}

fn take_value(argv: &[String], index: &mut usize) -> Option<String> {
    let value = argv.get(*index + 1)?;
    *index += 2;
    Some(value.clone())
}

pub fn parse_args(argv: &[String]) -> (Vec<String>, Options) {
    let mut options = Options::default();
    let mut positional: Vec<String> = Vec::new();
    let mut index = 0;
    while index < argv.len() {
        let arg = argv[index].as_str();
        match arg {
            "-h" | "--help" => {
                options.help = true;
                index += 1;
            }
            "--version" => {
                options.help = true;
                index += 1;
            }
            "--verbose" | "-v" => {
                options.verbose = true;
                index += 1;
            }
            "--json" => {
                options.json = true;
                index += 1;
            }
            "--once" => {
                options.once = true;
                index += 1;
            }
            "--dry-run" => {
                options.dry_run = true;
                index += 1;
            }
            "--speak" => {
                options.speak = true;
                index += 1;
            }
            "--no-confirm" => {
                options.confirm = Some(false);
                index += 1;
            }
            "--config" => {
                if let Some(value) = take_value(argv, &mut index) {
                    options.config = Some(PathBuf::from(value));
                }
            }
            "--host" => options.mpd_host = take_value(argv, &mut index),
            "--port" => {
                if let Some(value) = take_value(argv, &mut index) {
                    options.mpd_port = value.trim().parse().ok();
                }
            }
            "--password" => options.mpd_password = take_value(argv, &mut index),
            "--lang" => options.language = take_value(argv, &mut index),
            "--wake-word" => options.wake_word = take_value(argv, &mut index),
            "--stt" => options.stt = take_value(argv, &mut index),
            "--stt-url" => options.stt_url = take_value(argv, &mut index),
            "--stt-bin" => options.stt_bin = take_value(argv, &mut index),
            "--stt-model" => options.stt_model = take_value(argv, &mut index),
            "--stt-cmd" => options.stt_cmd = take_value(argv, &mut index),
            "--tts" => options.tts = take_value(argv, &mut index),
            "--tts-url" => options.tts_url = take_value(argv, &mut index),
            "--tts-voice" => options.tts_voice = take_value(argv, &mut index),
            "--tts-cmd" => options.tts_cmd = take_value(argv, &mut index),
            "--capture" => options.capture = take_value(argv, &mut index),
            "--capture-cmd" => options.capture_cmd = take_value(argv, &mut index),
            "--device" => options.device = take_value(argv, &mut index),
            "--max-seconds" => {
                if let Some(value) = take_value(argv, &mut index) {
                    options.max_seconds = value.trim().parse().ok();
                }
            }
            "--silence-seconds" => {
                if let Some(value) = take_value(argv, &mut index) {
                    options.silence_seconds = value.trim().parse().ok();
                }
            }
            "--input-wav" => {
                options.input_wav = take_value(argv, &mut index).map(PathBuf::from);
            }
            other => {
                positional.push(other.to_string());
                index += 1;
            }
        }
    }
    (positional, options)
}

/// Apply the flags on top of the file/environment configuration.
pub fn apply_options(cfg: &mut Config, options: &Options) {
    if let Some(value) = &options.mpd_host {
        cfg.mpd_host = value.clone();
    }
    if let Some(value) = options.mpd_port {
        cfg.mpd_port = value;
    }
    if let Some(value) = &options.mpd_password {
        cfg.mpd_password = value.clone();
    }
    if let Some(value) = &options.language {
        cfg.language = value.clone();
    }
    if let Some(value) = &options.wake_word {
        cfg.wake_word = value.clone();
    }
    if let Some(value) = options.confirm {
        cfg.confirm = value;
    }
    if let Some(value) = &options.stt {
        cfg.stt = value.clone();
    }
    if let Some(value) = &options.stt_url {
        cfg.stt_url = value.clone();
    }
    if let Some(value) = &options.stt_bin {
        cfg.stt_bin = value.clone();
    }
    if let Some(value) = &options.stt_model {
        cfg.stt_model = value.clone();
    }
    if let Some(value) = &options.stt_cmd {
        cfg.stt_cmd = value.clone();
    }
    if let Some(value) = &options.tts {
        cfg.tts = value.clone();
    }
    if let Some(value) = &options.tts_url {
        cfg.tts_url = value.clone();
    }
    if let Some(value) = &options.tts_voice {
        cfg.tts_voice = value.clone();
    }
    if let Some(value) = &options.tts_cmd {
        cfg.tts_cmd = value.clone();
    }
    if let Some(value) = &options.capture {
        cfg.capture = value.clone();
    }
    if let Some(value) = &options.capture_cmd {
        cfg.capture_cmd = value.clone();
    }
    if let Some(value) = &options.device {
        cfg.device = value.clone();
    }
    if let Some(value) = options.max_seconds {
        cfg.max_seconds = value;
    }
    if let Some(value) = options.silence_seconds {
        cfg.silence_seconds = value;
    }
}

pub fn client(cfg: &Config, timeout: Duration) -> MpdClient {
    let password = if cfg.mpd_password.is_empty() {
        None
    } else {
        Some(cfg.mpd_password.clone())
    };
    MpdClient::new(&cfg.mpd_host, cfg.mpd_port as u16, password, timeout)
}

fn build_stt(cfg: &Config) -> Result<Box<dyn SpeechToText>, stt::SttError> {
    stt::build_stt(
        &cfg.stt,
        &cfg.stt_url,
        &cfg.stt_model,
        &cfg.stt_bin,
        &cfg.stt_cmd,
        &cfg.language,
        Duration::from_secs(300),
    )
}

fn build_tts(cfg: &Config) -> Result<Box<dyn TextToSpeech>, tts::TtsError> {
    tts::build_tts(
        &cfg.tts,
        &cfg.tts_url,
        &cfg.tts_voice,
        &cfg.tts_cmd,
        Duration::from_secs(60),
    )
}

fn describe_backend(name: &str, detail: &str) -> String {
    if detail.is_empty() {
        name.to_string()
    } else {
        format!("{name} {detail}")
    }
}

/// `mpd-voice <command>`: returns the process exit code.
pub fn run(argv: &[String]) -> u8 {
    let (positional, options) = parse_args(argv);
    let (mut cfg, sources) = config::load(options.config.as_deref());
    apply_options(&mut cfg, &options);
    let Some(command) = positional.first().cloned() else {
        if options.help {
            println!("{DOC}");
            return EXIT_OK;
        }
        println!("{DOC}");
        return EXIT_ERROR;
    };
    let tail = &positional[1..];
    match command.as_str() {
        "say" => cmd_say(&cfg, tail, &options),
        "status" => cmd_status(&cfg, options.json),
        "parse" => cmd_parse(tail),
        "phrases" => cmd_phrases(),
        "doctor" => cmd_doctor(&cfg, &sources),
        "listen" | "once" => cmd_listen(&cfg, &options),
        other => {
            eprintln!("unknown command: {other}");
            EXIT_ERROR
        }
    }
}

fn intent_json(intent: &intents::Intent, with_understood: bool) -> String {
    let number = match intent.number {
        Some(number) => number.to_string(),
        None => "null".to_string(),
    };
    let mut out = String::from("{\n");
    out.push_str(&format!(
        "  \"name\": \"{}\",\n",
        http::json_escape(&intent.name)
    ));
    out.push_str(&format!(
        "  \"value\": \"{}\",\n",
        http::json_escape(&intent.value)
    ));
    out.push_str(&format!(
        "  \"tag\": \"{}\",\n",
        http::json_escape(&intent.tag)
    ));
    out.push_str(&format!("  \"number\": {number},\n"));
    out.push_str(&format!(
        "  \"lang\": \"{}\",\n",
        http::json_escape(&intent.lang)
    ));
    out.push_str(&format!(
        "  \"raw\": \"{}\"",
        http::json_escape(&intent.raw)
    ));
    if with_understood {
        out.push_str(&format!(",\n  \"understood\": {}", intent.understood()));
    }
    out.push_str("\n}");
    out
}

fn cmd_say(cfg: &Config, words: &[String], options: &Options) -> u8 {
    let text = words.join(" ");
    if options.dry_run {
        let intent = intents::parse(&text);
        println!("{}", intent_json(&intent, true));
        return if intent.understood() {
            EXIT_OK
        } else {
            EXIT_UNKNOWN
        };
    }
    let mut controller = Controller::new(client(cfg, Duration::from_secs(5)), cfg.clone());
    let reply = controller.handle_text(&text);
    println!("{}", reply.text);
    if options.speak {
        match build_tts(cfg) {
            Ok(speaker) => {
                if let Err(exc) = speaker.speak(&reply.text) {
                    eprintln!("tts: {exc}");
                }
            }
            Err(exc) => eprintln!("tts: {exc}"),
        }
    }
    if reply.ok {
        EXIT_OK
    } else {
        EXIT_UNKNOWN
    }
}

fn cmd_parse(words: &[String]) -> u8 {
    let intent = intents::parse(&words.join(" "));
    println!("{}", intent_json(&intent, false));
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

fn status_json(status: &Meta, song: &Meta) -> String {
    let render = |meta: &Meta, indent: usize| -> String {
        if meta.is_empty() {
            return "{}".to_string();
        }
        let pad = " ".repeat(indent + 2);
        let close = " ".repeat(indent);
        let body: Vec<String> = meta
            .0
            .iter()
            .map(|(key, value)| {
                format!(
                    "{pad}\"{}\": \"{}\"",
                    http::json_escape(key),
                    http::json_escape(value)
                )
            })
            .collect();
        format!("{{\n{}\n{close}}}", body.join(",\n"))
    };
    format!(
        "{{\n  \"status\": {},\n  \"song\": {}\n}}",
        render(status, 2),
        render(song, 2)
    )
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
    println!("{state}: {}", crate::song::describe(&song));
    EXIT_OK
}

fn cmd_doctor(cfg: &Config, sources: &[PathBuf]) -> u8 {
    let mut healthy = true;
    let mut client = client(cfg, Duration::from_secs(3));
    let status = client.status();
    let song = client.current_song();
    match (status, song) {
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
                println!("          now   {}", crate::song::describe(&song));
            }
        }
        (Err(exc), _) | (_, Err(exc)) => {
            healthy = false;
            println!("mpd       FAIL  {exc}");
        }
    }
    match audio::detect_backend(&cfg.capture, &cfg.capture_cmd) {
        Ok(backend) => println!("capture   ok    {backend}"),
        Err(exc) => println!("capture   warn  {exc}"),
    }
    match build_stt(cfg) {
        Ok(backend) => {
            let detail = if cfg.stt == "http" || cfg.stt == "auto" {
                cfg.stt_url.clone()
            } else {
                cfg.stt_bin.clone()
            };
            println!(
                "stt       ok    {}",
                describe_backend(backend.name(), &detail)
            );
        }
        Err(exc) => println!("stt       warn  {exc}"),
    }
    match build_tts(cfg) {
        Ok(backend) => {
            let detail = if cfg.tts == "cmd" {
                cfg.tts_cmd.clone()
            } else {
                cfg.tts_url.clone()
            };
            println!(
                "tts       ok    {}",
                describe_backend(backend.name(), &detail)
            );
        }
        Err(exc) => println!("tts       warn  {exc}"),
    }
    if sources.is_empty() {
        println!("config    warn  no config.toml found (defaults in use)");
    } else {
        for source in sources {
            println!("config    ok    {}", source.display());
        }
    }
    println!("language  ok    {}", cfg.language);
    if healthy {
        EXIT_OK
    } else {
        EXIT_ERROR
    }
}

fn cmd_listen(cfg: &Config, options: &Options) -> u8 {
    let single = options.once || options.input_wav.is_some();
    let transcriber = match build_stt(cfg) {
        Ok(transcriber) => transcriber,
        Err(exc) => {
            eprintln!("stt: {exc}");
            return EXIT_ERROR;
        }
    };
    let speaker: Box<dyn TextToSpeech> = if cfg.confirm {
        match build_tts(cfg) {
            Ok(speaker) => speaker,
            Err(exc) => {
                eprintln!("tts: {exc}");
                Box::new(tts::NullTts)
            }
        }
    } else {
        Box::new(tts::NullTts)
    };
    let recorder = if options.input_wav.is_some() {
        None
    } else {
        match audio::Recorder::new(&cfg.capture, &cfg.device, audio::PCM_RATE, &cfg.capture_cmd) {
            Ok(recorder) => Some(recorder),
            Err(exc) => {
                eprintln!("capture: {exc}");
                return EXIT_ERROR;
            }
        }
    };
    let mut controller = Controller::new(client(cfg, Duration::from_secs(5)), cfg.clone());
    loop {
        let wav = match next_wav(cfg, options, recorder.as_ref(), options.verbose) {
            Ok(Some(wav)) => wav,
            Ok(None) => {
                if single {
                    return EXIT_OK;
                }
                continue;
            }
            Err(exc) => {
                eprintln!("capture: {exc}");
                return EXIT_ERROR;
            }
        };
        let transcript = transcriber.transcribe(&wav, Some(&cfg.language));
        if options.input_wav.is_none() {
            let _ = std::fs::remove_file(&wav);
        }
        let transcript = match transcript {
            Ok(text) => text,
            Err(exc) => {
                eprintln!("stt: {exc}");
                return EXIT_ERROR;
            }
        };
        let transcript = intents::strip_wake_word(&transcript, &cfg.wake_word);
        if transcript.is_empty() {
            if options.verbose {
                if cfg.wake_word.is_empty() {
                    println!("heard nothing");
                } else {
                    println!("no wake word ('{}')", cfg.wake_word);
                }
            }
            if single {
                return EXIT_UNKNOWN;
            }
            continue;
        }
        if options.verbose {
            println!("heard: {transcript}");
        }
        let reply: Reply = controller.handle_text(&transcript);
        println!("{}", reply.text);
        if let Err(exc) = speaker.speak(&reply.text) {
            eprintln!("tts: {exc}");
        }
        if reply.should_exit || single {
            return if reply.ok { EXIT_OK } else { EXIT_UNKNOWN };
        }
    }
}

fn next_wav(
    cfg: &Config,
    options: &Options,
    recorder: Option<&audio::Recorder>,
    verbose: bool,
) -> Result<Option<PathBuf>, audio::CaptureError> {
    if let Some(path) = &options.input_wav {
        return Ok(Some(path.clone()));
    }
    let Some(recorder) = recorder else {
        return Ok(None);
    };
    let pcm = recorder.capture(cfg.max_seconds, cfg.silence_seconds, true)?;
    if pcm.is_empty() {
        if verbose {
            println!("capture: no speech detected");
        }
        return Ok(None);
    }
    let path = std::env::temp_dir().join(format!(
        "mpd-voice-{}-{}.wav",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|delta| delta.as_nanos())
            .unwrap_or(0)
    ));
    audio::write_wav(&path, &pcm, recorder.rate, audio::PCM_CHANNELS)
        .map_err(|exc| audio::CaptureError(format!("cannot write {}: {exc}", path.display())))?;
    Ok(Some(path))
}

/// Read a WAV from stdin (used by the hidden `audio-sim` helper's tests).
pub fn read_stdin_wav() -> std::io::Result<Vec<u8>> {
    let mut buffer = Vec::new();
    std::io::stdin().read_to_end(&mut buffer)?;
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_override_the_config() {
        let argv: Vec<String> = ["say", "--port", "7000", "--lang", "en", "next track"]
            .iter()
            .map(|part| part.to_string())
            .collect();
        let (positional, options) = parse_args(&argv);
        assert_eq!(positional[0], "say");
        assert_eq!(positional[1], "next track");
        let mut cfg = Config::default();
        apply_options(&mut cfg, &options);
        assert_eq!(cfg.mpd_port, 7000);
        assert_eq!(cfg.language, "en");
    }

    #[test]
    fn dry_run_json_has_the_dataclass_fields() {
        let intent = intents::parse("пауза");
        let json = intent_json(&intent, false);
        assert!(json.starts_with("{\n  \"name\": \"pause\""));
        assert!(json.contains("\"number\": null"));
        assert!(!json.contains("understood"));
        let json = intent_json(&intent, true);
        assert!(json.contains("\"understood\": true"));
    }

    #[test]
    fn status_json_shape_matches_python() {
        let status = Meta(vec![("state".to_string(), "play".to_string())]);
        let song = Meta(vec![("file".to_string(), "a.flac".to_string())]);
        assert_eq!(
            status_json(&status, &song),
            "{\n  \"status\": {\n    \"state\": \"play\"\n  },\n  \"song\": {\n    \"file\": \"a.flac\"\n  }\n}"
        );
    }
}
