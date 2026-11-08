//! Rust port of `packages/local-bin/bin/pic-ocr`.
//!
//! OCR an image and put the result into the clipboard. `magick`, `curl`,
//! `grim`, `slurp`, `mktemp`, `wl-copy` and `notify-send` stay subprocesses;
//! the argument handling, the base64 encoding, the Ollama JSON payload and the
//! response parsing are native. NEURAL ONLY: tesseract was removed on
//! 2026-11-08 (it lost ~7 of 14 key fields on the scan benchmark and produced
//! garbage on formulas), so the classic engine, its menu entry and the nn
//! fallback are gone.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::ExitCode;

use local_bin_desktop::env;
use local_bin_desktop::helptext::PIC_OCR_HELP;
use local_bin_desktop::json::Json;
use local_bin_desktop::proc::{Cmd, Input, Sink};
use local_bin_desktop::text;

fn main() -> ExitCode {
    let code = run();
    ExitCode::from((code & 0xff) as u8)
}

fn run() -> i32 {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let args: Vec<Vec<u8>> = arguments.map(|value| value.as_bytes().to_vec()).collect();

    let mut engine: Vec<u8> = b"nn".to_vec();
    let mut image: Option<Vec<u8>> = None;
    let mut index = 0;
    while index < args.len() {
        let argument = args[index].as_slice();
        if let Some(value) = argument.strip_prefix(b"--engine=") {
            engine = value.to_vec();
            index += 1;
        } else if argument == b"-e" {
            // The original `shift 2`s past the missing value and loops forever;
            // the port consumes the flag once and continues.
            engine = args.get(index + 1).cloned().unwrap_or_default();
            index += 2;
        } else if argument == b"-n" || argument == b"--nn" {
            engine = b"nn".to_vec();
            index += 1;
        } else if argument == b"-m" || argument == b"--menu" {
            // The engine menu had one entry left after tesseract was dropped;
            // the flag stays as an alias for the neural engine so existing
            // keybinds keep working.
            engine = b"nn".to_vec();
            index += 1;
        } else if argument == b"-h" || argument == b"--help" {
            env::out_str(PIC_OCR_HELP);
            return 0;
        } else if argument.starts_with(b"-") {
            let mut message = b"pic-ocr: unknown option: ".to_vec();
            message.extend_from_slice(argument);
            message.push(b'\n');
            env::err(&message);
            env::err_str(PIC_OCR_HELP);
            return 1;
        } else {
            image = Some(argument.to_vec());
            index += 1;
        }
    }

    // Keeps the slurp/grim temporary capture alive for the whole run and
    // removes it on every exit path (the original's `trap ... EXIT`).
    let mut temporary = Temporary::default();

    let image = match image {
        Some(image) => image,
        None => {
            let region = Cmd::new("slurp")
                .stdout(Sink::Capture)
                .stderr(Sink::Null)
                .run();
            if region.code != 0 {
                env::err_str("pic-ocr: no region selected\n");
                return 1;
            }
            let geometry = text::strip_trailing_newlines(&region.stdout).to_vec();
            let created = Cmd::new("mktemp")
                .arg("--suffix=.png")
                .stdout(Sink::Capture)
                .diag(&program, 46)
                .run();
            let path = text::strip_trailing_newlines(&created.stdout).to_vec();
            temporary.path = Some(path.clone());
            let shot = Cmd::new("grim")
                .arg("-g")
                .arg_bytes(&geometry)
                .arg_bytes(&path)
                .diag(&program, 47)
                .run();
            if shot.code != 0 {
                let _ = std::fs::remove_file(OsStr::from_bytes(&path));
                temporary.path = None;
                return 1;
            }
            path
        }
    };

    if !Path::new(OsStr::from_bytes(&image)).is_file() {
        let mut message = b"pic-ocr: no such file: ".to_vec();
        message.extend_from_slice(&image);
        message.push(b'\n');
        env::err(&message);
        return 1;
    }

    if engine == b"menu" {
        // No engine list is left: the menu used to offer tesseract and the
        // neural model. Keep the value harmless if it arrives via -e.
        engine = b"nn".to_vec();
    }

    let (mut result, engine_name): (Vec<u8>, Vec<u8>) = match engine.as_slice() {
        b"nn" | b"neural" | b"ollama" => {
            let text = ocr_neural(&image, &program);
            let model = env::var_or("PIC_OCR_NN_MODEL", b"qwen3-vl-abliterated:8b");
            let mut name = model;
            name.extend_from_slice(b" (local)");
            (text, name)
        }
        _ => {
            let mut message = b"pic-ocr: unknown engine: ".to_vec();
            message.extend_from_slice(&engine);
            message.push(b'\n');
            env::err(&message);
            env::err_str(PIC_OCR_HELP);
            return 1;
        }
    };

    if result.is_empty() {
        let mut body = b"No text recognized (".to_vec();
        body.extend_from_slice(&engine_name);
        body.extend_from_slice(b")");
        let _ = Cmd::new("notify-send")
            .args(["-a", "pic-ocr", "-u", "critical", "OCR"])
            .arg_bytes(&body)
            .diag(&program, 115)
            .run();
        return 1;
    }

    // `printf '%s\n' "$text" | wl-copy`
    result.push(b'\n');
    let _ = Cmd::new("wl-copy")
        .stdin(Input::Bytes(&result))
        .diag(&program, 119)
        .run();
    result.pop();

    let preview_line = text::newlines_to_spaces(&result);
    let preview = if text::locale_is_utf8() {
        text::first_chars(&preview_line, 140)
    } else {
        text::first_bytes(&preview_line, 140)
    };
    let mut title = b"OCR (".to_vec();
    title.extend_from_slice(&engine_name);
    title.push(b')');
    let outcome = Cmd::new("notify-send")
        .args(["-a", "pic-ocr"])
        .arg_bytes(&title)
        .arg_bytes(&preview)
        .diag(&program, 121)
        .run();
    outcome.code
}

