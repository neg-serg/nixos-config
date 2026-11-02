//! Speech-to-text backends.
//!
//! Port of `mpd_voice/stt.py`. Three escape hatches keep the client usable on a
//! host where the local speech stack is switched off by policy:
//!
//! - `http` — any OpenAI-compatible `/v1/audio/transcriptions` endpoint (the
//!   repo's `whisper-server.py` on :8002 when it is enabled);
//! - `cli` — `whisper-cli` from whisper.cpp directly (no server needed);
//! - `cmd` — an arbitrary command template, for anything else.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::http;
use crate::rex::Regex;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SttError(pub String);

impl std::fmt::Display for SttError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for SttError {}

fn fail<T>(message: impl Into<String>) -> Result<T, SttError> {
    Err(SttError(message.into()))
}

/// Lines whisper.cpp prints that are log noise, not transcript.
const WHISPER_NOISE: [&str; 8] = [
    "whisper_",
    "ggml_",
    "main:",
    "system_info",
    "load time",
    "whisper_print",
    "error:",
    "warning:",
];

/// Drop whisper.cpp log noise and collapse whitespace.
///
/// Timestamped segments (`[00:00.000 --> 00:02.000] text`) keep their text:
/// only the bracketed prefix is removed, so the output stays usable even when
/// the backend was invoked without `-nt`.
pub fn clean_transcript(text: &str) -> String {
    let timestamp = Regex::new(r"^\s*\[[^\]]*\]\s*");
    let mut lines: Vec<String> = Vec::new();
    for line in text.split('\n') {
        let stripped = match &timestamp {
            Some(regex) => regex.replace_all(line, ""),
            None => line.to_string(),
        };
        let stripped = stripped.trim();
        if stripped.is_empty() {
            continue;
        }
        let lowered = stripped.to_lowercase();
        if WHISPER_NOISE.iter().any(|token| lowered.starts_with(token)) {
            continue;
        }
        lines.push(stripped.to_string());
    }
    lines
        .join(" ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// Build a multipart/form-data body without third-party libraries.
pub fn multipart(
    fields: &[(&str, &str)],
    file_field: &str,
    filename: &str,
    data: &[u8],
    content_type: &str,
    boundary: &str,
) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();
    for (key, value) in fields {
        body.extend_from_slice(
            format!(
                "--{boundary}\r\nContent-Disposition: form-data; name=\"{key}\"\r\n\r\n{value}\r\n"
            )
            .as_bytes(),
        );
    }
    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; \
             filename=\"{filename}\"\r\nContent-Type: {content_type}\r\n\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(data);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

/// A boundary that cannot collide with the payload: the pid, a monotonic
/// counter and the clock, in hex (Python used `uuid4().hex`; the value only has
/// to be unique per request).
pub fn boundary() -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_nanos() as u64)
        .unwrap_or(0);
    format!(
        "----mpdvoice{:x}{:x}{:x}",
        std::process::id(),
        nanos,
        counter
    )
}

/// A backend that turns a WAV file into text.
pub trait SpeechToText {
    fn name(&self) -> &'static str;
    fn available(&self) -> bool;
    fn transcribe(&self, wav: &Path, language: Option<&str>) -> Result<String, SttError>;
}

/// OpenAI-compatible HTTP transcription client.
pub struct HttpStt {
    pub base_url: String,
    pub model: String,
    pub language: String,
    pub timeout: Duration,
}

impl HttpStt {
    pub fn new(base_url: &str, model: &str, language: &str, timeout: Duration) -> Self {
        let model = if model.is_empty() { "whisper-1" } else { model };
        HttpStt {
            base_url: base_url.trim_end_matches('/').to_string(),
            model: model.to_string(),
            language: language.to_string(),
            timeout,
        }
    }

    pub fn endpoint(&self) -> String {
        format!("{}/v1/audio/transcriptions", self.base_url)
    }

    pub fn models_endpoint(&self) -> String {
        format!("{}/v1/models", self.base_url)
    }

    fn probe(&self, timeout: Duration) -> bool {
        matches!(http::get(&self.models_endpoint(), timeout), Ok(response) if response.status < 400)
    }

