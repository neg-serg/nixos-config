//! Effective configuration: files, environment, then command line flags.
//!
//! Port of `mpd_voice/config.py`. Config files are read from
//! `$XDG_CONFIG_DIRS/mpd-voice/config.toml` and
//! `$XDG_CONFIG_HOME/mpd-voice/config.toml` (the user file wins); the installer
//! writes the system file, so per-user tweaks stay possible without rebuilding.

use std::path::{Path, PathBuf};

use crate::toml::{self, Value};

pub const APP: &str = "mpd-voice";

#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub mpd_host: String,
    pub mpd_port: i64,
    pub mpd_password: String,

    pub language: String,
    pub wake_word: String,
    pub confirm: bool,
    pub volume_step: i64,
    pub max_seconds: f64,
    pub silence_seconds: f64,

    pub capture: String,
    pub capture_cmd: String,
    pub device: String,

    pub stt: String,
    pub stt_url: String,
    pub stt_bin: String,
    pub stt_model: String,
    pub stt_cmd: String,

    pub tts: String,
    pub tts_url: String,
    pub tts_voice: String,
    pub tts_cmd: String,

    pub similar_cmd: String,
    pub music_dir: String,

    pub describe_cmd: String,
    pub describe_timeout: f64,

    pub tags_file: String,
    pub tags_min_score: f64,
    pub tags_min_seconds: f64,
    pub tags_exclude: String,
    pub tags_limit: i64,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            mpd_host: "127.0.0.1".to_string(),
            mpd_port: 6600,
            mpd_password: String::new(),

            language: "ru".to_string(),
            wake_word: String::new(),
            confirm: true,
            volume_step: 5,
            max_seconds: 8.0,
            silence_seconds: 0.8,

            capture: "auto".to_string(),
            capture_cmd: String::new(),
            device: String::new(),

            stt: "auto".to_string(),
            stt_url: "http://127.0.0.1:8002".to_string(),
            stt_bin: "whisper-cli".to_string(),
            stt_model: String::new(),
            stt_cmd: String::new(),

            tts: "auto".to_string(),
            tts_url: "http://127.0.0.1:8001".to_string(),
            tts_voice: "default".to_string(),
            tts_cmd: String::new(),

            similar_cmd: "music-similar --json -k 10".to_string(),
            music_dir: "~/music".to_string(),

            describe_cmd:
                "music-describe --json --cache ~/.cache/music-describe/descriptions.jsonl"
                    .to_string(),
            describe_timeout: 900.0,

            tags_file: "~/.cache/music-mtg/tags.jsonl".to_string(),
            tags_min_score: 0.10,
            tags_min_seconds: 45.0,
            tags_exclude: "samples/*".to_string(),
            tags_limit: 25,
        }
    }
}

impl Config {
    /// Overlay a parsed table; unknown keys and wrong shapes are ignored.
    pub fn apply_mapping(&mut self, values: &[(String, Value)]) {
        for (key, value) in values {
            match key.as_str() {
                "mpd_host" => self.mpd_host = coerce_str(&self.mpd_host, value),
                "mpd_port" => self.mpd_port = coerce_int(self.mpd_port, value),
                "mpd_password" => self.mpd_password = coerce_str(&self.mpd_password, value),
                "language" => self.language = coerce_str(&self.language, value),
                "wake_word" => self.wake_word = coerce_str(&self.wake_word, value),
                "confirm" => self.confirm = coerce_bool(self.confirm, value),
                "volume_step" => self.volume_step = coerce_int(self.volume_step, value),
                "max_seconds" => self.max_seconds = coerce_float(self.max_seconds, value),
                "silence_seconds" => {
                    self.silence_seconds = coerce_float(self.silence_seconds, value);
                }
                "capture" => self.capture = coerce_str(&self.capture, value),
                "capture_cmd" => self.capture_cmd = coerce_str(&self.capture_cmd, value),
                "device" => self.device = coerce_str(&self.device, value),
                "stt" => self.stt = coerce_str(&self.stt, value),
                "stt_url" => self.stt_url = coerce_str(&self.stt_url, value),
                "stt_bin" => self.stt_bin = coerce_str(&self.stt_bin, value),
                "stt_model" => self.stt_model = coerce_str(&self.stt_model, value),
                "stt_cmd" => self.stt_cmd = coerce_str(&self.stt_cmd, value),
                "tts" => self.tts = coerce_str(&self.tts, value),
                "tts_url" => self.tts_url = coerce_str(&self.tts_url, value),
                "tts_voice" => self.tts_voice = coerce_str(&self.tts_voice, value),
                "tts_cmd" => self.tts_cmd = coerce_str(&self.tts_cmd, value),
                "similar_cmd" => self.similar_cmd = coerce_str(&self.similar_cmd, value),
                "music_dir" => self.music_dir = coerce_str(&self.music_dir, value),
                "describe_cmd" => self.describe_cmd = coerce_str(&self.describe_cmd, value),
                "describe_timeout" => {
                    self.describe_timeout = coerce_float(self.describe_timeout, value);
                }
                "tags_file" => self.tags_file = coerce_str(&self.tags_file, value),
                "tags_min_score" => self.tags_min_score = coerce_float(self.tags_min_score, value),
                "tags_min_seconds" => {
                    self.tags_min_seconds = coerce_float(self.tags_min_seconds, value);
                }
                "tags_exclude" => self.tags_exclude = coerce_str(&self.tags_exclude, value),
                "tags_limit" => self.tags_limit = coerce_int(self.tags_limit, value),
                _ => {}
            }
        }
    }

