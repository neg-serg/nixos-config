//! Microphone capture with a small energy based voice activity detector.
//!
//! Port of `mpd_voice/audio.py`. Capture itself is delegated to whatever the
//! host already has (PipeWire, ALSA, FFmpeg, SoX), so the client needs no audio
//! stack of its own: the recorder reads raw signed 16-bit mono PCM from the
//! child process, feeds fixed size frames to [`SpeechGate`] and keeps only the
//! utterance (silence trimmed).

use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

pub const PCM_RATE: u32 = 16000;
pub const PCM_WIDTH: usize = 2;
pub const PCM_CHANNELS: u32 = 1;
pub const FRAME_MS: u32 = 30;

/// Backends in auto-detection order.
pub const BACKENDS: [&str; 5] = ["pw-record", "arecord", "ffmpeg", "sox", "cmd"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureError(pub String);

impl std::fmt::Display for CaptureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for CaptureError {}

fn fail<T>(message: impl Into<String>) -> Result<T, CaptureError> {
    Err(CaptureError(message.into()))
}

/// Split a command template the way `shlex.split` does for our templates:
/// whitespace separates words, single quotes are literal, double quotes allow
/// `\"` and `\\`.
pub fn shlex_split(text: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut started = false;
    let mut chars = text.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            ch if ch.is_whitespace() => {
                if started {
                    words.push(std::mem::take(&mut current));
                    started = false;
                }
            }
            '\'' => {
                started = true;
                for inner in chars.by_ref() {
                    if inner == '\'' {
                        break;
                    }
                    current.push(inner);
                }
            }
            '"' => {
                started = true;
                while let Some(inner) = chars.next() {
                    match inner {
                        '"' => break,
                        '\\' => {
                            if let Some(escaped) = chars.next() {
                                current.push(escaped);
                            }
                        }
                        other => current.push(other),
                    }
                }
            }
            other => {
                started = true;
                current.push(other);
            }
        }
    }
    if started {
        words.push(current);
    }
    words
}

/// Command line that writes raw s16le mono PCM to stdout.
pub fn build_capture_argv(
    backend: &str,
    device: &str,
    rate: u32,
    command: &str,
) -> Result<Vec<String>, CaptureError> {
    let rate_text = rate.to_string();
    if backend == "cmd" {
        if command.is_empty() {
            return fail("capture backend 'cmd' needs a command template");
        }
        let device = if device.is_empty() { "default" } else { device };
        let expanded = command
            .replace("{rate}", &rate_text)
            .replace("{device}", device);
        return Ok(shlex_split(&expanded));
    }
    if backend == "pw-record" {
        let mut argv = vec![
            "pw-record".to_string(),
            "--rate".to_string(),
            rate_text,
            "--channels".to_string(),
            PCM_CHANNELS.to_string(),
            "--format".to_string(),
            "s16".to_string(),
        ];
        if !device.is_empty() {
            argv.push("--target".to_string());
            argv.push(device.to_string());
        }
        argv.push("-".to_string());
        return Ok(argv);
    }
    if backend == "arecord" {
        let mut argv = vec![
            "arecord".to_string(),
            "-q".to_string(),
            "-t".to_string(),
            "raw".to_string(),
            "-f".to_string(),
            "S16_LE".to_string(),
            "-r".to_string(),
            rate_text,
            "-c".to_string(),
            PCM_CHANNELS.to_string(),
        ];
        if !device.is_empty() {
            argv.push("-D".to_string());
            argv.push(device.to_string());
        }
        argv.push("-".to_string());
        return Ok(argv);
    }
    if backend == "ffmpeg" {
        return Ok(vec![
            "ffmpeg".to_string(),
            "-hide_banner".to_string(),
            "-loglevel".to_string(),
            "error".to_string(),
            "-f".to_string(),
            "pulse".to_string(),
            "-i".to_string(),
            if device.is_empty() { "default" } else { device }.to_string(),
            "-ac".to_string(),
            PCM_CHANNELS.to_string(),
            "-ar".to_string(),
            rate_text,
            "-f".to_string(),
            "s16le".to_string(),
            "-".to_string(),
        ]);
    }
    if backend == "sox" {
        return Ok(vec![
            "sox".to_string(),
            "-q".to_string(),
            "-t".to_string(),
            "raw".to_string(),
            "-r".to_string(),
            rate_text,
            "-c".to_string(),
            PCM_CHANNELS.to_string(),
            "-e".to_string(),
            "signed-integer".to_string(),
            "-b".to_string(),
            "16".to_string(),
            if device.is_empty() { "-d" } else { device }.to_string(),
            "-".to_string(),
        ]);
    }
    fail(format!("unknown capture backend: {backend}"))
}