    /// Parse a transcription answer: `{"text": "..."}` or raw text.
    pub fn parse(payload: &[u8]) -> String {
        let text = String::from_utf8_lossy(payload).to_string();
        if let Some(value) = http::json_string_field(&text, "text") {
            return clean_transcript(&value);
        }
        clean_transcript(&text)
    }
}

impl SpeechToText for HttpStt {
    fn name(&self) -> &'static str {
        "http"
    }

    fn available(&self) -> bool {
        self.probe(Duration::from_millis(1500))
    }

    fn transcribe(&self, wav: &Path, language: Option<&str>) -> Result<String, SttError> {
        let data = match std::fs::read(wav) {
            Ok(data) => data,
            Err(exc) => return fail(format!("cannot read {}: {exc}", wav.display())),
        };
        let filename = wav
            .file_name()
            .map(|name| name.to_string_lossy().to_string())
            .unwrap_or_else(|| "audio.wav".to_string());
        let lang = language.unwrap_or(&self.language).to_string();
        let mut fields: Vec<(&str, &str)> =
            vec![("model", &self.model), ("response_format", "json")];
        let short;
        if !lang.is_empty() && lang != "auto" {
            short = lang.chars().take(2).collect::<String>();
            fields.push(("language", &short));
        }
        let boundary = boundary();
        let body = multipart(&fields, "file", &filename, &data, "audio/wav", &boundary);
        let content_type = format!("multipart/form-data; boundary={boundary}");
        let response = match http::post(&self.endpoint(), &content_type, &body, self.timeout) {
            Ok(response) => response,
            Err(exc) => return fail(format!("transcription endpoint unreachable: {exc}")),
        };
        if response.status != 200 {
            let detail =
                String::from_utf8_lossy(&response.body[..response.body.len().min(200)]).to_string();
            if detail.is_empty() {
                return fail(format!(
                    "transcription failed with status {}",
                    response.status
                ));
            }
            return fail(format!(
                "transcription failed ({}): {detail}",
                response.status
            ));
        }
        Ok(HttpStt::parse(&response.body))
    }
}

/// whisper.cpp's `whisper-cli` driven directly.
pub struct CliStt {
    pub binary: String,
    pub model: String,
    pub language: String,
    pub extra_args: Vec<String>,
    pub timeout: Duration,
}

impl CliStt {
    pub fn new(binary: &str, model: &str, language: &str, timeout: Duration) -> Self {
        CliStt {
            binary: binary.to_string(),
            model: model.to_string(),
            language: language.to_string(),
            extra_args: Vec::new(),
            timeout,
        }
    }

    fn argv(&self, wav: &Path, language: &str, quiet: bool) -> Vec<String> {
        let mut argv = vec![self.binary.clone(), "-nt".to_string()];
        if quiet {
            argv.push("-np".to_string());
        }
        if !self.model.is_empty() {
            argv.push("-m".to_string());
            argv.push(self.model.clone());
        }
        argv.push("-f".to_string());
        argv.push(wav.display().to_string());
        if !language.is_empty() && language != "auto" {
            argv.push("-l".to_string());
            argv.push(language.chars().take(2).collect());
        }
        argv.extend(self.extra_args.iter().cloned());
        argv
    }
}

struct RunResult {
    code: i32,
    stdout: String,
    stderr: String,
}

fn run_capture(argv: &[String], timeout: Duration) -> Result<RunResult, SttError> {
    let mut child = Command::new(&argv[0])
        .args(&argv[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|exc| SttError(format!("cannot run {}: {exc}", argv[0])))?;
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let output = child
                    .wait_with_output()
                    .map_err(|exc| SttError(format!("cannot read {}: {exc}", argv[0])))?;
                return Ok(RunResult {
                    code: status.code().unwrap_or(-1),
                    stdout: String::from_utf8_lossy(&output.stdout).to_string(),
                    stderr: String::from_utf8_lossy(&output.stderr).to_string(),
                });
            }
            Ok(None) if std::time::Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return fail(format!(
                    "{} timed out after {}s",
                    argv[0],
                    timeout.as_secs_f64()
                ));
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(20)),
            Err(exc) => return fail(format!("cannot run {}: {exc}", argv[0])),
        }
    }
}

fn last_error_line(stderr: &str) -> String {
    stderr
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or("")
        .to_string()
}

