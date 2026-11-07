//! main-menu: vicinae dmenu-driven helper actions for music/clipboard/network.
//!
//! Port of `packages/local-bin/bin/main-menu` (POSIX sh). The menu names, the
//! action bodies and the argv of every external helper are the original ones:
//! `mpc --format`, `wl-copy`, `wl-paste`, `trans -brief :ru`, `notify-send -t N`,
//! `nc termbin.com 9999`, `play-sound` and `vicinae dmenu -p '❯>'`. Song
//! metadata comes from one MPD format string, so the menu needs no
//! player-specific client.

use std::io::{Read, Write};
use std::process::{Command, Stdio};

use local_bin_system as sh;

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

/// One field per line; `%name%` is the stream name MPD reports for radio.
const SONG_FORMAT: &str = "%artist%\n%title%\n%album%\n%name%\n%file%";

#[derive(Default)]
struct Song {
    artist: String,
    title: String,
    album: String,
    name: String,
    file: String,
}

/// `mpc --format FORMAT current`: no output means nothing is playing. One
/// trailing newline (mpc terminates every line) is stripped before the split;
/// a song with no tags therefore still yields five empty fields.
fn song() -> Option<Song> {
    let output = sh::capture("mpc", &["--format", SONG_FORMAT, "current"], true)?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    if stdout.is_empty() {
        return None;
    }
    let text = stdout.strip_suffix('\n').unwrap_or(&stdout);
    let mut fields = text.split('\n').map(str::to_string);
    Some(Song {
        artist: fields.next().unwrap_or_default(),
        title: fields.next().unwrap_or_default(),
        album: fields.next().unwrap_or_default(),
        name: fields.next().unwrap_or_default(),
        file: fields.next().unwrap_or_default(),
    })
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
    let Some(song) = song() else {
        // Nothing playing: an empty clipboard, like the original's empty
        // jq output. wl-copy still runs with an empty stdin.
        clipboard(b"");
        return;
    };
    let text = if !song.artist.is_empty() && !song.title.is_empty() {
        format!("{} - {}", song.artist, song.title)
    } else if !song.title.is_empty() {
        song.title
    } else {
        song.name
    };
    clipboard(format!("{text}\n").as_bytes());
}

fn album_copy() {
    match song() {
        Some(song) if !song.album.is_empty() => clipboard(format!("{}\n", song.album).as_bytes()),
        _ => clipboard(b""),
    }
}

fn artist_copy() {
    match song() {
        Some(song) if !song.artist.is_empty() => clipboard(format!("{}\n", song.artist).as_bytes()),
        _ => clipboard(b""),
    }
}

fn path_copy() {
    let music_dir = sh::env_or("XDG_MUSIC_DIR", &format!("{}/Music", sh::home()));
    if let Some(song) = song() {
        if !song.file.is_empty() {
            clipboard(format!("{music_dir}/{}\n", song.file).as_bytes());
        }
    }
}

fn pipewire_output() {
    run_ignored("mpc", &["pause"]);
    run_ignored("mpc", &["enable", "PipeWire"]);
    run_ignored("mpc", &["disable", DAC_NAME]);
    run_ignored("mpc", &["play"]);
}

fn alsa_output() {
    run_ignored("mpc", &["pause"]);
    run_ignored("mpc", &["enable", DAC_NAME]);
    run_ignored("mpc", &["disable", "PipeWire"]);
    run_ignored("mpc", &["play"]);
    run_ignored("sleep", &["5s"]);
    run_ignored("mpc", &["play"]);
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
