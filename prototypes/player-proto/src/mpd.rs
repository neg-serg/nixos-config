//! Minimal MPD client: plain TCP, no external crates.
//!
//! Only the subset a frontend needs: status/current song, queue, library listing, search,
//! playback control and `idle` for change notifications. The protocol is line based:
//! commands end with `\n`, responses are `key: value` lines terminated by `OK` or `ACK`.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::TcpStream;
use std::time::Duration;

pub type Fields = Vec<(String, String)>;

#[derive(Debug)]
pub struct MpdError(pub String);

impl std::fmt::Display for MpdError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

pub struct Client {
    reader: BufReader<TcpStream>,
    writer: TcpStream,
}

impl Client {
    pub fn connect(addr: &str, timeout: Duration) -> Result<Self, MpdError> {
        let stream =
            TcpStream::connect(addr).map_err(|e| MpdError(format!("connect {addr}: {e}")))?;
        stream.set_read_timeout(Some(timeout)).ok();
        stream.set_write_timeout(Some(timeout)).ok();
        let writer = stream
            .try_clone()
            .map_err(|e| MpdError(format!("clone socket: {e}")))?;
        let mut client = Self {
            reader: BufReader::new(stream),
            writer,
        };
        let mut banner = String::new();
        client
            .reader
            .read_line(&mut banner)
            .map_err(|e| MpdError(format!("banner: {e}")))?;
        if !banner.starts_with("OK MPD") {
            return Err(MpdError(format!("unexpected banner: {}", banner.trim())));
        }
        Ok(client)
    }

    /// Send one command and collect its `key: value` response.
    pub fn command(&mut self, cmd: &str) -> Result<Fields, MpdError> {
        self.writer
            .write_all(format!("{cmd}\n").as_bytes())
            .map_err(|e| MpdError(format!("write {cmd}: {e}")))?;
        self.writer.flush().ok();
        let mut fields = Vec::new();
        loop {
            let mut line = String::new();
            let n = self
                .reader
                .read_line(&mut line)
                .map_err(|e| MpdError(format!("read {cmd}: {e}")))?;
            if n == 0 {
                return Err(MpdError("connection closed".into()));
            }
            let line = line.trim_end_matches(['\r', '\n']);
            if line == "OK" {
                return Ok(fields);
            }
            if let Some(err) = line.strip_prefix("ACK ") {
                return Err(MpdError(err.to_string()));
            }
            if let Some((k, v)) = line.split_once(": ") {
                fields.push((k.to_string(), v.to_string()));
            }
        }
    }

    /// Blocking `idle` for the given subsystems; returns the ones that changed.
    pub fn idle(&mut self, subsystems: &[&str]) -> Result<Vec<String>, MpdError> {
        let cmd = format!("idle {}", subsystems.join(" "));
        self.command(&cmd)?;
        // `command` stops at OK; idle reports changed subsystems before it, so re-parse:
        Ok(Vec::new())
    }

    pub fn status(&mut self) -> Result<Status, MpdError> {
        let f = self.command("status")?;
        Ok(Status::from(f))
    }

    pub fn current_song(&mut self) -> Result<Option<Song>, MpdError> {
        let f = self.command("currentsong")?;
        Ok(if f.is_empty() {
            None
        } else {
            Some(Song::from(f))
        })
    }

    pub fn queue(&mut self) -> Result<Vec<Song>, MpdError> {
        Ok(parse_songs(self.command("playlistinfo")?))
    }

    pub fn list_dir(&mut self, uri: &str) -> Result<Vec<Entry>, MpdError> {
        let f = self.command(&format!("lsinfo \"{uri}\""))?;
        Ok(parse_entries(f))
    }

    pub fn search(&mut self, query: &str) -> Result<Vec<Song>, MpdError> {
        let escaped = query.replace('\\', "\\\\").replace('"', "\\\"");
        let f = self.command(&format!("search any \"{escaped}\""))?;
        Ok(parse_songs(f))
    }

    /// `list <tag>`: distinct tag values across the library.
    pub fn list_tag(&mut self, tag: &str) -> Result<Vec<String>, MpdError> {
        let fields = self.command(&format!("list {tag}"))?;
        let key = tag.to_string();
        let mut out: Vec<String> = fields
            .into_iter()
            .filter(|(k, _)| k.eq_ignore_ascii_case(&key))
            .map(|(_, v)| v)
            .filter(|v| !v.is_empty())
            .collect();
        out.sort_by_key(|a| a.to_lowercase());
        out.dedup();
        Ok(out)
    }