/// `shutil.which`: is the executable on `PATH`?
pub fn which(program: &str) -> Option<PathBuf> {
    if program.contains('/') {
        let path = PathBuf::from(program);
        return path.is_file().then_some(path);
    }
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(program))
        .find(|candidate| candidate.is_file())
}

/// Pick the first usable capture backend (`cmd` wins when a command is given).
pub fn detect_backend(preferred: &str, command: &str) -> Result<String, CaptureError> {
    if !command.is_empty() {
        return Ok("cmd".to_string());
    }
    if preferred == "cmd" {
        return fail("the 'cmd' capture backend needs a command template");
    }
    if preferred != "auto" {
        let argv = build_capture_argv(preferred, "", PCM_RATE, "")?;
        if which(&argv[0]).is_some() {
            return Ok(preferred.to_string());
        }
        return fail(format!("capture backend not found: {preferred}"));
    }
    for backend in BACKENDS {
        if backend == "cmd" {
            continue;
        }
        let Ok(argv) = build_capture_argv(backend, "", PCM_RATE, "") else {
            continue;
        };
        if which(&argv[0]).is_some() {
            return Ok(backend.to_string());
        }
    }
    fail("no capture backend found (install pipewire, alsa-utils, ffmpeg or sox)")
}

/// Root mean square of a signed 16-bit little-endian frame.
pub fn rms(frame: &[u8]) -> f64 {
    let usable = frame.len() - frame.len() % 2;
    let samples: Vec<i16> = frame[..usable]
        .chunks_exact(2)
        .map(|pair| i16::from_le_bytes([pair[0], pair[1]]))
        .collect();
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f64 = samples
        .iter()
        .map(|sample| f64::from(*sample) * f64::from(*sample))
        .sum();
    (sum / samples.len() as f64).sqrt()
}

/// What [`SpeechGate::push`] decided about one frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Event {
    Idle,
    SpeechStart,
    Speech,
    SpeechEnd,
}

impl Event {
    pub fn as_str(&self) -> &'static str {
        match self {
            Event::Idle => "idle",
            Event::SpeechStart => "speech_start",
            Event::Speech => "speech",
            Event::SpeechEnd => "speech_end",
        }
    }
}

/// Energy gate with an adaptive noise floor.
///
/// `push` consumes one frame and returns an [`Event`]; the accepted utterance is
/// available as [`SpeechGate::utterance`] (pre-roll included, trailing silence
/// trimmed).
#[derive(Debug, Clone)]
pub struct SpeechGate {
    pub frame_bytes: usize,
    pub silence_frames: usize,
    pub min_speech_frames: usize,
    pub threshold_ratio: f64,
    pub absolute_floor: f64,
    pub noise_floor: f64,
    pre_roll: Vec<Vec<u8>>,
    pre_roll_len: usize,
    pub state: &'static str,
    pub utterance: Vec<u8>,
    speech_frames: usize,
    silent_frames: usize,
}

