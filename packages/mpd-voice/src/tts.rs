//! Text-to-speech backends for spoken confirmations.
//!
//! Port of `mpd_voice/tts.py`: `http` posts to any OpenAI-compatible
//! `/v1/audio/speech` endpoint (the repo's `piper-server.py` on :8001) and pipes
//! the returned WAV into the default sink, `cmd` runs a local command such as
//! `espeak-ng`, and `none` keeps the client silent — replies are still printed.

use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::http;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TtsError(pub String);

impl std::fmt::Display for TtsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for TtsError {}

fn fail<T>(message: impl Into<String>) -> Result<T, TtsError> {
    Err(TtsError(message.into()))
}

const CANDIDATES: [&str; 5] = ["spd-say", "espeak-ng", "espeak", "say", "festival"];
const PLAYERS: [&str; 4] = ["pw-play", "paplay", "aplay", "ffplay"];

/// Command that plays a WAV file from stdin (`-` means stdin).
pub fn detect_player() -> Result<Vec<String>, TtsError> {
    for player in PLAYERS {
        let Some(path) = crate::audio::which(player) else {
            continue;
        };
        let path = path.display().to_string();
        return Ok(match player {
            "ffplay" => vec![
                path,
                "-hide_banner".to_string(),
                "-loglevel".to_string(),
                "error".to_string(),
                "-nodisp".to_string(),
                "-autoexit".to_string(),
                "-".to_string(),
            ],
            "pw-play" => vec![path, "--volume=1.0".to_string(), "-".to_string()],
            _ => vec![path, "-q".to_string(), "-".to_string()],
        });
    }
    fail("no audio player found for HTTP speech output (install pipewire, pulseaudio-utils, alsa-utils or ffmpeg)")
}

/// Pipe a WAV buffer into a player.
pub fn play_bytes(data: &[u8], player: Option<&[String]>) -> Result<(), TtsError> {
    let argv = match player {
        Some(argv) => argv.to_vec(),
        None => detect_player()?,
    };
    let mut child = Command::new(&argv[0])
        .args(&argv[1..])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|exc| TtsError(format!("cannot play audio with {}: {exc}", argv[0])))?;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(data);
    }
    let status = child
        .wait()
        .map_err(|exc| TtsError(format!("cannot play audio with {}: {exc}", argv[0])))?;
    if !status.success() {
        return fail(format!(
            "{} exited with {}",
            argv[0],
            status.code().unwrap_or(-1)
        ));
    }
    Ok(())
}

/// A backend that turns text into sound.
pub trait TextToSpeech {
    fn name(&self) -> &'static str;
    fn available(&self) -> bool;
    fn speak(&self, text: &str) -> Result<(), TtsError>;
}

/// OpenAI-compatible speech endpoint, played on the local sink.
pub struct HttpTts {
    pub base_url: String,
    pub voice: String,
    pub model: String,
    pub timeout: Duration,
    pub player: Option<Vec<String>>,
}

impl HttpTts {
    pub fn new(base_url: &str, voice: &str, timeout: Duration) -> Self {
        HttpTts {
            base_url: base_url.trim_end_matches('/').to_string(),
            voice: voice.to_string(),
            model: "piper".to_string(),
            timeout,
            player: None,
        }
    }

    pub fn endpoint(&self) -> String {
        format!("{}/v1/audio/speech", self.base_url)
    }

    pub fn models_endpoint(&self) -> String {
        format!("{}/v1/models", self.base_url)
    }

    /// POST the text and return the synthesized WAV (no playback).
    pub fn synthesize(&self, text: &str) -> Result<Vec<u8>, TtsError> {
        let payload = format!(
            "{{\"model\": \"{}\", \"input\": \"{}\", \"voice\": \"{}\", \"response_format\": \"wav\"}}",
            http::json_escape(&self.model),
            http::json_escape(text),
            http::json_escape(&self.voice)
        );
        let response = match http::post(
            &self.endpoint(),
            "application/json",
            payload.as_bytes(),
            self.timeout,
        ) {
            Ok(response) => response,
            Err(exc) => return fail(format!("speech endpoint unreachable: {exc}")),
        };
        if response.status != 200 {
            let detail =
                String::from_utf8_lossy(&response.body[..response.body.len().min(200)]).to_string();
            if detail.is_empty() {
                return fail(format!("speech synthesis failed ({})", response.status));
            }
            return fail(format!(
                "speech synthesis failed ({}): {detail}",
                response.status
            ));
        }
        if response.body.is_empty() {
            return fail("speech endpoint returned empty audio");
        }
        Ok(response.body)
    }
}

impl TextToSpeech for HttpTts {
    fn name(&self) -> &'static str {
        "http"
    }

    fn available(&self) -> bool {
        matches!(http::get(&self.models_endpoint(), Duration::from_millis(1500)),
                 Ok(response) if response.status < 400)
    }

    fn speak(&self, text: &str) -> Result<(), TtsError> {
        if text.trim().is_empty() {
            return Ok(());
        }
        let audio = self.synthesize(text)?;
        play_bytes(&audio, self.player.as_deref())
    }
}

/// Speak by running a local command; `{text}` becomes one argv element.
pub struct CmdTts {
    pub command: String,
    pub timeout: Duration,
}

/// Placeholder that survives shlex parsing, so a phrase with spaces (or
/// quotes) is still passed as exactly one argument.
const TEXT_TOKEN: &str = "\u{0}mpd-voice-text\u{0}";

impl CmdTts {
    pub fn new(command: &str, timeout: Duration) -> Result<Self, TtsError> {
        if command.is_empty() {
            return fail("the 'cmd' backend needs --tts-cmd");
        }
        Ok(CmdTts {
            command: command.to_string(),
            timeout,
        })
    }