impl SpeechToText for CliStt {
    fn name(&self) -> &'static str {
        "cli"
    }

    fn available(&self) -> bool {
        if crate::audio::which(&self.binary).is_none() {
            return false;
        }
        self.model.is_empty() || Path::new(&self.model).exists()
    }

    fn transcribe(&self, wav: &Path, language: Option<&str>) -> Result<String, SttError> {
        if crate::audio::which(&self.binary).is_none() {
            return fail(format!("'{}' is not in PATH", self.binary));
        }
        let lang = language.unwrap_or(&self.language).to_string();
        let mut result = run_capture(&self.argv(wav, &lang, true), self.timeout)?;
        if result.code != 0 && result.stderr.to_lowercase().contains("unknown argument") {
            // Older whisper.cpp builds have no -np flag.
            result = run_capture(&self.argv(wav, &lang, false), self.timeout)?;
        }
        if result.code != 0 {
            return fail(format!(
                "{} failed: {}",
                self.binary,
                last_error_line(&result.stderr)
            ));
        }
        Ok(clean_transcript(&result.stdout))
    }
}

/// Transcribe by running a user supplied command.
///
/// The template may use `{wav}` and `{lang}`; each placeholder becomes a single
/// argv element, and the command must print the transcript to stdout.
pub struct CmdStt {
    pub command: String,
    pub language: String,
    pub timeout: Duration,
}

const WAV_TOKEN: &str = "\u{0}mpd-voice-wav\u{0}";
const LANG_TOKEN: &str = "\u{0}mpd-voice-lang\u{0}";

impl CmdStt {
    pub fn new(command: &str, language: &str, timeout: Duration) -> Result<Self, SttError> {
        if command.is_empty() {
            return fail("the 'cmd' backend needs --stt-cmd");
        }
        Ok(CmdStt {
            command: command.to_string(),
            language: language.to_string(),
            timeout,
        })
    }

    fn argv(&self, wav: &Path, language: &str) -> Result<Vec<String>, SttError> {
        if !self.command.contains("{wav}") {
            return fail("the --stt-cmd template must contain {wav}");
        }
        let template = self
            .command
            .replace("{wav}", WAV_TOKEN)
            .replace("{lang}", LANG_TOKEN);
        Ok(crate::audio::shlex_split(&template)
            .into_iter()
            .map(|argument| {
                argument
                    .replace(WAV_TOKEN, &wav.display().to_string())
                    .replace(LANG_TOKEN, language)
            })
            .collect())
    }
}

impl SpeechToText for CmdStt {
    fn name(&self) -> &'static str {
        "cmd"
    }

    fn available(&self) -> bool {
        match self.argv(Path::new("probe.wav"), &self.language) {
            Ok(argv) => !argv.is_empty() && crate::audio::which(&argv[0]).is_some(),
            Err(_) => false,
        }
    }

    fn transcribe(&self, wav: &Path, language: Option<&str>) -> Result<String, SttError> {
        let argv = self.argv(wav, language.unwrap_or(&self.language))?;
        let result = run_capture(&argv, self.timeout)?;
        if result.code != 0 {
            return fail(format!(
                "STT command failed: {}",
                last_error_line(&result.stderr)
            ));
        }
        Ok(clean_transcript(&result.stdout))
    }
}

/// Placeholder for text-only operation.
pub struct NullStt;

impl SpeechToText for NullStt {
    fn name(&self) -> &'static str {
        "none"
    }

    fn available(&self) -> bool {
        false
    }

    fn transcribe(&self, _wav: &Path, _language: Option<&str>) -> Result<String, SttError> {
        fail("speech recognition is disabled (--stt none)")
    }
}

/// Construct the requested backend; `auto` probes HTTP, then the CLI.
pub fn build_stt(
    kind: &str,
    base_url: &str,
    model: &str,
    binary: &str,
    command: &str,
    language: &str,
    timeout: Duration,
) -> Result<Box<dyn SpeechToText>, SttError> {
    match kind {
        "none" => Ok(Box::new(NullStt)),
        "cmd" => Ok(Box::new(CmdStt::new(command, language, timeout)?)),
        "cli" => Ok(Box::new(CliStt::new(binary, model, language, timeout))),
        "http" => Ok(Box::new(HttpStt::new(base_url, "", language, timeout))),
        _ => {
            let http_backend = HttpStt::new(base_url, "", language, timeout);
            if http_backend.available() {
                return Ok(Box::new(http_backend));
            }
            let cli = CliStt::new(binary, model, language, timeout);
            if cli.available() {
                return Ok(Box::new(cli));
            }
            fail(
                "no speech recognition backend available: enable the local speech stack, point \
                 --stt-url at an OpenAI-compatible server, pass --stt cli with --stt-model, or use \
                 --stt-cmd",
            )
        }
    }
}