impl SpeechGate {
    pub fn new(rate: u32, frame_ms: u32, silence_seconds: f64) -> Self {
        Self::with_thresholds(rate, frame_ms, silence_seconds, 0.3, 3.0, 120.0, 0.24)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_thresholds(
        rate: u32,
        frame_ms: u32,
        silence_seconds: f64,
        min_speech_seconds: f64,
        threshold_ratio: f64,
        absolute_floor: f64,
        pre_roll_seconds: f64,
    ) -> Self {
        let frame_bytes = (rate as f64 * frame_ms as f64 / 1000.0) as usize * PCM_WIDTH;
        let silence_frames = ((silence_seconds * 1000.0 / frame_ms as f64) as usize).max(1);
        let min_speech_frames = ((min_speech_seconds * 1000.0 / frame_ms as f64) as usize).max(1);
        let pre_roll_len = ((pre_roll_seconds * 1000.0 / frame_ms as f64) as usize).max(1);
        SpeechGate {
            frame_bytes,
            silence_frames,
            min_speech_frames,
            threshold_ratio,
            absolute_floor,
            noise_floor: absolute_floor,
            pre_roll: Vec::new(),
            pre_roll_len,
            state: "idle",
            utterance: Vec::new(),
            speech_frames: 0,
            silent_frames: 0,
        }
    }

    pub fn threshold(&self) -> f64 {
        (self.noise_floor * self.threshold_ratio).max(self.absolute_floor)
    }

    pub fn speech_seconds(&self) -> f64 {
        self.speech_frames as f64 * self.frame_bytes as f64 / f64::from(PCM_RATE * PCM_WIDTH as u32)
    }

    pub fn has_speech(&self) -> bool {
        self.speech_frames >= self.min_speech_frames
    }

    /// Consume one frame; returns what the gate decided.
    pub fn push(&mut self, frame: &[u8]) -> Event {
        let level = rms(frame);
        if self.state == "idle" {
            if level >= self.threshold() {
                self.state = "speech";
                self.speech_frames = 1;
                self.silent_frames = 0;
                self.utterance = self.pre_roll.concat();
                self.utterance.extend_from_slice(frame);
                self.pre_roll.clear();
                return Event::SpeechStart;
            }
            // Track the room: quiet frames define the noise floor.
            self.noise_floor = 0.9 * self.noise_floor + 0.1 * level;
            if self.pre_roll.len() == self.pre_roll_len {
                self.pre_roll.remove(0);
            }
            self.pre_roll.push(frame.to_vec());
            return Event::Idle;
        }
        if level >= self.threshold() {
            self.speech_frames += 1;
            self.silent_frames = 0;
            self.utterance.extend_from_slice(frame);
            return Event::Speech;
        }
        self.silent_frames += 1;
        self.utterance.extend_from_slice(frame);
        if self.silent_frames >= self.silence_frames {
            self.state = "idle";
            // Drop the trailing pause but keep the final 150 ms of it.
            let keep = 5 * self.frame_bytes;
            let excess = (self.silent_frames - 1) * self.frame_bytes;
            if excess > keep {
                let drop = excess - keep;
                let new_len = self.utterance.len().saturating_sub(drop);
                self.utterance.truncate(new_len);
            }
            return Event::SpeechEnd;
        }
        Event::Speech
    }
}

/// Write a mono 16-bit PCM buffer as a canonical 44-byte-header WAV file.
pub fn write_wav(path: &Path, pcm: &[u8], rate: u32, channels: u32) -> std::io::Result<PathBuf> {
    let mut file = std::fs::File::create(path)?;
    let data_len = pcm.len() as u32;
    let block_align = channels * PCM_WIDTH as u32;
    let byte_rate = rate * block_align;
    file.write_all(b"RIFF")?;
    file.write_all(&(36 + data_len).to_le_bytes())?;
    file.write_all(b"WAVEfmt ")?;
    file.write_all(&16u32.to_le_bytes())?;
    file.write_all(&1u16.to_le_bytes())?; // PCM
    file.write_all(&(channels as u16).to_le_bytes())?;
    file.write_all(&rate.to_le_bytes())?;
    file.write_all(&byte_rate.to_le_bytes())?;
    file.write_all(&(block_align as u16).to_le_bytes())?;
    file.write_all(&(16u16).to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&data_len.to_le_bytes())?;
    file.write_all(pcm)?;
    Ok(path.to_path_buf())
}

/// Return `(pcm, rate)` for a mono 16-bit WAV file.
pub fn read_wav(path: &Path) -> Result<(Vec<u8>, u32), String> {
    let mut file = std::fs::File::open(path).map_err(|exc| format!("{path:?}: {exc}"))?;
    let mut header = [0u8; 12];
    file.read_exact(&mut header)
        .map_err(|exc| format!("{path:?}: {exc}"))?;
    if &header[0..4] != b"RIFF" || &header[8..12] != b"WAVE" {
        return Err(format!("{path:?}: not a WAV file"));
    }
    let mut rate = PCM_RATE;
    let mut channels = 1u32;
    let mut width = PCM_WIDTH;
    loop {
        let mut chunk = [0u8; 8];
        if file.read_exact(&mut chunk).is_err() {
            return Err(format!("{path:?}: truncated WAV"));
        }
        let id = &chunk[0..4];
        let size = u32::from_le_bytes([chunk[4], chunk[5], chunk[6], chunk[7]]);
        match id {
            b"fmt " => {
                let mut fmt = vec![0u8; size as usize];
                file.read_exact(&mut fmt)
                    .map_err(|exc| format!("{path:?}: {exc}"))?;
                if fmt.len() >= 16 {
                    channels = u32::from(u16::from_le_bytes([fmt[2], fmt[3]]));
                    rate = u32::from_le_bytes([fmt[4], fmt[5], fmt[6], fmt[7]]);
                    width = usize::from(u16::from_le_bytes([fmt[14], fmt[15]])) / 8;
                }
            }
            b"data" => {
                if width != PCM_WIDTH {
                    return Err(format!("{path:?}: only 16-bit WAV is supported"));
                }
                if channels != 1 {
                    return Err(format!("{path:?}: only mono WAV is supported"));
                }
                let mut pcm = vec![0u8; size as usize];
                file.read_exact(&mut pcm)
                    .map_err(|exc| format!("{path:?}: {exc}"))?;
                return Ok((pcm, rate));
            }
            _ => {
                file.seek(SeekFrom::Current(i64::from(size)))
                    .map_err(|exc| format!("{path:?}: {exc}"))?;
            }
        }
    }
}

pub fn duration_seconds(pcm: &[u8], rate: u32) -> f64 {
    pcm.len() as f64 / f64::from(rate * PCM_WIDTH as u32)
}

/// Records one utterance from the microphone.
pub struct Recorder {
    pub backend: String,
    pub device: String,
    pub rate: u32,
    pub command: String,
}

impl Recorder {
    pub fn new(
        backend: &str,
        device: &str,
        rate: u32,
        command: &str,
    ) -> Result<Self, CaptureError> {
        Ok(Recorder {
            backend: detect_backend(backend, command)?,
            device: device.to_string(),
            rate,
            command: command.to_string(),
        })
    }

