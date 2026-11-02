//! In-process MPD stub for the controller tests.
//!
//! Mirrors the shape of the Python suite's `tests/fake_mpd.py`: a real TCP
//! server speaking enough of the wire protocol for the controller, with the
//! state the tests assert on (queue, transport, volume, modes, playlists, the
//! command log).

#![cfg(test)]

use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Mutex};
use std::thread;

#[derive(Debug, Clone, Default)]
pub struct StubSong {
    pub file: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub albumartist: String,
    pub genre: String,
    pub duration: String,
}

impl StubSong {
    pub fn new(file: &str, title: &str, artist: &str, album: &str) -> Self {
        StubSong {
            file: file.to_string(),
            title: title.to_string(),
            artist: artist.to_string(),
            album: album.to_string(),
            albumartist: String::new(),
            genre: String::new(),
            duration: "240".to_string(),
        }
    }

    pub fn artist(mut self, artist: &str) -> Self {
        self.artist = artist.to_string();
        self
    }

    pub fn album(mut self, album: &str) -> Self {
        self.album = album.to_string();
        self
    }

    pub fn genre(mut self, genre: &str) -> Self {
        self.genre = genre.to_string();
        self
    }

    pub fn albumartist(mut self, albumartist: &str) -> Self {
        self.albumartist = albumartist.to_string();
        self
    }

    fn field(&self, tag: &str) -> &str {
        match tag.to_ascii_lowercase().as_str() {
            "file" => &self.file,
            "title" => &self.title,
            "artist" => &self.artist,
            "album" => &self.album,
            "albumartist" => &self.albumartist,
            "genre" => &self.genre,
            "duration" => &self.duration,
            _ => "",
        }
    }

    fn matches(&self, tag: &str, needle: &str) -> bool {
        let needle = needle.to_lowercase();
        if tag.eq_ignore_ascii_case("any") {
            return ["file", "title", "artist", "album", "albumartist", "genre"]
                .iter()
                .any(|field| self.field(field).to_lowercase().contains(&needle));
        }
        self.field(tag).to_lowercase().contains(&needle)
    }

    fn protocol_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("file: {}", self.file)];
        for (tag, value) in [
            ("Title", &self.title),
            ("Artist", &self.artist),
            ("AlbumArtist", &self.albumartist),
            ("Album", &self.album),
            ("Genre", &self.genre),
            ("duration", &self.duration),
        ] {
            if !value.is_empty() {
                lines.push(format!("{tag}: {value}"));
            }
        }
        lines
    }
}

#[derive(Debug, Default)]
pub struct StubState {
    pub library: Vec<StubSong>,
    pub queue: Vec<String>,
    pub state: String,
    pub position: usize,
    pub volume: i64,
    pub modes: Vec<(String, i64)>,
    pub playlists: Vec<(String, Vec<String>)>,
    pub updated: Vec<String>,
    pub commands: Vec<String>,
    /// When set, `status` (and `currentsong`) answer with this ACK instead.
    pub fail_with: Option<String>,
}

impl StubState {
    fn song_for(&self, file: &str) -> Option<&StubSong> {
        self.library.iter().find(|song| song.file == file)
    }

    fn current(&self) -> Option<&StubSong> {
        self.queue
            .get(self.position)
            .and_then(|file| self.song_for(file))
    }

    fn mode(&self, name: &str) -> i64 {
        self.modes
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| *value)
            .unwrap_or(0)
    }

    fn set_mode(&mut self, name: &str, value: i64) {
        if let Some(entry) = self.modes.iter_mut().find(|(key, _)| key == name) {
            entry.1 = value;
        } else {
            self.modes.push((name.to_string(), value));
        }
    }
}

/// A fake MPD listening on loopback; the handle owns the state.
pub struct FakeMpd {
    pub port: u16,
    state: Arc<Mutex<StubState>>,
}

