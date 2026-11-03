//! Rust port of `packages/local-bin/bin/clip`.
//!
//! Clipboard helper over cliphist/clipcat, vicinae's dmenu and wl-clipboard.
//! The shell original is a thin pipeline wrapper, so every tool stays a
//! subprocess with the identical argv; the option parsing, the `awk -F:`
//! selection index, the `tr -d '\n'` filter and the `cd` handling are native.
//! Note that `rg -E` is kept verbatim (ripgrep reads `-E` as `--encoding`), so
//! the URL picker keeps failing the way it does in the shell.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_desktop::env;
use local_bin_desktop::helptext::CLIP_HELP;
use local_bin_desktop::proc::{Cmd, Input, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let args: Vec<Vec<u8>> = arguments
        .map(|value| env::os_bytes(&value).to_vec())
        .collect();

    let first = args.first().map(Vec::as_slice).unwrap_or_default();
    if matches!(first, b"-h" | b"--help" | b"help") {
        env::out_str(CLIP_HELP);
        std::process::exit(0);
    }

    let code = match first {
        b"pipe" => clipboard_pipe(&program, &args[1..]),
        b"youtube-dw-list" => youtube_dw_list(&program),
        b"youtube-dw" => youtube_dw(&program),
        b"youtube-view" => youtube_view(&program),
        _ => clip_main(&program),
    };
    std::process::exit(code);
}

/// `USE_CLIPCAT=false` unless the environment sets a non-empty value.
fn use_clipcat() -> bool {
    env::var_nonempty("USE_CLIPCAT").as_deref() == Some(b"true")
}

fn clip_main(program: &[u8]) -> i32 {
    if use_clipcat() {
        let mut config = env::var_or_empty("HOME");
        config.extend_from_slice(b"/.config/clipcat/clipcat-menu.toml");
        return Cmd::new("clipcat-menu")
            .args(["-c"])
            .arg_bytes(&config)
            .diag(program, 91)
            .run()
            .code;
    }
    let listed = Cmd::new("cliphist")
        .arg("list")
        .stdout(Sink::Capture)
        .diag(program, 94)
        .run();
    let selected = Cmd::new("vicinae")
        .args(["dmenu", "-p", "clip ❯>"])
        .stdin(Input::Bytes(&listed.stdout))
        .stdout(Sink::Capture)
        .diag(program, 94)
        .run();
    let selection = text::strip_trailing_newlines(&selected.stdout).to_vec();
    if selection.is_empty() {
        return 0;
    }
    let index = first_field(&selection);
    let decoded = Cmd::new("cliphist")
        .args(["decode"])
        .arg_bytes(&index)
        .stdout(Sink::Capture)
        .diag(program, 97)
        .run();
    Cmd::new("wl-copy")
        .stdin(Input::Bytes(&decoded.stdout))
        .diag(program, 97)
        .run()
        .code
}

/// `clip pipe [-p|--paste] [-c|--command CMD] [--]`.
fn clipboard_pipe(program: &[u8], arguments: &[Vec<u8>]) -> i32 {
    let mut command: Vec<u8> = Vec::new();
    let mut paste = false;
    let mut index = 0;
    while index < arguments.len() {
        match arguments[index].as_slice() {
            b"--" => break,
            b"-p" | b"--paste" => {
                paste = true;
                index += 1;
            }
            b"-c" | b"-e" | b"--command" => {
                match arguments.get(index + 1) {
                    Some(value) if !value.is_empty() => {
                        command = value.clone();
                        index += 2;
                    }
                    _ => {
                        index += 1;
                        command = read_command(program);
                    }
                };
            }
            _ => {
                command = read_command(program);
                break;
            }
        }
    }
    if command.is_empty() {
        command = read_command(program);
    }

    if paste {
        send_key(program, b"c");
        let _ = Cmd::new("sleep").arg("0.05").diag(program, 70).run();
    }
    let pasted = Cmd::new("wl-paste")
        .stdout(Sink::Capture)
        .diag(program, 73)
        .run();
    let selection = text::strip_trailing_newlines(&pasted.stdout).to_vec();
    if selection.is_empty() && paste {
        env::err_str("no input, aborting...\n");
        return 1;
    }
    let transformed = Cmd::new("sh")
        .arg("-c")
        .arg_bytes(&command)
        .stdin(Input::Bytes(&selection))
        .stdout(Sink::Capture)
        .diag(program, 79)
        .run();
    let output = text::strip_trailing_newlines(&transformed.stdout).to_vec();
    let _ = Cmd::new("wl-copy")
        .stdin(Input::Bytes(&output))
        .diag(program, 80)
        .run();
    if paste {
        let _ = Cmd::new("sleep").arg("0.05").diag(program, 83).run();
        send_key(program, b"v");
    }
    0
}

/// `printf '%s\n' sort tac | vicinae dmenu -p '❯>'`.
fn read_command(program: &[u8]) -> Vec<u8> {
    let listed = Cmd::new("vicinae")
        .args(["dmenu", "-p", "❯>"])
        .stdin(Input::Bytes(b"sort\ntac\n"))
        .stdout(Sink::Capture)
        .diag(program, 30)
        .run();
    text::strip_trailing_newlines(&listed.stdout).to_vec()
}

