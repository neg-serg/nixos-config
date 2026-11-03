//! main-menu: vicinae dmenu-driven helper actions for music/clipboard/network.
//!
//! Port of `packages/local-bin/bin/main-menu` (POSIX sh). The menu names, the
//! action bodies and the argv of every external helper are the original ones:
//! `rmpc song`, `wl-copy`, `wl-paste`, `trans -brief :ru`, `notify-send -t N`,
//! `nc termbin.com 9999`, `play-sound`, the `rmpc-*output` switches and
//! `vicinae dmenu -p '❯>'`. JSON from `rmpc song` is parsed natively with jq's
//! `// empty` and string-interpolation semantics.

use std::io::{Read, Write};
use std::process::{Command, Stdio};

use local_bin_system as sh;
use serde_json::Value;

const MENU: [&str; 8] = [
    "title_copy",
    "artist_copy",
    "album_copy",
    "path_copy",
    "pipewire_output",
    "alsa_output",
    "translate",
    "termbin",
];

const DAC_NAME: &str = "RME HDSPe AIO";

fn song_json() -> Option<Value> {
    let output = sh::capture("rmpc", &["song"], true)?;
    serde_json::from_slice(&output.stdout).ok()
}

fn song_field(document: &Option<Value>, path: &[&str]) -> Result<Option<String>, ()> {
    let Some(document) = document else {
        return Ok(None);
    };
    let value = sh::jq_index_chain(document, path)?;
    Ok(sh::jq_alt_empty(&value))
}

/// jq's `tostring` for the string interpolation in `title_copy`.
fn jq_tostring(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => "null".to_string(),
        Value::Bool(true) => "true".to_string(),
        Value::Bool(false) => "false".to_string(),
        Value::Number(_) => sh::jq_render(value),
        other => serde_json::to_string(other).unwrap_or_default(),
    }
}

fn jq_truthy(value: &Value) -> bool {
    !matches!(value, Value::Null | Value::Bool(false))
}

fn clipboard(bytes: &[u8]) {
    let mut child = match Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return,
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(bytes);
    }
    let _ = child.wait();
}

fn capture_with_stdin(program: &str, arguments: &[&str], input: &[u8]) -> Vec<u8> {
    let mut child = match Command::new(program)
        .args(arguments)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return Vec::new(),
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input);
    }
    let mut output = Vec::new();
    if let Some(mut stdout) = child.stdout.take() {
        let _ = stdout.read_to_end(&mut output);
    }
    let _ = child.wait();
    output
}

fn capture_stdout(program: &str, arguments: &[&str]) -> Vec<u8> {
    capture_with_stdin(program, arguments, &[])
}

fn run_ignored(program: &str, arguments: &[&str]) {
    let _ = Command::new(program).args(arguments).status();
}

fn title_copy() {
    let Some(document) = song_json() else {
        // jq fails on the unreadable/absent JSON and emits nothing; wl-copy
        // still runs with an empty stdin.
        clipboard(b"");
        return;
    };
    let Ok(metadata) = sh::jq_index(&document, "metadata") else {
        clipboard(b"");
        return;
    };
    let artist = sh::jq_index(&metadata, "artist").unwrap_or(Value::Null);
    let title = sh::jq_index(&metadata, "title").unwrap_or(Value::Null);
    let text = if jq_truthy(&artist) && jq_truthy(&title) {
        format!("{} - {}", jq_tostring(&artist), jq_tostring(&title))
    } else if jq_truthy(&title) {
        jq_tostring(&title)
    } else {
        let name = sh::jq_index(&metadata, "name").unwrap_or(Value::Null);
        if jq_truthy(&name) {
            jq_tostring(&name)
        } else {
            String::new()
        }
    };
    clipboard(format!("{text}\n").as_bytes());
}

fn album_copy() {
    let document = song_json();
    match song_field(&document, &["metadata", "album"]) {
        Ok(Some(text)) => clipboard(format!("{text}\n").as_bytes()),
        _ => clipboard(b""),
    }
}

fn artist_copy() {
    let document = song_json();
    match song_field(&document, &["metadata", "artist"]) {
        Ok(Some(text)) => clipboard(format!("{text}\n").as_bytes()),
        _ => clipboard(b""),
    }
}

