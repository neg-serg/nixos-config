//! A minimal MPD client speaking the plain-text wire protocol.
//!
//! Port of `mpd_voice/mpd.py`: the daemon protocol is line based
//! (`command arg1 arg2\n` -> `Key: value` lines -> `OK` or `ACK`), so the
//! client stays dependency free and covers playback, queue, modes, playlists
//! and library search — everything a voice front-end needs.

use std::fmt;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

pub const DEFAULT_HOST: &str = "127.0.0.1";
pub const DEFAULT_PORT: u16 = 6600;
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const GREETING_PREFIX: &str = "OK MPD ";

/// Server-side limit is generous; chunking keeps a huge album from blowing the
/// daemon's input buffer.
const COMMAND_LIST_CHUNK: usize = 200;

/// Tags accepted by `search`/`find`. `any` matches every tag (MPD >= 0.21).
pub const SEARCH_TAGS: [&str; 11] = [
    "any",
    "file",
    "artist",
    "albumartist",
    "album",
    "title",
    "genre",
    "date",
    "composer",
    "performer",
    "name",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MpdError {
    /// The server answered with `ACK` (command level failure).
    Ack {
        code: i64,
        message: String,
        command: Vec<String>,
    },
    /// Transport level failure: no daemon, timeout, closed connection.
    Connection(String),
}

impl MpdError {
    pub fn is_connection(&self) -> bool {
        matches!(self, MpdError::Connection(_))
    }
}

impl fmt::Display for MpdError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MpdError::Ack { code, message, .. } => {
                write!(f, "MPD error {code}: {message}")
            }
            MpdError::Connection(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for MpdError {}

/// Ordered `Key: value` map: MPD repeats keys for multi-valued tags, and the
/// JSON output keeps protocol order, so a sorted map would be wrong.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Meta(pub Vec<(String, String)>);

impl Meta {
    pub fn new() -> Self {
        Meta(Vec::new())
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.0
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// Insert, joining repeats with `", "` the way the Python client did.
    pub fn insert_joined(&mut self, key: String, value: String) {
        if let Some(entry) = self.0.iter_mut().find(|(k, _)| *k == key) {
            entry.1 = format!("{}, {}", entry.1, value);
        } else {
            self.0.push((key, value));
        }
    }
}

impl<'a> IntoIterator for &'a Meta {
    type Item = &'a (String, String);
    type IntoIter = std::slice::Iter<'a, (String, String)>;

    fn into_iter(self) -> Self::IntoIter {
        self.0.iter()
    }
}

/// Quote one protocol argument the way libmpdclient does.
pub fn quote(argument: &str) -> String {
    let needs_quotes = argument.is_empty()
        || argument
            .chars()
            .any(|ch| matches!(ch, ' ' | '\t' | '"' | '\\' | '\n'));
    if !needs_quotes {
        return argument.to_string();
    }
    let escaped = argument.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{escaped}\"")
}

/// Turn `Key: value` protocol lines into pairs (garbage is skipped).
pub fn split_pairs<'a, I: IntoIterator<Item = &'a str>>(lines: I) -> Meta {
    let mut pairs = Vec::new();
    for line in lines {
        if let Some((key, value)) = line.split_once(": ") {
            pairs.push((key.to_string(), value.to_string()));
        }
    }
    Meta(pairs)
}

/// Flatten pairs into a metadata map with lower-cased keys.
///
/// MPD capitalises tag names (`Title`, `AlbumArtist`); the rest of the client
/// speaks lowercase, so the translation happens once, here.
pub fn song_dict<'a, I: IntoIterator<Item = (&'a str, &'a str)>>(pairs: I) -> Meta {
    let mut song = Meta::new();
    for (key, value) in pairs {
        song.insert_joined(key.to_lowercase(), value.to_string());
    }
    song
}

/// Group protocol pairs into songs (a song starts at `file`).
pub fn songs_from(pairs: &Meta) -> Vec<Meta> {
    let mut songs: Vec<Meta> = Vec::new();
    for (key, value) in pairs {
        let key = key.to_lowercase();
        if key == "file" {
            let mut song = Meta::new();
            song.insert_joined(key, value.clone());
            songs.push(song);
        } else if let Some(current) = songs.last_mut() {
            current.insert_joined(key, value.clone());
        }
    }
    songs
}

/// Parse `ACK [5@0] {command} message` into its code and message.
pub fn parse_ack(line: &str) -> (i64, String) {
    let body = line.trim_start_matches("ACK").trim();
    let (code_token, rest) = match body.split_once('@') {
        Some((code, rest)) => (code, rest),
        None => (body, ""),
    };
    let code = code_token
        .trim()
        .trim_start_matches('[')
        .parse::<i64>()
        .unwrap_or(0);
    let message = match rest.split_once(']') {
        Some((_, message)) => message.trim(),
        None => "",
    };
    let message = if message.starts_with('{') && message.contains('}') {
        match message.split_once('}') {
            Some((_, tail)) => tail.trim(),
            None => message,
        }
    } else {
        message
    };
    let message = if message.is_empty() {
        line.to_string()
    } else {
        message.to_string()
    };
    (code, message)
}

/// Blocking MPD client; the socket opens on first use.
pub struct MpdClient {
    pub host: String,
    pub port: u16,
    pub password: Option<String>,
    pub timeout: Duration,
    pub version: Option<String>,
    stream: Option<TcpStream>,
    reader: Option<BufReader<TcpStream>>,
}

impl MpdClient {
    pub fn new(host: &str, port: u16, password: Option<String>, timeout: Duration) -> Self {
        MpdClient {
            host: host.to_string(),
            port,
            password,
            timeout,
            version: None,
            stream: None,
            reader: None,
        }
    }

    pub fn from_env(timeout: Duration) -> Self {
        let host = std::env::var("MPD_HOST").unwrap_or_else(|_| DEFAULT_HOST.to_string());
        let port = std::env::var("MPD_PORT")
            .ok()
            .and_then(|p| p.trim().parse::<u16>().ok())
            .unwrap_or(DEFAULT_PORT);
        let password = std::env::var("MPD_PASSWORD").ok().filter(|p| !p.is_empty());
        MpdClient::new(&host, port, password, timeout)
    }

    pub fn connect(&mut self) -> Result<(), MpdError> {
        if self.stream.is_some() {
            return Ok(());
        }
        let address = (self.host.as_str(), self.port)
            .to_socket_addrs()
            .map_err(|exc| {
                MpdError::Connection(format!(
                    "cannot reach MPD at {}:{}: {exc}",
                    self.host, self.port
                ))
            })?
            .next()
            .ok_or_else(|| {
                MpdError::Connection(format!(
                    "cannot reach MPD at {}:{}: no address",
                    self.host, self.port
                ))
            })?;
        let stream = TcpStream::connect_timeout(&address, self.timeout).map_err(|exc| {
            MpdError::Connection(format!(
                "cannot reach MPD at {}:{}: {exc}",
                self.host, self.port
            ))
        })?;
        stream.set_read_timeout(Some(self.timeout)).ok();
        stream.set_write_timeout(Some(self.timeout)).ok();
        let reader = stream.try_clone().map_err(|exc| {
            MpdError::Connection(format!(
                "cannot reach MPD at {}:{}: {exc}",
                self.host, self.port
            ))
        })?;
        self.stream = Some(stream);
        self.reader = Some(BufReader::new(reader));

        let greeting = self.read_line()?;
        let Some(version) = greeting.strip_prefix(GREETING_PREFIX) else {
            self.close();
            return Err(MpdError::Connection(format!(
                "bad MPD greeting: '{greeting}'"
            )));
        };
        self.version = Some(version.trim().to_string());
        if let Some(password) = self.password.clone() {
            self.command(&["password", &password])?;
        }
        Ok(())
    }

    pub fn close(&mut self) {
        self.reader = None;
        if let Some(stream) = self.stream.take() {
            let _ = stream.shutdown(std::net::Shutdown::Both);
        }
        self.version = None;
    }

    fn read_line(&mut self) -> Result<String, MpdError> {
        let Some(reader) = self.reader.as_mut() else {
            return Err(MpdError::Connection("not connected".to_string()));
        };
        let mut raw = String::new();
        match reader.read_line(&mut raw) {
            Ok(0) => Err(MpdError::Connection(
                "MPD closed the connection".to_string(),
            )),
            Ok(_) => Ok(raw.trim_end_matches(['\r', '\n']).to_string()),
            Err(exc) if is_timeout(&exc) => Err(MpdError::Connection(format!(
                "timed out waiting for MPD at {}:{}",
                self.host, self.port
            ))),
            Err(exc) => Err(MpdError::Connection(format!("MPD connection lost: {exc}"))),
        }
    }

    fn send(&mut self, payload: &str) -> Result<(), MpdError> {
        let Some(stream) = self.stream.as_mut() else {
            return Err(MpdError::Connection("not connected".to_string()));
        };
        stream
            .write_all(payload.as_bytes())
            .and_then(|()| stream.flush())
            .map_err(|exc| MpdError::Connection(format!("MPD connection lost: {exc}")))
    }

    /// Run one command and return its `Key: value` pairs.
    pub fn command(&mut self, args: &[&str]) -> Result<Meta, MpdError> {
        self.connect()?;
        let quoted: Vec<String> = args.iter().map(|arg| quote(arg)).collect();
        self.send(&format!("{}\n", quoted.join(" ")))?;
        let mut lines: Vec<String> = Vec::new();
        loop {
            let line = self.read_line()?;
            if line == "OK" {
                return Ok(split_pairs(lines.iter().map(String::as_str)));
            }
            if line.starts_with("ACK") {
                let (code, message) = parse_ack(&line);
                return Err(MpdError::Ack {
                    code,
                    message,
                    command: args.iter().map(|a| a.to_string()).collect(),
                });
            }
            lines.push(line);
        }
    }

    /// Run commands as a command list; returns pairs per command.
    pub fn command_list(&mut self, commands: &[Vec<String>]) -> Result<Vec<Meta>, MpdError> {
        self.connect()?;
        let mut payload = vec!["command_list_begin".to_string()];
        for command in commands {
            let quoted: Vec<String> = command.iter().map(|arg| quote(arg)).collect();
            payload.push(quoted.join(" "));
        }
        payload.push("command_list_end".to_string());
        self.send(&format!("{}\n", payload.join("\n")))?;
        let mut results: Vec<Meta> = Vec::new();
        let mut current: Vec<String> = Vec::new();
        loop {
            let line = self.read_line()?;
            if line == "OK" {
                return Ok(results);
            }
            if line == "list_OK" {
                results.push(split_pairs(current.iter().map(String::as_str)));
                current.clear();
                continue;
            }
            if line.starts_with("ACK") {
                let (code, message) = parse_ack(&line);
                return Err(MpdError::Ack {
                    code,
                    message,
                    command: vec!["command_list".to_string()],
                });
            }
            current.push(line);
        }
    }

    // -- playback ------------------------------------------------------
    pub fn status(&mut self) -> Result<Meta, MpdError> {
        self.command(&["status"])
    }

    pub fn current_song(&mut self) -> Result<Meta, MpdError> {
        let pairs = self.command(&["currentsong"])?;
        let owned: Vec<(String, String)> = pairs
            .0
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        Ok(song_dict(
            owned.iter().map(|(k, v)| (k.as_str(), v.as_str())),
        ))
    }

    pub fn queue(&mut self) -> Result<Vec<Meta>, MpdError> {
        let pairs = self.command(&["playlistinfo"])?;
        Ok(songs_from(&pairs))
    }

    pub fn song_at(&mut self, position: i64) -> Result<Meta, MpdError> {
        let position = position.to_string();
        let pairs = self.command(&["playlistinfo", &position])?;
        Ok(songs_from(&pairs).into_iter().next().unwrap_or_default())
    }

    pub fn play(&mut self, position: Option<i64>) -> Result<(), MpdError> {
        match position {
            Some(position) => {
                let position = position.to_string();
                self.command(&["play", &position]).map(|_| ())
            }
            None => self.command(&["play"]).map(|_| ()),
        }
    }

    pub fn pause(&mut self, paused: bool) -> Result<(), MpdError> {
        self.command(&["pause", if paused { "1" } else { "0" }])
            .map(|_| ())
    }

    pub fn resume(&mut self) -> Result<(), MpdError> {
        self.pause(false)
    }

    /// Pause when playing, resume when paused; `true` when now paused.
    pub fn toggle_pause(&mut self) -> Result<bool, MpdError> {
        let was_playing = self.status()?.get("state") == Some("play");
        self.pause(was_playing)?;
        Ok(was_playing)
    }

    pub fn stop(&mut self) -> Result<(), MpdError> {
        self.command(&["stop"]).map(|_| ())
    }

    pub fn next(&mut self) -> Result<(), MpdError> {
        self.command(&["next"]).map(|_| ())
    }

    pub fn previous(&mut self) -> Result<(), MpdError> {
        self.command(&["previous"]).map(|_| ())
    }

    // -- volume --------------------------------------------------------
    pub fn volume(&mut self) -> Result<Option<i64>, MpdError> {
        let status = self.status()?;
        Ok(status
            .get("volume")
            .and_then(|raw| raw.trim().parse::<i64>().ok())
            .filter(|value| *value >= 0))
    }

    pub fn set_volume(&mut self, value: i64) -> Result<i64, MpdError> {
        let clamped = value.clamp(0, 100);
        let text = clamped.to_string();
        self.command(&["setvol", &text])?;
        Ok(clamped)
    }

    pub fn adjust_volume(&mut self, delta: i64) -> Result<Option<i64>, MpdError> {
        match self.volume()? {
            Some(current) => self.set_volume(current + delta).map(Some),
            None => Ok(None),
        }
    }

    // -- seek ----------------------------------------------------------
    pub fn seek_relative(&mut self, seconds: f64) -> Result<(), MpdError> {
        let sign = if seconds >= 0.0 { "+" } else { "" };
        let value = format!("{sign}{}", short_float(seconds));
        self.command(&["seekcur", &value]).map(|_| ())
    }

    pub fn seek_to(&mut self, seconds: f64) -> Result<(), MpdError> {
        let value = short_float(seconds.max(0.0));
        self.command(&["seekcur", &value]).map(|_| ())
    }

    // -- modes ---------------------------------------------------------
    fn mode(&mut self, name: &str, enabled: bool) -> Result<bool, MpdError> {
        self.command(&[name, if enabled { "1" } else { "0" }])?;
        Ok(enabled)
    }

    pub fn set_random(&mut self, enabled: bool) -> Result<bool, MpdError> {
        self.mode("random", enabled)
    }

    pub fn set_repeat(&mut self, enabled: bool) -> Result<bool, MpdError> {
        self.mode("repeat", enabled)
    }

    pub fn set_single(&mut self, enabled: bool) -> Result<bool, MpdError> {
        self.mode("single", enabled)
    }

    pub fn set_consume(&mut self, enabled: bool) -> Result<bool, MpdError> {
        self.mode("consume", enabled)
    }

    pub fn get_mode(&mut self, name: &str) -> Result<bool, MpdError> {
        Ok(self.status()?.get(name) == Some("1"))
    }

    pub fn flip_mode(&mut self, name: &str) -> Result<bool, MpdError> {
        let current = self.get_mode(name)?;
        self.mode(name, !current)
    }

    pub fn set_crossfade(&mut self, seconds: i64) -> Result<i64, MpdError> {
        let value = seconds.max(0);
        let text = value.to_string();
        self.command(&["crossfade", &text])?;
        Ok(value)
    }

    // -- queue and library ---------------------------------------------
    pub fn clear(&mut self) -> Result<(), MpdError> {
        self.command(&["clear"]).map(|_| ())
    }

    pub fn add(&mut self, uri: &str) -> Result<(), MpdError> {
        self.command(&["add", uri]).map(|_| ())
    }

    /// Append many URIs, using command lists when the server allows it.
    pub fn add_many(&mut self, uris: &[String]) -> Result<usize, MpdError> {
        for chunk in uris.chunks(COMMAND_LIST_CHUNK) {
            let commands: Vec<Vec<String>> = chunk
                .iter()
                .map(|uri| vec!["add".to_string(), uri.clone()])
                .collect();
            if self.command_list(&commands).is_err() {
                // Older servers (or a queue edited concurrently) may refuse a
                // command list; fall back to plain `add` calls.
                for uri in chunk {
                    self.add(uri)?;
                }
            }
        }
        Ok(uris.len())
    }

    pub fn search(&mut self, tag: &str, needle: &str) -> Result<Vec<Meta>, MpdError> {
        if !SEARCH_TAGS.contains(&tag) {
            return Err(MpdError::Connection(format!(
                "unsupported search tag: {tag}"
            )));
        }
        let pairs = self.command(&["search", tag, needle])?;
        Ok(songs_from(&pairs))
    }

    pub fn search_any(&mut self, needle: &str) -> Result<Vec<Meta>, MpdError> {
        self.search("any", needle)
    }

    pub fn find(&mut self, tag: &str, needle: &str) -> Result<Vec<Meta>, MpdError> {
        if !SEARCH_TAGS.contains(&tag) {
            return Err(MpdError::Connection(format!(
                "unsupported search tag: {tag}"
            )));
        }
        let pairs = self.command(&["find", tag, needle])?;
        Ok(songs_from(&pairs))
    }

    // -- playlists -----------------------------------------------------
    pub fn playlists(&mut self) -> Result<Vec<String>, MpdError> {
        let pairs = self.command(&["listplaylists"])?;
        Ok(pairs
            .0
            .into_iter()
            .filter(|(key, _)| key == "playlist")
            .map(|(_, value)| value)
            .collect())
    }

    pub fn playlist_songs(&mut self, name: &str) -> Result<Vec<Meta>, MpdError> {
        let pairs = self.command(&["listplaylistinfo", name])?;
        Ok(songs_from(&pairs))
    }

    pub fn load_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        self.command(&["load", name]).map(|_| ())
    }

    pub fn save_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        self.command(&["save", name]).map(|_| ())
    }

    pub fn delete_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        self.command(&["rm", name]).map(|_| ())
    }

    // -- misc ----------------------------------------------------------
    pub fn update(&mut self, path: &str) -> Result<(), MpdError> {
        if path.is_empty() {
            self.command(&["update"]).map(|_| ())
        } else {
            self.command(&["update", path]).map(|_| ())
        }
    }

    pub fn stats(&mut self) -> Result<Meta, MpdError> {
        self.command(&["stats"])
    }

    pub fn ping(&mut self) -> Result<(), MpdError> {
        self.command(&["ping"]).map(|_| ())
    }
}