impl FakeMpd {
    pub fn start() -> FakeMpd {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let port = listener.local_addr().expect("addr").port();
        let state = Arc::new(Mutex::new(StubState {
            state: "stop".to_string(),
            volume: 50,
            ..StubState::default()
        }));
        let shared = Arc::clone(&state);
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let shared = Arc::clone(&shared);
                thread::spawn(move || serve(stream, shared));
            }
        });
        FakeMpd { port, state }
    }

    pub fn library(&self, songs: Vec<StubSong>) {
        self.state.lock().unwrap().library = songs;
    }

    pub fn queue(&self) -> Vec<String> {
        self.state.lock().unwrap().queue.clone()
    }

    pub fn state(&self) -> String {
        self.state.lock().unwrap().state.clone()
    }

    pub fn position(&self) -> usize {
        self.state.lock().unwrap().position
    }

    pub fn volume(&self) -> i64 {
        self.state.lock().unwrap().volume
    }

    pub fn mode(&self, name: &str) -> i64 {
        self.state.lock().unwrap().mode(name)
    }

    pub fn commands(&self) -> Vec<String> {
        self.state.lock().unwrap().commands.clone()
    }

    pub fn playlists(&self) -> Vec<(String, Vec<String>)> {
        self.state.lock().unwrap().playlists.clone()
    }

    pub fn updated(&self) -> Vec<String> {
        self.state.lock().unwrap().updated.clone()
    }

    pub fn set_no_mixer(&self) {
        let mut state = self.state.lock().unwrap();
        state.volume = -1;
    }

    pub fn add_playlist(&self, name: &str, files: &[&str]) {
        let mut state = self.state.lock().unwrap();
        state.playlists.push((
            name.to_string(),
            files.iter().map(|file| file.to_string()).collect(),
        ));
    }
}

fn serve(stream: TcpStream, state: Arc<Mutex<StubState>>) {
    let mut writer = stream.try_clone().expect("clone stream");
    let mut reader = BufReader::new(stream);
    if writer.write_all(b"OK MPD 0.24.0\n").is_err() {
        return;
    }
    let mut line = String::new();
    loop {
        line.clear();
        match reader.read_line(&mut line) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        let command = line.trim_end_matches(['\r', '\n']).to_string();
        if command.is_empty() {
            continue;
        }
        let mut state = state.lock().unwrap();
        state.commands.push(command.clone());
        // Command lists: run each entry, answer `list_OK` per success and a
        // final `OK` (a failure aborts the list with its ACK, like MPD).
        if command == "command_list_begin" {
            let mut payload = String::new();
            let mut aborted = false;
            loop {
                let mut entry = String::new();
                match reader.read_line(&mut entry) {
                    Ok(0) | Err(_) => return,
                    Ok(_) => {}
                }
                let entry = entry.trim_end_matches(['\r', '\n']).to_string();
                if entry.is_empty() {
                    continue;
                }
                if entry == "command_list_end" {
                    break;
                }
                state.commands.push(entry.clone());
                let (body, ack) = answer(&entry, &mut state);
                if !body.is_empty() {
                    payload.push_str(&body.join("\n"));
                    payload.push('\n');
                }
                if let Some(message) = ack {
                    payload.push_str(&message);
                    payload.push('\n');
                    aborted = true;
                    break;
                }
                payload.push_str("list_OK\n");
            }
            if !aborted {
                payload.push_str("OK\n");
            }
            if writer.write_all(payload.as_bytes()).is_err() {
                return;
            }
            continue;
        }
        let (body, ack) = answer(&command, &mut state);
        let mut payload = body.join("\n");
        if !payload.is_empty() {
            payload.push('\n');
        }
        if let Some(message) = ack {
            payload.push_str(&message);
            payload.push('\n');
        } else {
            payload.push_str("OK\n");
        }
        if writer.write_all(payload.as_bytes()).is_err() {
            return;
        }
    }
}

/// Split `search Artist "The Mantle"` into words, honouring quotes.
fn split_command(command: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let mut quoted = false;
    for ch in command.chars() {
        match ch {
            '"' => quoted = !quoted,
            ' ' if !quoted => {
                if !current.is_empty() {
                    words.push(std::mem::take(&mut current));
                }
            }
            other => current.push(other),
        }
    }
    if !current.is_empty() {
        words.push(current);
    }
    words
}