    /// Record until the speaker stops, or until `max_seconds`.
    pub fn capture(
        &self,
        max_seconds: f64,
        silence_seconds: f64,
        vad: bool,
    ) -> Result<Vec<u8>, CaptureError> {
        let argv = build_capture_argv(&self.backend, &self.device, self.rate, &self.command)?;
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|exc| CaptureError(format!("cannot start {}: {exc}", argv[0])))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| CaptureError("capture child has no stdout".to_string()))?;
        let collected = self.capture_from(stdout, max_seconds, silence_seconds, vad);
        let code = stop_child(&mut child);
        let pcm = collected?;
        // A positive exit code means the backend failed (busy device, missing
        // permission, bad arguments); the SIGTERM we send ourselves is -15.
        if code > 0 {
            return fail(format!("{} exited with status {code}", argv[0]));
        }
        Ok(pcm)
    }

    /// The recording loop, over any reader (tests feed a cursor).
    pub fn capture_from<R: Read>(
        &self,
        mut reader: R,
        max_seconds: f64,
        silence_seconds: f64,
        vad: bool,
    ) -> Result<Vec<u8>, CaptureError> {
        let mut gate = SpeechGate::new(self.rate, FRAME_MS, silence_seconds);
        let mut collected: Vec<u8> = Vec::new();
        let deadline = Instant::now() + Duration::from_secs_f64(max_seconds.max(0.0));
        let mut frame = vec![0u8; gate.frame_bytes];
        loop {
            let mut filled = 0;
            while filled < frame.len() {
                match reader.read(&mut frame[filled..]) {
                    Ok(0) => break,
                    Ok(read) => filled += read,
                    Err(exc) if exc.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
            if filled == 0 {
                break;
            }
            let chunk = &frame[..filled];
            if vad {
                if gate.push(chunk) == Event::SpeechEnd && gate.has_speech() {
                    break;
                }
            } else {
                collected.extend_from_slice(chunk);
            }
            if Instant::now() >= deadline {
                break;
            }
            if filled < frame.len() {
                break;
            }
        }
        if vad {
            Ok(gate.utterance)
        } else {
            Ok(collected)
        }
    }
}

fn stop_child(child: &mut Child) -> i32 {
    let _ = child.kill();
    match child.wait() {
        Ok(status) => status.code().unwrap_or(-1),
        Err(_) => -1,
    }
}