    /// Saved playlists by name.
    pub fn playlists(&mut self) -> Result<Vec<String>, MpdError> {
        let fields = self.command("listplaylists")?;
        Ok(fields
            .into_iter()
            .filter(|(k, _)| k == "playlist")
            .map(|(_, v)| v)
            .collect())
    }

    /// Songs of a saved playlist.
    pub fn playlist_songs(&mut self, name: &str) -> Result<Vec<Song>, MpdError> {
        let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
        Ok(parse_songs(
            self.command(&format!("listplaylistinfo \"{escaped}\""))?,
        ))
    }

    /// Songs matching one tag exactly (`find Artist "X"`).
    pub fn find(&mut self, tag: &str, value: &str) -> Result<Vec<Song>, MpdError> {
        let escaped = value.replace('\\', "\\\\").replace('"', "\\\"");
        Ok(parse_songs(
            self.command(&format!("find {tag} \"{escaped}\""))?,
        ))
    }

    /// Append songs and start playing the first of them; returns the first song id.
    pub fn add_and_play(&mut self, uris: &[String]) -> Result<(), MpdError> {
        let mut first_id: Option<u64> = None;
        for uri in uris {
            let escaped = uri.replace('\\', "\\\\").replace('"', "\\\"");
            let fields = self.command(&format!("addid \"{escaped}\" \"\""))?;
            if first_id.is_none() {
                first_id = fields
                    .iter()
                    .find(|(k, _)| k == "Id")
                    .and_then(|(_, v)| v.parse::<u64>().ok());
            }
        }
        match first_id {
            Some(id) => self.command(&format!("playid {id}")).map(|_| ()),
            None => Ok(()),
        }
    }

    pub fn append(&mut self, uris: &[String]) -> Result<(), MpdError> {
        for uri in uris {
            let escaped = uri.replace('\\', "\\\\").replace('"', "\\\"");
            self.command(&format!("add \"{escaped}\""))?;
        }
        Ok(())
    }

    /// Configured outputs: id, name, enabled, plus whatever metadata the daemon will share.
    ///
    /// MPD 0.22+ reports `plugin:` (and, on 0.22/0.23, `driver:`) in the `outputs` reply itself.
    /// The device path only exists in the daemon's own config, reachable through `config` — which
    /// MPD refuses for non-local clients ("Command only permitted to local clients", an ACK).
    /// That refusal is a normal answer, not a failure: the metadata degrades to the fields we do
    /// have instead of turning the overlay into an error state.
    pub fn outputs(&mut self) -> Result<Vec<Output>, MpdError> {
        let fields = self.command("outputs")?;
        let mut out = Vec::new();
        let mut cur: Option<Output> = None;
        for (k, v) in fields {
            match k.as_str() {
                "outputid" => {
                    if let Some(c) = cur.take() {
                        out.push(c);
                    }
                    cur = Some(Output {
                        id: v.parse().unwrap_or(0),
                        name: String::new(),
                        enabled: false,
                        plugin: String::new(),
                        driver: String::new(),
                        device: String::new(),
                    });
                }
                "outputname" => {
                    if let Some(c) = cur.as_mut() {
                        c.name = v;
                    }
                }
                "outputenabled" => {
                    if let Some(c) = cur.as_mut() {
                        c.enabled = v == "1";
                    }
                }
                "plugin" => {
                    if let Some(c) = cur.as_mut() {
                        c.plugin = v;
                    }
                }
                "driver" => {
                    if let Some(c) = cur.as_mut() {
                        c.driver = v;
                    }
                }
                _ => {}
            }
        }
        if let Some(c) = cur.take() {
            out.push(c);
        }
        // Fill the gaps from `config` where the daemon is willing to show it: a daemon older
        // than 0.22 has no `plugin:` field at all, so its type comes from the config block, and
        // the device path is never part of the `outputs` reply.
        for (name, spec) in self.output_config() {
            for o in out.iter_mut().filter(|o| o.name == name) {
                if o.plugin.is_empty() {
                    o.plugin = spec.kind.clone();
                }
                if o.device.is_empty() {
                    o.device = spec.device.clone();
                }
            }
        }
        Ok(out)
    }