fn answer(command: &str, state: &mut StubState) -> (Vec<String>, Option<String>) {
    let words = split_command(command);
    let name = words.first().map(String::as_str).unwrap_or("");
    let arg = |index: usize| words.get(index).cloned().unwrap_or_default();
    let ack = |code: i64, message: &str, command: &str| {
        Some(format!("ACK [{code}@0] {{{command}}} {message}"))
    };
    if let Some(failure) = &state.fail_with {
        if matches!(name, "status" | "currentsong") {
            return (Vec::new(), ack(5, failure, name));
        }
    }
    match name {
        "ping" => (Vec::new(), None),
        "status" => {
            let mut lines = vec![format!("volume: {}", state.volume)];
            lines.push(format!("state: {}", state.state));
            lines.push(format!("playlistlength: {}", state.queue.len()));
            lines.push(format!("song: {}", state.position));
            for mode in ["random", "repeat", "single", "consume"] {
                lines.push(format!("{mode}: {}", state.mode(mode)));
            }
            (lines, None)
        }
        "currentsong" => match state.current() {
            Some(song) => (song.protocol_lines(), None),
            None => (Vec::new(), None),
        },
        "playlistinfo" => {
            let mut lines = Vec::new();
            let requested = words.get(1).and_then(|pos| pos.parse::<usize>().ok());
            for (index, file) in state.queue.clone().iter().enumerate() {
                if let Some(wanted) = requested {
                    if wanted != index {
                        continue;
                    }
                }
                if let Some(song) = state.song_for(file) {
                    lines.push(format!("Pos: {index}"));
                    lines.extend(song.protocol_lines());
                }
            }
            (lines, None)
        }
        "add" => {
            let file = arg(1);
            if state.song_for(&file).is_none() {
                return (Vec::new(), ack(50, "no such song", "add"));
            }
            state.queue.push(file);
            (Vec::new(), None)
        }
        "play" => {
            if let Some(position) = words.get(1).and_then(|pos| pos.parse().ok()) {
                state.position = position;
            }
            if state.queue.is_empty() {
                return (Vec::new(), ack(50, "no such song", "play"));
            }
            state.state = "play".to_string();
            (Vec::new(), None)
        }
        "pause" => {
            if state.queue.is_empty() {
                return (Vec::new(), ack(50, "no such song", "pause"));
            }
            if arg(1) == "1" {
                state.state = "pause".to_string();
            } else {
                state.state = "play".to_string();
            }
            (Vec::new(), None)
        }
        "stop" => {
            state.state = "stop".to_string();
            (Vec::new(), None)
        }
        "next" => {
            if state.queue.is_empty() {
                return (Vec::new(), ack(50, "no such song", "next"));
            }
            if state.position + 1 < state.queue.len() {
                state.position += 1;
            }
            (Vec::new(), None)
        }
        "previous" => {
            if state.queue.is_empty() {
                return (Vec::new(), ack(50, "no such song", "previous"));
            }
            state.position = state.position.saturating_sub(1);
            (Vec::new(), None)
        }
        "setvol" => {
            let volume = arg(1).parse::<i64>().unwrap_or(0);
            if state.volume >= 0 {
                state.volume = volume.clamp(0, 100);
            }
            (Vec::new(), None)
        }
        "seekcur" => {
            if state.queue.is_empty() {
                return (Vec::new(), ack(50, "no such song", "seekcur"));
            }
            (Vec::new(), None)
        }
        "random" | "repeat" | "single" | "consume" => {
            let value = arg(1).parse::<i64>().unwrap_or(0);
            state.set_mode(name, value);
            (Vec::new(), None)
        }
        "clear" => {
            state.queue.clear();
            state.position = 0;
            if state.state != "stop" {
                state.state = "stop".to_string();
            }
            (Vec::new(), None)
        }
        "search" | "find" => {
            let tag = arg(1);
            let needle = arg(2);
            let mut lines = Vec::new();
            for song in state.library.clone() {
                if song.matches(&tag, &needle) {
                    lines.extend(song.protocol_lines());
                }
            }
            (lines, None)
        }
        "listplaylists" => (
            state
                .playlists
                .iter()
                .map(|(name, _)| format!("playlist: {name}"))
                .collect(),
            None,
        ),
        "listplaylistinfo" => {
            let name = arg(1);
            match state.playlists.iter().find(|(key, _)| *key == name) {
                Some((_, files)) => {
                    let mut lines = Vec::new();
                    for file in files {
                        if let Some(song) = state.song_for(file) {
                            lines.extend(song.protocol_lines());
                        }
                    }
                    (lines, None)
                }
                None => (Vec::new(), ack(50, "no such playlist", "listplaylistinfo")),
            }
        }
        "load" => {
            let name = arg(1);
            match state.playlists.iter().find(|(key, _)| *key == name) {
                Some((_, files)) => {
                    state.queue.extend(files.iter().cloned());
                    (Vec::new(), None)
                }
                None => (Vec::new(), ack(50, "no such playlist", "load")),
            }
        }
        "save" => {
            let name = arg(1);
            if state.playlists.iter().any(|(key, _)| *key == name) {
                return (Vec::new(), ack(56, "playlist already exists", "save"));
            }
            state.playlists.push((name, state.queue.clone()));
            (Vec::new(), None)
        }
        "rm" => {
            let name = arg(1);
            state.playlists.retain(|(key, _)| *key != name);
            (Vec::new(), None)
        }
        "update" => {
            state.updated.push(arg(1));
            (Vec::new(), None)
        }
        "crossfade" => (Vec::new(), None),
        "password" => (Vec::new(), None),
        other => (
            Vec::new(),
            ack(5, &format!("unknown command \"{other}\""), other),
        ),
    }
}