    pub fn argv(&self, text: &str) -> Result<Vec<String>, TtsError> {
        if !self.command.contains("{text}") {
            return fail("the --tts-cmd template must contain {text}");
        }
        let template = self.command.replace("{text}", TEXT_TOKEN);
        Ok(crate::audio::shlex_split(&template)
            .into_iter()
            .map(|argument| argument.replace(TEXT_TOKEN, text))
            .collect())
    }
}

impl TextToSpeech for CmdTts {
    fn name(&self) -> &'static str {
        "cmd"
    }

    fn available(&self) -> bool {
        match self.argv("probe") {
            Ok(argv) => !argv.is_empty() && crate::audio::which(&argv[0]).is_some(),
            Err(_) => false,
        }
    }

    fn speak(&self, text: &str) -> Result<(), TtsError> {
        if text.trim().is_empty() {
            return Ok(());
        }
        let argv = self.argv(text)?;
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|exc| TtsError(format!("cannot run {}: {exc}", argv[0])))?;
        let deadline = Instant::now() + self.timeout;
        loop {
            match child.try_wait() {
                Ok(Some(status)) => {
                    let output = child
                        .wait_with_output()
                        .map_err(|exc| TtsError(format!("cannot read {}: {exc}", argv[0])))?;
                    if !status.success() {
                        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
                        let tail = stderr
                            .lines()
                            .rev()
                            .map(str::trim)
                            .find(|line| !line.is_empty())
                            .unwrap_or("");
                        return fail(format!("TTS command failed: {tail}"));
                    }
                    return Ok(());
                }
                Ok(None) if Instant::now() >= deadline => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return fail(format!("{} timed out", argv[0]));
                }
                Ok(None) => std::thread::sleep(Duration::from_millis(20)),
                Err(exc) => return fail(format!("cannot run {}: {exc}", argv[0])),
            }
        }
    }
}

/// Stay silent.
pub struct NullTts;

impl TextToSpeech for NullTts {
    fn name(&self) -> &'static str {
        "none"
    }

    fn available(&self) -> bool {
        false
    }

    fn speak(&self, _text: &str) -> Result<(), TtsError> {
        Ok(())
    }
}

/// Sensible argv template for the detected local speech tool.
pub fn default_command(binary: &str) -> String {
    match binary {
        "spd-say" => "spd-say -w -e {text}".to_string(),
        "espeak-ng" | "espeak" => format!("{binary} -s 165 -v ru {{text}}"),
        "say" => "say {text}".to_string(),
        _ => "festival --tts {text}".to_string(),
    }
}

/// First available local tool, else the null backend.
pub fn detect_tts() -> Box<dyn TextToSpeech> {
    for binary in CANDIDATES {
        if crate::audio::which(binary).is_some() {
            if let Ok(backend) = CmdTts::new(&default_command(binary), Duration::from_secs(60)) {
                return Box::new(backend);
            }
        }
    }
    Box::new(NullTts)
}

/// Construct the requested backend; `auto` prefers HTTP, then a local tool.
pub fn build_tts(
    kind: &str,
    base_url: &str,
    voice: &str,
    command: &str,
    timeout: Duration,
) -> Result<Box<dyn TextToSpeech>, TtsError> {
    match kind {
        "none" => Ok(Box::new(NullTts)),
        "cmd" => Ok(Box::new(CmdTts::new(command, timeout)?)),
        "http" => Ok(Box::new(HttpTts::new(base_url, voice, timeout))),
        _ => {
            let http_backend = HttpTts::new(base_url, voice, timeout);
            if http_backend.available() {
                return Ok(Box::new(http_backend));
            }
            Ok(detect_tts())
        }
    }
}

/// True when the path looks like a WAV file (used by the CLI's reply pipe).
pub fn is_wav(data: &[u8]) -> bool {
    data.len() > 12 && &data[..4] == b"RIFF" && &data[8..12] == b"WAVE"
}

/// Read a WAV file for callers that want the bytes before playing them.
pub fn read_audio(path: &Path) -> Result<Vec<u8>, TtsError> {
    std::fs::read(path).map_err(|exc| TtsError(format!("cannot read {}: {exc}", path.display())))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_templates_match_python() {
        assert_eq!(default_command("spd-say"), "spd-say -w -e {text}");
        assert_eq!(
            default_command("espeak-ng"),
            "espeak-ng -s 165 -v ru {text}"
        );
        assert_eq!(default_command("say"), "say {text}");
        assert_eq!(default_command("festival"), "festival --tts {text}");
    }

    #[test]
    fn cmd_template_keeps_the_phrase_in_one_argument() {
        let backend = CmdTts::new("spd-say -w -e {text}", Duration::from_secs(5)).unwrap();
        assert_eq!(
            backend.argv("next track").unwrap(),
            vec!["spd-say", "-w", "-e", "next track"]
        );
        assert!(CmdTts::new("spd-say -w", Duration::from_secs(5))
            .unwrap()
            .argv("x")
            .is_err());
        assert!(CmdTts::new("", Duration::from_secs(5)).is_err());
    }

    #[test]
    fn null_backend_stays_silent() {
        let backend = NullTts;
        assert!(!backend.available());
        assert!(backend.speak("hello").is_ok());
    }

    #[test]
    fn empty_text_is_not_spoken() {
        let backend = CmdTts::new("tool {text}", Duration::from_secs(5)).unwrap();
        assert!(backend.speak("   ").is_ok());
    }

    #[test]
    fn wav_detection() {
        let mut wav = b"RIFF".to_vec();
        wav.extend_from_slice(&[0, 0, 0, 0]);
        wav.extend_from_slice(b"WAVEfmt ");
        assert!(is_wav(&wav));
        assert!(!is_wav(b"not audio"));
    }
}