fn path_copy() {
    let music_dir = sh::env_or("XDG_MUSIC_DIR", &format!("{}/Music", sh::home()));
    let document = song_json();
    if let Ok(Some(file)) = song_field(&document, &["file"]) {
        if !file.is_empty() {
            clipboard(format!("{music_dir}/{file}\n").as_bytes());
        }
    }
}

fn pipewire_output() {
    run_ignored("rmpc-pause", &[]);
    run_ignored("rmpc-enableoutput", &["PipeWire"]);
    run_ignored("rmpc-disableoutput", &[DAC_NAME]);
    run_ignored("rmpc-play", &[]);
}

fn alsa_output() {
    run_ignored("rmpc-pause", &[]);
    run_ignored("rmpc-enableoutput", &[DAC_NAME]);
    run_ignored("rmpc-disableoutput", &["PipeWire"]);
    run_ignored("rmpc-play", &[]);
    run_ignored("sleep", &["5s"]);
    run_ignored("rmpc-play", &[]);
}

fn translate() {
    let text = String::from_utf8_lossy(&capture_stdout("wl-paste", &[]))
        .trim_end_matches('\n')
        .to_string();
    let translated = String::from_utf8_lossy(&capture_stdout("trans", &["-brief", ":ru", &text]))
        .trim_end_matches('\n')
        .to_string();
    let timeout = format!("{}", text.chars().count() * 150);
    run_ignored("notify-send", &["-t", &timeout, &translated]);
    run_ignored("play-sound", &["cyclist.ogg"]);
}

fn termbin() {
    let pasted = capture_stdout("wl-paste", &[]);
    let url = String::from_utf8_lossy(&capture_with_stdin("nc", &["termbin.com", "9999"], &pasted))
        .trim_end_matches('\n')
        .to_string();
    clipboard(format!("{url}\n").as_bytes());
    run_ignored("notify-send", &[&format!("{url} copied to clipboard")]);
    run_ignored("play-sound", &["direct.ogg"]);
}

fn run_action(name: &str) {
    match name {
        "title_copy" => title_copy(),
        "artist_copy" => artist_copy(),
        "album_copy" => album_copy(),
        "path_copy" => path_copy(),
        "pipewire_output" => pipewire_output(),
        "alsa_output" => alsa_output(),
        "translate" => translate(),
        "termbin" => termbin(),
        _ => {}
    }
}

fn generate_menu() {
    for entry in MENU {
        sh::out_str_line(entry);
    }
}

/// `generate_menu | vicinae dmenu -p '❯>' | handler`: every selected line that
/// names an action runs it; unknown and empty lines are ignored.
fn dmenu_mode() {
    let mut input = String::new();
    for entry in MENU {
        input.push_str(entry);
        input.push('\n');
    }
    let mut child = match Command::new("vicinae")
        .args(["dmenu", "-p", "❯>"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return,
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }
    let mut output = Vec::new();
    if let Some(mut stdout) = child.stdout.take() {
        let _ = stdout.read_to_end(&mut output);
    }
    let _ = child.wait();
    let text = String::from_utf8_lossy(&output);
    // `while IFS= read -r line` does not run its body for a final line that
    // has no newline, so only terminated lines reach the handler.
    for segment in text.split_inclusive('\n') {
        let Some(line) = segment.strip_suffix('\n') else {
            continue;
        };
        if line.is_empty() {
            continue;
        }
        if MENU.contains(&line) {
            run_action(line);
        }
    }
}

fn main() {
    let arguments = sh::args();
    let first = arguments.first().map(String::as_str).unwrap_or("");
    match first {
        "--list" => generate_menu(),
        "--run" => {
            let action = arguments.get(1).map(String::as_str).unwrap_or("");
            if action.is_empty() {
                sh::err_line("main-menu: --run needs an action name");
                std::process::exit(2);
            }
            if !MENU.contains(&action) {
                sh::err_line(&format!("main-menu: unknown action: {action}"));
                std::process::exit(2);
            }
            run_action(action);
        }
        "--help" | "-h" => sh::out_str_line("usage: main-menu [--list | --run NAME]"),
        _ => dmenu_mode(),
    }
}