    /// Every field as `key = value`, for `mpd-voice config`.
    pub fn as_toml(&self) -> String {
        let mut lines = vec!["[mpd-voice]".to_string()];
        push_str(&mut lines, "mpd_host", &self.mpd_host);
        push_num(&mut lines, "mpd_port", self.mpd_port);
        push_str(&mut lines, "mpd_password", &self.mpd_password);
        push_str(&mut lines, "language", &self.language);
        push_str(&mut lines, "wake_word", &self.wake_word);
        push_bool(&mut lines, "confirm", self.confirm);
        push_num(&mut lines, "volume_step", self.volume_step);
        push_float(&mut lines, "max_seconds", self.max_seconds);
        push_float(&mut lines, "silence_seconds", self.silence_seconds);
        push_str(&mut lines, "capture", &self.capture);
        push_str(&mut lines, "capture_cmd", &self.capture_cmd);
        push_str(&mut lines, "device", &self.device);
        push_str(&mut lines, "stt", &self.stt);
        push_str(&mut lines, "stt_url", &self.stt_url);
        push_str(&mut lines, "stt_bin", &self.stt_bin);
        push_str(&mut lines, "stt_model", &self.stt_model);
        push_str(&mut lines, "stt_cmd", &self.stt_cmd);
        push_str(&mut lines, "tts", &self.tts);
        push_str(&mut lines, "tts_url", &self.tts_url);
        push_str(&mut lines, "tts_voice", &self.tts_voice);
        push_str(&mut lines, "tts_cmd", &self.tts_cmd);
        push_str(&mut lines, "similar_cmd", &self.similar_cmd);
        push_str(&mut lines, "music_dir", &self.music_dir);
        push_str(&mut lines, "describe_cmd", &self.describe_cmd);
        push_float(&mut lines, "describe_timeout", self.describe_timeout);
        push_str(&mut lines, "tags_file", &self.tags_file);
        push_float(&mut lines, "tags_min_score", self.tags_min_score);
        push_float(&mut lines, "tags_min_seconds", self.tags_min_seconds);
        push_str(&mut lines, "tags_exclude", &self.tags_exclude);
        push_num(&mut lines, "tags_limit", self.tags_limit);
        lines.join("\n")
    }
}

fn push_str(lines: &mut Vec<String>, key: &str, value: &str) {
    lines.push(format!("{key} = \"{}\"", escape(value)));
}

fn push_num(lines: &mut Vec<String>, key: &str, value: i64) {
    lines.push(format!("{key} = {value}"));
}

fn push_float(lines: &mut Vec<String>, key: &str, value: f64) {
    lines.push(format!("{key} = {value}"));
}

fn push_bool(lines: &mut Vec<String>, key: &str, value: bool) {
    lines.push(format!("{key} = {value}"));
}