/// The Ollama engine: downscale to JPEG, base64 it, ask the vision model, and
/// read `.choices[0].message.content // empty` from the reply.
fn ocr_neural(image: &[u8], program: &[u8]) -> Vec<u8> {
    let model = env::var_or("PIC_OCR_NN_MODEL", b"qwen3-vl-abliterated:8b");
    let base_url = env::var_or("PIC_OCR_OLLAMA_URL", b"http://localhost:11434/v1");
    let converted = Cmd::new("magick")
        .arg_bytes(image)
        .args(["-resize", "1600x1600>", "-quality", "85", "jpg:-"])
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .run();
    let encoded = base64(&converted.stdout);
    if encoded.is_empty() {
        return Vec::new();
    }
    let prompt = b"Transcribe all text from this image, preserving line breaks. Output only the recognized text, no commentary.";
    let mut url = b"data:image/jpeg;base64,".to_vec();
    url.extend_from_slice(&encoded);
    let payload = payload(&model, &url, prompt);

    let mut endpoint = base_url.clone();
    endpoint.extend_from_slice(b"/chat/completions");
    let response = Cmd::new("curl")
        .args(["-s", "--max-time", "120"])
        .arg_bytes(&endpoint)
        .args(["-H", "Content-Type: application/json", "-d"])
        .arg_bytes(&payload)
        .stdout(Sink::Capture)
        .diag(program, 72)
        .run();
    let value = match Json::parse(&response.stdout) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };
    let content = value
        .get("choices")
        .and_then(|choices| choices.index(0))
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"));
    match content {
        Some(content) => text::strip_trailing_newlines(&content.raw_or_empty()).to_vec(),
        None => Vec::new(),
    }
}

/// The `jq -n` payload, byte for byte (jq's 2-space layout).
fn payload(model: &[u8], image_url: &[u8], prompt: &[u8]) -> Vec<u8> {
    use local_bin_desktop::json::Json;
    let content = Json::Arr(vec![
        Json::Obj(vec![
            (b"type".to_vec(), Json::Str(b"image_url".to_vec())),
            (
                b"image_url".to_vec(),
                Json::Obj(vec![(b"url".to_vec(), Json::Str(image_url.to_vec()))]),
            ),
        ]),
        Json::Obj(vec![
            (b"type".to_vec(), Json::Str(b"text".to_vec())),
            (b"text".to_vec(), Json::Str(prompt.to_vec())),
        ]),
    ]);
    let message = Json::Obj(vec![
        (b"role".to_vec(), Json::Str(b"user".to_vec())),
        (b"content".to_vec(), content),
    ]);
    Json::Obj(vec![
        (b"model".to_vec(), Json::Str(model.to_vec())),
        (b"messages".to_vec(), Json::Arr(vec![message])),
        (b"stream".to_vec(), Json::Bool(false)),
    ])
    .pretty()
}

/// `base64 -w0`: standard alphabet, padded, no line wrapping.
fn base64(data: &[u8]) -> Vec<u8> {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let first = chunk[0];
        let second = chunk.get(1).copied().unwrap_or(0);
        let third = chunk.get(2).copied().unwrap_or(0);
        let combined = (u32::from(first) << 16) | (u32::from(second) << 8) | u32::from(third);
        out.push(ALPHABET[(combined >> 18) as usize & 0x3f]);
        out.push(ALPHABET[(combined >> 12) as usize & 0x3f]);
        if chunk.len() > 1 {
            out.push(ALPHABET[(combined >> 6) as usize & 0x3f]);
        } else {
            out.push(b'=');
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[combined as usize & 0x3f]);
        } else {
            out.push(b'=');
        }
    }
    out
}

/// The `trap 'rm -f "$tmp"' EXIT` of the slurp path.
#[derive(Default)]
struct Temporary {
    path: Option<Vec<u8>>,
}

impl Drop for Temporary {
    fn drop(&mut self) {
        if let Some(path) = &self.path {
            let _ = std::fs::remove_file(OsStr::from_bytes(path));
        }
    }
}