impl Drop for MpdClient {
    fn drop(&mut self) {
        self.close();
    }
}

fn is_timeout(exc: &std::io::Error) -> bool {
    matches!(
        exc.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    )
}

/// Python's `{value:g}` for the shapes the CLI produces: no trailing `.0`.
fn short_float(value: f64) -> String {
    if value.is_finite() && value.fract() == 0.0 && value.abs() < 1e15 {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_argument_is_untouched() {
        assert_eq!(quote("Agalloch"), "Agalloch");
    }

    #[test]
    fn spaces_and_quotes_are_escaped() {
        assert_eq!(quote("The Mantle"), "\"The Mantle\"");
        assert_eq!(quote("say \"hi\""), "\"say \\\"hi\\\"\"");
        assert_eq!(quote(""), "\"\"");
        assert_eq!(quote("back\\slash"), "\"back\\\\slash\"");
    }

    #[test]
    fn song_dict_lowercases_and_joins() {
        let song = song_dict([("file", "a.flac"), ("Title", "T"), ("Artist", "A")]);
        assert_eq!(song.get("title"), Some("T"));
        let song = song_dict([("file", "a.flac"), ("Artist", "A"), ("Artist", "B")]);
        assert_eq!(song.get("artist"), Some("A, B"));
    }

    #[test]
    fn songs_start_at_file() {
        let pairs = split_pairs([
            "file: a.flac",
            "Title: A",
            "file: b.flac",
            "Title: B",
            "Time: 12",
        ]);
        let songs = songs_from(&pairs);
        assert_eq!(songs.len(), 2);
        assert_eq!(songs[0].get("title"), Some("A"));
        assert_eq!(songs[1].get("time"), Some("12"));
    }

    #[test]
    fn pairs_skip_garbage() {
        let pairs = split_pairs(["no separator", "file: a.flac", "Artist: X"]);
        assert_eq!(pairs.0.len(), 2);
    }

    #[test]
    fn ack_is_parsed() {
        assert_eq!(
            parse_ack("ACK [5@0] {add} unknown command \"x\""),
            (5, "unknown command \"x\"".to_string())
        );
        assert_eq!(
            parse_ack("ACK [50@1] {play} no such song"),
            (50, "no such song".to_string())
        );
        assert_eq!(parse_ack("ACK garbage"), (0, "ACK garbage".to_string()));
    }

    #[test]
    fn short_floats_have_no_trailing_zero() {
        assert_eq!(short_float(5.0), "5");
        assert_eq!(short_float(-2.5), "-2.5");
        assert_eq!(short_float(0.0), "0");
    }
}