/// `wtype -M ctrl -k c|v -m ctrl`.
fn send_key(program: &[u8], key: &[u8]) {
    match key {
        b"c" => {
            let _ = Cmd::new("wtype")
                .args(["-M", "ctrl", "-k", "c", "-m", "ctrl"])
                .diag(program, 36)
                .run();
        }
        b"v" => {
            let _ = Cmd::new("wtype")
                .args(["-M", "ctrl", "-k", "v", "-m", "ctrl"])
                .diag(program, 37)
                .run();
        }
        _ => {}
    }
}

/// `awk -F ':' '{print $1}'`, applied to every line of the selection.
fn first_field(selection: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    for (index, line) in selection.split(|byte| *byte == b'\n').enumerate() {
        if index > 0 {
            result.push(b'\n');
        }
        match line.iter().position(|byte| *byte == b':') {
            Some(position) => result.extend_from_slice(&line[..position]),
            None => result.extend_from_slice(line),
        }
    }
    result
}

/// `/"${XDG_VIDEOS_DIR:-$HOME/vid}"/new`.
fn videos_new() -> Vec<u8> {
    let mut directory = match env::var_nonempty("XDG_VIDEOS_DIR") {
        Some(value) => value,
        None => {
            let mut value = env::var_or_empty("HOME");
            value.extend_from_slice(b"/vid");
            value
        }
    };
    directory.extend_from_slice(b"/new");
    directory
}

/// `youtube-dw-list`: download the URL picked from the clipboard history.
fn youtube_dw_list(program: &[u8]) -> i32 {
    let directory = videos_new();
    if !Path::new(OsStr::from_bytes(&directory)).is_dir() {
        env::err(&env::cd_message(program, 125, &directory));
        return 1;
    }
    let url = youtube_url(program).unwrap_or_default();
    Cmd::new("yt-dlp")
        .args(["-f", "(bestvideo+bestaudio/best)"])
        .arg_bytes(&url)
        .current_dir(env::os_string(&directory))
        .diag(program, 24)
        .run()
        .code
}

/// `youtube-dw`: download whatever URL is in the clipboard.
fn youtube_dw(program: &[u8]) -> i32 {
    let directory = videos_new();
    if !Path::new(OsStr::from_bytes(&directory)).is_dir() {
        env::err(&env::cd_message(program, 126, &directory));
        return 1;
    }
    let pasted = Cmd::new("wl-paste")
        .stdout(Sink::Capture)
        .diag(program, 126)
        .run();
    let url = text::strip_trailing_newlines(&pasted.stdout).to_vec();
    Cmd::new("yt-dlp")
        .args(["-f", "(bestvideo+bestaudio/best)"])
        .arg_bytes(&url)
        .current_dir(env::os_string(&directory))
        .diag(program, 24)
        .run()
        .code
}

/// `youtube-view`: open the yt scratchpad and paste the selection.
fn youtube_view(program: &[u8]) -> i32 {
    let _ = Cmd::new("negwm")
        .args(["send", "scratchpad toggle youtube"])
        .diag(program, 102)
        .run();
    let _ = Cmd::new("sleep").arg("1s").diag(program, 103).run();
    // `echo "$@"` with the single argument "clip".
    let _ = Cmd::new("wl-copy")
        .stdin(Input::Bytes(b"clip\n"))
        .diag(program, 104)
        .run();
    Cmd::new("wtype")
        .args(["-M", "ctrl", "-k", "v", "-m", "ctrl"])
        .diag(program, 105)
        .run()
        .code
}

/// `youtube_url`: pick a video URL from the clipboard history and print it
/// without newlines. `None` is the function's `exit 1`.
fn youtube_url(program: &[u8]) -> Option<Vec<u8>> {
    // The original pattern reaches rg/grep with the double backslash intact.
    let pattern = b"https.*(youtube|vimeo)\\\\.com";
    let listed = Cmd::new("cliphist").arg("list").stdout(Sink::Capture);
    let (listed, filter_line) = if env::which(b"rg") {
        (listed.diag(program, 110).run(), 110)
    } else {
        (listed.diag(program, 113).run(), 113)
    };
    let filter = if env::which(b"rg") { "rg" } else { "grep" };
    let filtered = Cmd::new(filter)
        .args(["-E"])
        .arg_bytes(pattern)
        .stdin(Input::Bytes(&listed.stdout))
        .stdout(Sink::Capture)
        .diag(program, filter_line)
        .run();
    let selected = Cmd::new("vicinae")
        .args(["dmenu", "-p", "youtube ❯>"])
        .stdin(Input::Bytes(&filtered.stdout))
        .stdout(Sink::Capture)
        .diag(program, filter_line + 1)
        .run();
    let selection = text::strip_trailing_newlines(&selected.stdout).to_vec();
    if selection.is_empty() {
        return None;
    }
    let index = first_field(&selection);
    let decoded = Cmd::new("cliphist")
        .args(["decode"])
        .arg_bytes(&index)
        .stdout(Sink::Capture)
        .diag(program, 118)
        .run();
    Some(text::remove_newlines(&decoded.stdout))
}