/// Path helper used by callers that keep the WAV around after transcription.
pub fn wav_path(path: &Path) -> PathBuf {
    path.to_path_buf()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transcript_noise_is_dropped() {
        let raw = "whisper_init_from_file: loading\n\
                   [00:00.000 --> 00:02.000]   Next track   \n\
                   main: processing\n\
                   error: something\n\
                   ██ second line";
        assert_eq!(clean_transcript(raw), "Next track ██ second line");
    }

    #[test]
    fn transcript_whitespace_is_collapsed() {
        assert_eq!(clean_transcript("  next   track \n\n"), "next track");
        assert_eq!(clean_transcript(""), "");
    }

    #[test]
    fn http_payload_parsing() {
        assert_eq!(HttpStt::parse(br#"{"text": " next track "}"#), "next track");
        assert_eq!(HttpStt::parse(b"plain text"), "plain text");
        assert_eq!(HttpStt::parse(b""), "");
    }

    #[test]
    fn multipart_body_has_fields_and_file() {
        let body = multipart(
            &[("model", "whisper-1"), ("response_format", "json")],
            "file",
            "a.wav",
            b"RIFF",
            "audio/wav",
            "BOUND",
        );
        let text = String::from_utf8_lossy(&body).to_string();
        assert!(text.contains(
            "--BOUND\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"
        ));
        assert!(text.contains(
            "name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"
        ));
        assert!(text.ends_with("--BOUND--\r\n"));
    }

    #[test]
    fn cli_argv_matches_python() {
        let backend = CliStt::new("whisper-cli", "/m.bin", "ru", Duration::from_secs(5));
        assert_eq!(
            backend.argv(Path::new("/tmp/a.wav"), "ru", true).join(" "),
            "whisper-cli -nt -np -m /m.bin -f /tmp/a.wav -l ru"
        );
        assert_eq!(
            backend
                .argv(Path::new("/tmp/a.wav"), "auto", false)
                .join(" "),
            "whisper-cli -nt -m /m.bin -f /tmp/a.wav"
        );
    }

    #[test]
    fn cmd_template_splits_into_one_argument() {
        let backend = CmdStt::new(
            "tool --file {wav} --lang {lang}",
            "ru",
            Duration::from_secs(5),
        )
        .unwrap();
        assert_eq!(
            backend.argv(Path::new("/tmp/x.wav"), "en").unwrap(),
            vec!["tool", "--file", "/tmp/x.wav", "--lang", "en"]
        );
        assert!(CmdStt::new("tool {lang}", "ru", Duration::from_secs(5))
            .unwrap()
            .argv(Path::new("x"), "ru")
            .is_err());
        assert!(CmdStt::new("", "ru", Duration::from_secs(5)).is_err());
    }

    #[test]
    fn auto_backend_without_servers_fails_like_python() {
        // Nothing is listening on this port in the build sandbox and
        // whisper-cli is not installed, so `auto` must refuse with the same
        // explanation the Python builder gives.
        let error = build_stt(
            "auto",
            "http://127.0.0.1:9",
            "",
            "definitely-not-a-binary",
            "",
            "ru",
            Duration::from_millis(200),
        )
        .err()
        .expect("no backend");
        assert!(error
            .0
            .starts_with("no speech recognition backend available"));
    }

    #[test]
    fn null_backend_is_never_available() {
        let backend = build_stt(
            "none",
            "http://127.0.0.1:9",
            "",
            "whisper-cli",
            "",
            "ru",
            Duration::from_millis(50),
        )
        .unwrap();
        assert_eq!(backend.name(), "none");
        assert!(!backend.available());
        assert!(backend.transcribe(Path::new("/tmp/x.wav"), None).is_err());
    }
}