fn escape(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn coerce_bool(_current: bool, value: &Value) -> bool {
    // Python truthiness: an empty string is false, any other string is true
    // (`bool("false") is True`), so there is no failure path to fall back on.
    match value {
        Value::Bool(flag) => *flag,
        Value::Int(number) => *number != 0,
        Value::Float(number) => *number != 0.0,
        Value::Str(text) => !text.is_empty(),
    }
}

fn coerce_int(current: i64, value: &Value) -> i64 {
    match value {
        Value::Bool(flag) => {
            if *flag {
                1
            } else {
                0
            }
        }
        Value::Int(number) => *number,
        Value::Float(number) => *number as i64,
        Value::Str(text) => text.trim().parse::<i64>().unwrap_or(current),
    }
}

fn coerce_float(current: f64, value: &Value) -> f64 {
    match value {
        Value::Bool(flag) => {
            if *flag {
                1.0
            } else {
                0.0
            }
        }
        Value::Int(number) => *number as f64,
        Value::Float(number) => *number,
        Value::Str(text) => text.trim().parse::<f64>().unwrap_or(current),
    }
}

fn coerce_str(_current: &str, value: &Value) -> String {
    match value {
        Value::Str(text) => text.clone(),
        Value::Int(number) => number.to_string(),
        Value::Float(number) => py_float(*number),
        Value::Bool(flag) => {
            if *flag {
                "True".to_string()
            } else {
                "False".to_string()
            }
        }
    }
}

fn py_float(value: f64) -> String {
    if value.is_finite() && value.fract() == 0.0 && value.abs() < 1e16 {
        format!("{value:.1}")
    } else {
        format!("{value}")
    }
}

/// System directories first, user directory last (it wins).
pub fn config_paths() -> Vec<PathBuf> {
    let directories = std::env::var("XDG_CONFIG_DIRS")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "/etc/xdg".to_string());
    let home = std::env::var("XDG_CONFIG_HOME")
        .ok()
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"));
    let mut paths: Vec<PathBuf> = directories
        .split(':')
        .map(|directory| Path::new(directory).join(APP).join("config.toml"))
        .collect();
    paths.push(home.join(APP).join("config.toml"));
    paths
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

/// Return the effective config and the files that contributed to it.
pub fn load(path: Option<&Path>) -> (Config, Vec<PathBuf>) {
    let mut config = Config::default();
    let candidates = match path {
        Some(path) => vec![path.to_path_buf()],
        None => config_paths(),
    };
    let mut used = Vec::new();
    for candidate in candidates {
        let Ok(source) = std::fs::read_to_string(&candidate) else {
            continue;
        };
        let Some(document) = toml::parse(&source) else {
            continue;
        };
        let entries = document
            .table(Some(APP))
            .or_else(|| document.table(None))
            .unwrap_or(&[]);
        config.apply_mapping(entries);
        used.push(candidate);
    }
    config.apply_mapping(&environment());
    (config, used)
}

/// mpc-compatible MPD variables plus a couple of `MPD_VOICE_*` ones.
fn environment() -> Vec<(String, Value)> {
    let mut mapping: Vec<(String, Value)> = Vec::new();
    let take = |name: &str, key: &str, mapping: &mut Vec<(String, Value)>| {
        if let Ok(value) = std::env::var(name) {
            mapping.push((key.to_string(), Value::Str(value)));
        }
    };
    take("MPD_HOST", "mpd_host", &mut mapping);
    take("MPD_PORT", "mpd_port", &mut mapping);
    take("MPD_PASSWORD", "mpd_password", &mut mapping);
    take("MPD_VOICE_LANG", "language", &mut mapping);
    take("MPD_VOICE_STT", "stt", &mut mapping);
    take("MPD_VOICE_TTS", "tts", &mut mapping);
    take("MPD_VOICE_TAGS_FILE", "tags_file", &mut mapping);
    // Presence, not truthiness: an empty value means "no exclude patterns",
    // which differs from leaving the default in place.
    take("MPD_VOICE_TAGS_EXCLUDE", "tags_exclude", &mut mapping);
    mapping
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_the_python_dataclass() {
        let cfg = Config::default();
        assert_eq!(cfg.mpd_host, "127.0.0.1");
        assert_eq!(cfg.mpd_port, 6600);
        assert!(cfg.confirm);
        assert_eq!(cfg.volume_step, 5);
        assert_eq!(cfg.max_seconds, 8.0);
        assert_eq!(cfg.tags_min_score, 0.10);
        assert_eq!(cfg.tags_limit, 25);
        assert_eq!(cfg.tags_exclude, "samples/*");
    }

    #[test]
    fn mapping_overlays_known_keys_and_coerces() {
        let mut cfg = Config::default();
        cfg.apply_mapping(&[
            ("mpd_host".to_string(), Value::Str("box".into())),
            ("mpd_port".to_string(), Value::Str("6601".into())),
            ("confirm".to_string(), Value::Bool(false)),
            ("max_seconds".to_string(), Value::Int(3)),
            ("unknown".to_string(), Value::Str("x".into())),
        ]);
        assert_eq!(cfg.mpd_host, "box");
        assert_eq!(cfg.mpd_port, 6601);
        assert!(!cfg.confirm);
        assert_eq!(cfg.max_seconds, 3.0);
    }

    #[test]
    fn a_non_numeric_string_keeps_the_current_number() {
        let mut cfg = Config::default();
        cfg.apply_mapping(&[("mpd_port".to_string(), Value::Str("nope".into()))]);
        assert_eq!(cfg.mpd_port, 6600);
    }

    #[test]
    fn empty_string_is_falsy_for_booleans_like_python() {
        let mut cfg = Config::default();
        cfg.apply_mapping(&[("confirm".to_string(), Value::Str(String::new()))]);
        assert!(!cfg.confirm);
        let mut cfg = Config::default();
        cfg.apply_mapping(&[("confirm".to_string(), Value::Str("false".into()))]);
        assert!(cfg.confirm, "a non-empty string is truthy in Python");
    }

    #[test]
    fn numbers_become_strings_the_python_way() {
        let mut cfg = Config::default();
        cfg.apply_mapping(&[("wake_word".to_string(), Value::Float(2.0))]);
        assert_eq!(cfg.wake_word, "2.0");
        let mut cfg = Config::default();
        cfg.apply_mapping(&[("wake_word".to_string(), Value::Bool(true))]);
        assert_eq!(cfg.wake_word, "True");
    }

    #[test]
    fn as_toml_round_trips_through_the_parser() {
        let cfg = Config::default();
        let text = cfg.as_toml();
        let document = toml::parse(&text).expect("document");
        let mut other = Config::default();
        other.apply_mapping(document.table(Some(APP)).unwrap());
        assert_eq!(other, cfg);
    }
}