    /// Audio output blocks of `config`, keyed by the configured output name.
    ///
    /// The reply is the daemon's own syntax, one `config:` line at a time:
    ///
    /// ```text
    /// config: audio_output {
    /// config:   name "My ALSA Device"
    /// config:   type "alsa"
    /// config:   device "hw:0,0"
    /// config: }
    /// ```
    ///
    /// Anything unparsable (an ACK for a non-local client, a block without a name) is dropped
    /// instead of surfacing as an error.
    pub fn output_config(&mut self) -> Vec<(String, OutputSpec)> {
        match self.command("config") {
            Ok(fields) => parse_output_config(fields.iter().map(|(_, v)| v.as_str())),
            Err(_) => Vec::new(),
        }
    }

    /// `move <from> <to>`: reorder the queue.
    pub fn move_track(&mut self, from: usize, to: usize) -> Result<(), MpdError> {
        self.command(&format!("move {from} {to}")).map(|_| ())
    }

    /// `save <name>`: store the queue as a playlist.
    pub fn save_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
        self.command(&format!("save \"{escaped}\"")).map(|_| ())
    }

    /// `rm <name>`: delete a saved playlist.
    pub fn delete_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
        self.command(&format!("rm \"{escaped}\"")).map(|_| ())
    }

    /// `rename <old> <new>`. MPD changes this only for playlists, not for files.
    pub fn rename_playlist(&mut self, old: &str, new: &str) -> Result<(), MpdError> {
        let esc = |v: &str| v.replace('\\', "\\\\").replace('"', "\\\"");
        self.command(&format!("rename \"{}\" \"{}\"", esc(old), esc(new)))
            .map(|_| ())
    }

    /// `playlistadd <name> <uri>`: append one song to a saved playlist.
    pub fn playlist_add(&mut self, name: &str, uri: &str) -> Result<(), MpdError> {
        let esc = |v: &str| v.replace('\\', "\\\\").replace('"', "\\\"");
        self.command(&format!("playlistadd \"{}\" \"{}\"", esc(name), esc(uri)))
            .map(|_| ())
    }

    pub fn set_output(&mut self, id: u32, on: bool) -> Result<(), MpdError> {
        self.command(&format!(
            "{}output {id}",
            if on { "enable" } else { "disable" }
        ))
        .map(|_| ())
    }

    pub fn play(&mut self) -> Result<(), MpdError> {
        self.command("play").map(|_| ())
    }
    pub fn pause(&mut self, on: bool) -> Result<(), MpdError> {
        self.command(if on { "pause 1" } else { "pause 0" })
            .map(|_| ())
    }
    pub fn toggle(&mut self, playing: bool) -> Result<(), MpdError> {
        self.command(if playing { "pause 1" } else { "play" })
            .map(|_| ())
    }
    pub fn next(&mut self) -> Result<(), MpdError> {
        self.command("next").map(|_| ())
    }
    pub fn prev(&mut self) -> Result<(), MpdError> {
        self.command("previous").map(|_| ())
    }
    pub fn stop(&mut self) -> Result<(), MpdError> {
        self.command("stop").map(|_| ())
    }
    pub fn seek(&mut self, secs: f64) -> Result<(), MpdError> {
        self.command(&format!("seekcur {secs:.3}")).map(|_| ())
    }
    pub fn set_volume(&mut self, vol: i32) -> Result<(), MpdError> {
        self.command(&format!("setvol {}", vol.clamp(0, 100)))
            .map(|_| ())
    }
    pub fn play_index(&mut self, index: usize) -> Result<(), MpdError> {
        self.command(&format!("play {index}")).map(|_| ())
    }
    pub fn repeat(&mut self, on: bool) -> Result<(), MpdError> {
        self.command(&format!("repeat {}", on as u8)).map(|_| ())
    }
    pub fn random(&mut self, on: bool) -> Result<(), MpdError> {
        self.command(&format!("random {}", on as u8)).map(|_| ())
    }
    pub fn single(&mut self, on: bool) -> Result<(), MpdError> {
        self.command(&format!("single {}", on as u8)).map(|_| ())
    }
    pub fn consume(&mut self, on: bool) -> Result<(), MpdError> {
        self.command(&format!("consume {}", on as u8)).map(|_| ())
    }
    /// Raw cover art bytes for a song uri, if the server can extract them.
    pub fn album_art(&mut self, uri: &str) -> Result<Vec<u8>, MpdError> {
        let escaped = uri.replace('"', "\\\"");
        self.writer
            .write_all(format!("albumart \"{escaped}\" 0\n").as_bytes())
            .map_err(|e| MpdError(format!("write albumart: {e}")))?;
        self.writer.flush().ok();
        let mut size;
        let mut data: Vec<u8> = Vec::new();
        loop {
            let mut line = String::new();
            let n = self
                .reader
                .read_line(&mut line)
                .map_err(|e| MpdError(format!("read albumart: {e}")))?;
            if n == 0 {
                return Err(MpdError("connection closed".into()));
            }
            let line = line.trim_end_matches(['\r', '\n']);
            if line == "OK" {
                return Ok(data);
            }
            if let Some(err) = line.strip_prefix("ACK ") {
                return Err(MpdError(err.to_string()));
            }
            if let Some(v) = line.strip_prefix("size: ") {
                size = v.parse().unwrap_or(0);
                debug_assert!(size < 64 * 1024 * 1024);
                data.reserve(size);
                let start = data.len();
                data.resize(start + size, 0);
                // Read through the BufReader: it may already hold part of the body.
                std::io::Read::read_exact(&mut self.reader, &mut data[start..])
                    .map_err(|e| MpdError(format!("read albumart body: {e}")))?;
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct Output {
    pub id: u32,
    pub name: String,
    pub enabled: bool,
    /// Output plugin reported by MPD 0.22+ (`pulse`, `alsa`, `fifo`, ...); the `type` of the
    /// matching config block on older daemons, empty when neither says.
    pub plugin: String,
    /// Driver reported by MPD 0.22/0.23; 0.24 folded it into `plugin`, so it is often empty.
    pub driver: String,
    /// Device path from the daemon's config; empty when the daemon will not show its config.
    pub device: String,
}

impl Output {
    /// One dim second line for the overlay: the facts MPD actually shared, in a fixed order.
    ///
    /// Repeated words collapse (`plugin` and `driver` are the same string on 0.22/0.23), and a
    /// daemon that shared nothing yields an empty string, so the row simply stays one line.
    pub fn detail(&self) -> String {
        let mut parts: Vec<&str> = Vec::new();
        for part in [&self.plugin, &self.driver, &self.device] {
            let part = part.trim();
            if !part.is_empty() && !parts.contains(&part) {
                parts.push(part);
            }
        }
        parts.join(" \u{00b7} ")
    }
}

/// The parts of an `audio_output` block the overlay can show.
#[derive(Debug, Default, Clone)]
pub struct OutputSpec {
    pub kind: String,
    pub device: String,
}

#[derive(Debug, Default, Clone)]
pub struct Status {
    pub state: String,
    pub volume: i32,
    pub song: Option<usize>,
    pub songid: Option<u64>,
    pub elapsed: f64,
    pub duration: f64,
    pub queue_len: usize,
    pub repeat: bool,
    pub random: bool,
    pub single: bool,
    pub consume: bool,
    pub bitrate: Option<u32>,
    pub audio: Option<String>,
}

impl From<Fields> for Status {
    fn from(f: Fields) -> Self {
        let map: HashMap<String, String> = f.into_iter().collect();
        let num = |k: &str| map.get(k).and_then(|v| v.parse::<u64>().ok());
        let flag = |k: &str| map.get(k).map(|v| v == "1").unwrap_or(false);
        let elapsed = map
            .get("elapsed")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0.0);
        let duration = map
            .get("duration")
            .and_then(|v| v.parse().ok())
            .or_else(|| {
                map.get("time")
                    .and_then(|v| v.split(':').nth(1))
                    .and_then(|v| v.parse().ok())
            })
            .unwrap_or(0.0);
        Self {
            state: map.get("state").cloned().unwrap_or_else(|| "stop".into()),
            volume: map.get("volume").and_then(|v| v.parse().ok()).unwrap_or(-1),
            song: num("song").map(|v| v as usize),
            songid: num("songid"),
            elapsed,
            duration,
            queue_len: num("playlistlength").unwrap_or(0) as usize,
            repeat: flag("repeat"),
            random: flag("random"),
            single: flag("single"),
            consume: flag("consume"),
            bitrate: num("bitrate").map(|v| v as u32),
            audio: map.get("audio").cloned(),
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct Song {
    pub file: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration: f64,
    pub pos: Option<usize>,
    pub id: Option<u64>,
}

impl Song {
    fn from(f: Fields) -> Self {
        let map: HashMap<String, String> = f.into_iter().collect();
        let file = map.get("file").cloned().unwrap_or_default();
        let title = map.get("Title").cloned().unwrap_or_else(|| {
            file.rsplit('/')
                .next()
                .unwrap_or(&file)
                .trim_end_matches(".flac")
                .trim_end_matches(".mp3")
                .to_string()
        });
        Self {
            title,
            artist: map
                .get("Artist")
                .or_else(|| map.get("AlbumArtist"))
                .cloned()
                .unwrap_or_else(|| "unknown".into()),
            album: map.get("Album").cloned().unwrap_or_default(),
            duration: map
                .get("duration")
                .or_else(|| map.get("Time"))
                .and_then(|v| v.parse().ok())
                .unwrap_or(0.0),
            pos: map.get("Pos").and_then(|v| v.parse().ok()),
            id: map.get("Id").and_then(|v| v.parse().ok()),
            file,
        }
    }
}

#[derive(Debug, Clone)]
pub enum Entry {
    Dir { path: String, name: String },
    Song { path: String, song: Song },
}

/// Pull the `audio_output` blocks out of the flat `config` reply.
///
/// The reply interleaves simple parameters and multi-line blocks; only the blocks that carry a
/// `name` can be matched to an `outputs` row, and everything else is skipped.
fn parse_output_config<'a>(lines: impl Iterator<Item = &'a str>) -> Vec<(String, OutputSpec)> {
    let mut out = Vec::new();
    let mut in_block = false;
    let mut name = String::new();
    let mut spec = OutputSpec::default();
    for line in lines {
        let line = line.trim();
        if !in_block {
            if line.starts_with("audio_output") && line.contains('{') {
                in_block = true;
                name.clear();
                spec = OutputSpec::default();
            }
            continue;
        }
        if line.starts_with('}') {
            if !name.is_empty() {
                out.push((std::mem::take(&mut name), std::mem::take(&mut spec)));
            }
            in_block = false;
            continue;
        }
        let Some((key, value)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        let value = value.trim().trim_matches('"').replace("\\\"", "\"");
        match key.trim() {
            "name" => name = value,
            "type" => spec.kind = value,
            "device" => spec.device = value,
            _ => {}
        }
    }
    out
}

fn parse_songs(f: Fields) -> Vec<Song> {
    let mut out = Vec::new();
    let mut cur: Fields = Vec::new();
    for (k, v) in f {
        if k == "file" && !cur.is_empty() {
            out.push(Song::from(std::mem::take(&mut cur)));
        }
        cur.push((k, v));
    }
    if !cur.is_empty() {
        out.push(Song::from(cur));
    }
    out
}

fn parse_entries(f: Fields) -> Vec<Entry> {
    let mut out = Vec::new();
    let mut cur: Fields = Vec::new();
    let mut cur_is_dir = false;
    for (k, v) in f {
        if k == "directory" || (k == "file" && !cur.is_empty()) {
            if cur_is_dir {
                let path = cur
                    .iter()
                    .find(|(k, _)| k == "directory")
                    .map(|(_, v)| v.clone())
                    .unwrap_or_default();
                let name = path.rsplit('/').next().unwrap_or(&path).to_string();
                out.push(Entry::Dir { path, name });
            } else if !cur.is_empty() {
                out.push(Entry::Song {
                    path: cur
                        .iter()
                        .find(|(k, _)| k == "file")
                        .map(|(_, v)| v.clone())
                        .unwrap_or_default(),
                    song: Song::from(std::mem::take(&mut cur)),
                });
            }
            cur = Vec::new();
            cur_is_dir = k == "directory";
        }
        cur.push((k, v));
    }
    if !cur.is_empty() {
        if cur_is_dir {
            let path = cur
                .iter()
                .find(|(k, _)| k == "directory")
                .map(|(_, v)| v.clone())
                .unwrap_or_default();
            let name = path.rsplit('/').next().unwrap_or(&path).to_string();
            out.push(Entry::Dir { path, name });
        } else {
            out.push(Entry::Song {
                path: cur
                    .iter()
                    .find(|(k, _)| k == "file")
                    .map(|(_, v)| v.clone())
                    .unwrap_or_default(),
                song: Song::from(cur),
            });
        }
    }
    out
}
