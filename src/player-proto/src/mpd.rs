//! Minimal MPD client: plain TCP, no external crates.
//!
//! Only the subset a frontend needs: status/current song, queue, library listing, search,
//! playback control and `idle` for change notifications. The protocol is line based:
//! commands end with `\n`, responses are `key: value` lines terminated by `OK` or `ACK`.

use std::collections::HashMap;
use std::io::{self, BufRead, BufReader, Write};
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

impl std::error::Error for MpdError {}

/// Protocol errors keep crossing into the `io::Result` world with their text intact.
///
/// The older methods below return `Result<_, MpdError>` and stay that way (callers depend on the
/// type); the newer ones return `io::Result` so a caller can mix them with socket errors without
/// dragging a second error enum along. This bridge is the `?` between the two: an `ACK` still reads
/// like an `ACK`, only its carrier changed.
impl From<MpdError> for io::Error {
    fn from(e: MpdError) -> Self {
        io::Error::new(io::ErrorKind::Other, e.0)
    }
}

/// Rejected by this client before a single byte reaches the socket.
fn invalid(msg: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, msg.into())
}

/// Quote one command argument the way MPD parses it back.
///
/// The protocol has no line-level escaping: a quoted argument ends at the first `"` that is not
/// preceded by a backslash, and a literal `\` is sent as `\\`. Everything that lands here (playlist
/// names, URIs, tag values) is user data, so it goes through this one helper instead of a private
/// copy of the two `replace` calls at every call site.
fn quote(arg: &str) -> String {
    let mut out = String::with_capacity(arg.len() + 2);
    out.push('"');
    for ch in arg.chars() {
        if ch == '\\' || ch == '"' {
            out.push('\\');
        }
        out.push(ch);
    }
    out.push('"');
    out
}

/// First value of `key` in a reply, trimmed.
fn field<'a>(fields: &'a Fields, key: &str) -> Option<&'a str> {
    fields.iter().find(|(k, _)| k == key).map(|(_, v)| v.trim())
}

/// First value of `key` parsed as an unsigned number; `None` when absent or unparsable.
fn field_u64(fields: &Fields, key: &str) -> Option<u64> {
    field(fields, key).and_then(|v| v.parse().ok())
}

/// `crossfade <seconds>`, or an error for a value MPD cannot mean.
///
/// Negative seconds are refused here: MPD's parser would take them and the daemon would clamp or
/// misbehave, and a caller passing `-1` has a bug worth reporting.
fn crossfade_line(secs: i32) -> io::Result<String> {
    if secs < 0 {
        return Err(invalid(format!(
            "crossfade: {secs} is negative; seconds must be >= 0"
        )));
    }
    Ok(format!("crossfade {secs}"))
}

/// `prio <priority> <start:end>`, or an error for a range the daemon would reject.
fn prio_line(priority: u8, start: usize, end: usize) -> io::Result<String> {
    if start > end {
        return Err(invalid(format!("prio: start {start} is after end {end}")));
    }
    Ok(format!("prio {priority} {start}:{end}"))
}

/// `addtagid <songid> <tag> <value>` when `value` is given, `cleartagid <songid> <tag>` otherwise.
///
/// Tag names are bare words on the wire, so one with whitespace or quotes would split the line into
/// different arguments; that is refused before anything is sent.
fn tag_line(cmd: &str, songid: u32, tag: &str, value: Option<&str>) -> io::Result<String> {
    if tag.is_empty()
        || tag
            .chars()
            .any(|c| c.is_whitespace() || c == '"' || c == '\\')
    {
        return Err(invalid(format!("{cmd}: invalid tag name {tag:?}")));
    }
    match value {
        Some(value) => Ok(format!("{cmd} {songid} {tag} {}", quote(value))),
        None => Ok(format!("{cmd} {songid} {tag}")),
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
        let f = self.command(&format!("lsinfo {}", quote(uri)))?;
        Ok(parse_entries(f))
    }

    pub fn search(&mut self, query: &str) -> Result<Vec<Song>, MpdError> {
        let f = self.command(&format!("search any {}", quote(query)))?;
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
        Ok(parse_songs(
            self.command(&format!("listplaylistinfo {}", quote(name)))?,
        ))
    }

    /// Songs matching one tag exactly (`find Artist "X"`).
    pub fn find(&mut self, tag: &str, value: &str) -> Result<Vec<Song>, MpdError> {
        Ok(parse_songs(
            self.command(&format!("find {tag} {}", quote(value)))?,
        ))
    }

    /// Append songs and start playing the first of them; returns the first song id.
    pub fn add_and_play(&mut self, uris: &[String]) -> Result<(), MpdError> {
        let mut first_id: Option<u64> = None;
        for uri in uris {
            let fields = self.command(&format!("addid {} \"\"", quote(uri)))?;
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
            self.command(&format!("add {}", quote(uri)))?;
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
        self.command(&format!("save {}", quote(name))).map(|_| ())
    }

    /// `rm <name>`: delete a saved playlist.
    pub fn delete_playlist(&mut self, name: &str) -> Result<(), MpdError> {
        self.command(&format!("rm {}", quote(name))).map(|_| ())
    }

    /// `rename <old> <new>`. MPD changes this only for playlists, not for files.
    pub fn rename_playlist(&mut self, old: &str, new: &str) -> Result<(), MpdError> {
        self.command(&format!("rename {} {}", quote(old), quote(new)))
            .map(|_| ())
    }

    /// `playlistadd <name> <uri>`: append one song to a saved playlist.
    pub fn playlist_add(&mut self, name: &str, uri: &str) -> Result<(), MpdError> {
        self.command(&format!("playlistadd {} {}", quote(name), quote(uri)))
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
        self.writer
            .write_all(format!("albumart {} 0\n", quote(uri)).as_bytes())
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

    // ------------------------------------------------------------ mixer / gain / queue edits

    /// `crossfade [<seconds>]`: read or set the crossfader.
    ///
    /// `Some(n)` sends `crossfade <n>` — reply `OK` — and then reports what the daemon ended up
    /// with, which is not necessarily `n` because the daemon may clamp it. `None` sends the read
    /// form, whose reply is a single `crossfade: <seconds>` field.
    ///
    /// Two facts about MPD 0.24 shape the return type. It answers the argument-less form with
    /// `ACK [2@0] {crossfade} wrong number of arguments`, and it stopped echoing `crossfade` in
    /// `status` (checked live: `crossfade 1` then `status` prints no such field). So on that daemon
    /// the setting is write-only and both paths fail to produce a number: `None` then means "the
    /// daemon did not report a value", not "zero". Older daemons that answer the read form, or that
    /// still put the field in `status`, return `Some`.
    pub fn crossfade(&mut self, secs: Option<i32>) -> io::Result<Option<i32>> {
        if let Some(secs) = secs {
            let line = crossfade_line(secs)?;
            self.command(&line)?;
        }
        // Read form first: it is the documented reply (`crossfade: N`).
        match self.command("crossfade") {
            Ok(fields) => Ok(field(&fields, "crossfade").and_then(|v| v.parse().ok())),
            // The daemon refuses the read form (0.24 does); `status` was the other documented
            // source of the same value, so ask once and let an absent field mean "not reported".
            Err(_) => {
                let fields = self.command("status")?;
                Ok(field(&fields, "crossfade").and_then(|v| v.parse().ok()))
            }
        }
    }

    /// `replay_gain_mode <off|track|album|auto>`: how the daemon applies ReplayGain to playback.
    ///
    /// The command has no reply fields; the daemon answers `OK` or an `ACK`.
    pub fn replay_gain_mode(&mut self, mode: ReplayGainMode) -> io::Result<()> {
        self.command(&format!("replay_gain_mode {}", mode.as_str()))?;
        Ok(())
    }

    /// `replay_gain_status`: the mode currently in force.
    ///
    /// The reply is one field, `replay_gain_mode: <mode>`. A mode word this client does not know is
    /// an error rather than a guess: picking the wrong one would silently change how loud the
    /// daemon plays.
    pub fn replay_gain_status(&mut self) -> io::Result<ReplayGainMode> {
        let fields = self.command("replay_gain_status")?;
        let word = field(&fields, "replay_gain_mode").unwrap_or("");
        ReplayGainMode::parse(word)
            .ok_or_else(|| invalid(format!("replay_gain_status: unknown mode {word:?}")))
    }

    /// `shuffle`: randomise the order of the queue. No reply fields, just `OK`.
    pub fn shuffle(&mut self) -> io::Result<()> {
        self.command("shuffle")?;
        Ok(())
    }

    /// `prio <priority> <start:end>`: set the playback priority of the queue slice
    /// `start..end` (end exclusive, positions in the queue).
    ///
    /// The reply is `OK`, or an `ACK` for a range the daemon dislikes. MPD rejects priorities
    /// outside 0..=255 — the `u8` argument makes that a compile-time fact — and the only range this
    /// client still has to check is `start <= end`. A malformed line is never sent: the daemon's own
    /// answer to `prio 200 5:2` is `ACK [2@0] {prio} Malformed range: 5:2`, and there is no reason
    /// to make it parse our mistake.
    pub fn prio(&mut self, priority: u8, start: usize, end: usize) -> io::Result<()> {
        let line = prio_line(priority, start, end)?;
        self.command(&line)?;
        Ok(())
    }

    /// `update [<uri>]`: rescan the database (or one directory of it) and return the job id from
    /// the `updating_db: <id>` reply field.
    ///
    /// Without a URI the whole configured `music_directory` is updated; with one, only that
    /// subtree. The job runs in the background — the id is what `status` will report as
    /// `updating_db` until the scan ends.
    pub fn update(&mut self, uri: Option<&str>) -> io::Result<u32> {
        self.enqueue_update("update", uri)
    }

    /// `rescan [<uri>]`: like `update`, but re-reads tags of files that did not change on disk
    /// either. Reply and return value are the same `updating_db: <id>`.
    pub fn rescan(&mut self, uri: Option<&str>) -> io::Result<u32> {
        self.enqueue_update("rescan", uri)
    }

    /// Shared body of `update`/`rescan`: build the line, send it, pull the job id out.
    fn enqueue_update(&mut self, cmd: &str, uri: Option<&str>) -> io::Result<u32> {
        let line = match uri {
            Some(uri) => format!("{cmd} {}", quote(uri)),
            None => cmd.to_string(),
        };
        let fields = self.command(&line)?;
        field_u64(&fields, "updating_db")
            .map(|id| id as u32)
            .ok_or_else(|| invalid(format!("{cmd}: reply carried no updating_db job id")))
    }

    /// `stats`: library counters and uptime, not playback state.
    ///
    /// The reply is flat `key: value` pairs (`artists`, `albums`, `songs`, `uptime`, `playtime`,
    /// `db_playtime`, `db_update`); everything is a plain number of seconds, so it lands in `Stats`
    /// without unit guessing.
    pub fn stats(&mut self) -> io::Result<Stats> {
        Ok(Stats::from(self.command("stats")?))
    }

    /// `load "<name>"`: append a saved playlist to the queue. No reply fields, just `OK`.
    ///
    /// A name the daemon does not know comes back as `ACK [50@0] {load} No such playlist`, which
    /// surfaces here as an error.
    pub fn load(&mut self, playlist: &str) -> io::Result<()> {
        self.command(&format!("load {}", quote(playlist)))?;
        Ok(())
    }

    /// `rm` has no two-argument form: this removes one song from a saved playlist.
    ///
    /// MPD's `rm {NAME}` takes exactly one argument and deletes the whole playlist (that is
    /// `delete_playlist`); `rm "name" "uri"` is answered with `ACK [2@0] {rm} wrong number of
    /// arguments`. Deleting a single song is positional — `playlistdelete "<name>" <pos>` — so the
    /// URI is resolved through `listplaylistinfo` first and the first matching entry's `Pos` is
    /// used. A URI the playlist does not contain returns an error and nothing is sent.
    pub fn rm(&mut self, playlist: &str, uri: &str) -> io::Result<()> {
        let songs = self.playlist_songs(playlist)?;
        let pos = songs
            .iter()
            .enumerate()
            .find(|(_, song)| song.file == uri)
            .map(|(index, song)| song.pos.unwrap_or(index))
            .ok_or_else(|| {
                invalid(format!(
                    "rm: {} is not in playlist {}",
                    quote(uri),
                    quote(playlist)
                ))
            })?;
        self.command(&format!("playlistdelete {} {pos}", quote(playlist)))?;
        Ok(())
    }

    /// `seekcur <value>`: move the playback position inside the current song.
    ///
    /// The three wire forms are `seekcur 12.5` (absolute seconds), `seekcur +5` / `seekcur -5`
    /// (relative to the current position) and `seekcur 50%` (fraction of the song).
    ///
    /// Every value is range-checked before anything is written, so a bad call is an error here and
    /// not an `ACK` from the daemon. One wrinkle is handled below: MPD 0.24 on this host refuses
    /// the percent form (`ACK [2@0] {seekcur} Float expected: 50%`), so a percentage is converted
    /// to seconds from the current `duration` and retried — a seek that would otherwise always
    /// fail on that daemon.
    pub fn seek_cur(&mut self, spec: SeekSpec) -> io::Result<()> {
        let arg = spec.arg()?;
        match self.command(&format!("seekcur {arg}")) {
            Ok(_) => Ok(()),
            Err(e) => match spec {
                SeekSpec::Percent(p) => {
                    let status = self.command("status")?;
                    let duration = field(&status, "duration")
                        .and_then(|v| v.parse::<f64>().ok())
                        .unwrap_or(0.0);
                    if !(duration > 0.0) {
                        // Nothing playing or no duration: the original ACK is the honest answer.
                        return Err(e.into());
                    }
                    let secs = duration * p / 100.0;
                    self.command(&format!("seekcur {secs:.3}"))?;
                    Ok(())
                }
                _ => Err(e.into()),
            },
        }
    }

    /// `addtagid <songid> <tag> <value>`: set one tag on a song **in the queue**.
    ///
    /// This edits the queue entry, never the file on disk: MPD's queue tags shadow the tags read
    /// from the file, they are what the player displays, and they vanish with the queue entry. The
    /// first argument is the queue song id (`Id:` in `playlistinfo`/`currentsong`, `songid` in
    /// `status`), not a queue position. The reply carries no fields.
    ///
    /// One limit is worth knowing before building a UI on this: MPD 0.24 refuses the edit for an
    /// ordinary library file and answers `ACK [4@0] {addtagid} Cannot edit tags of local file`
    /// (observed live), so queue tags are only editable for entries the daemon is willing to tag.
    /// The ACK surfaces here as an error like any other.
    pub fn addtagid(&mut self, songid: u32, tag: &str, value: &str) -> io::Result<()> {
        let line = tag_line("addtagid", songid, tag, Some(value))?;
        self.command(&line)?;
        Ok(())
    }

    /// `cleartagid <songid> <tag>`: drop a queue tag again, so the value from the file shows up
    /// once more. Same scope and same daemon-side limit as `addtagid`: the queue entry, not the
    /// file, and MPD refuses it for local files just the same.
    pub fn cleartagid(&mut self, songid: u32, tag: &str) -> io::Result<()> {
        let line = tag_line("cleartagid", songid, tag, None)?;
        self.command(&line)?;
        Ok(())
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

/// What MPD does with the ReplayGain tags of the files it plays.
///
/// The wire words are exactly `off`, `track`, `album` and `auto`; the enum exists so the app cannot
/// send a word the daemon will `ACK` back at it, and so `status` can report the mode as data instead
/// of a string the UI has to compare.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ReplayGainMode {
    /// Tags ignored: they never touch the volume.
    #[default]
    Off,
    /// Every song normalised to the same loudness.
    Track,
    /// Every song normalised to its album's loudness, which keeps intra-album dynamics.
    Album,
    /// The daemon decides: album gain while an album plays in order, track gain otherwise.
    Auto,
}

impl ReplayGainMode {
    /// Parse a wire word. `None` for anything unknown, so a caller can report it instead of
    /// guessing a mode that would change how loud playback is.
    pub fn parse(word: &str) -> Option<Self> {
        match word.trim().to_ascii_lowercase().as_str() {
            "off" => Some(Self::Off),
            "track" => Some(Self::Track),
            "album" => Some(Self::Album),
            "auto" => Some(Self::Auto),
            _ => None,
        }
    }

    /// The word `replay_gain_mode` takes and `replay_gain_status` reports.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Track => "track",
            Self::Album => "album",
            Self::Auto => "auto",
        }
    }
}

impl std::fmt::Display for ReplayGainMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Where `seek_cur` should put the playback position.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SeekSpec {
    /// Seconds from the start of the song: `seekcur 12.5`.
    Absolute(f64),
    /// Seconds from the current position, sign carried in the value: `seekcur +5` / `seekcur -5`.
    Relative(f64),
    /// Percent of the song's length: `seekcur 50%`.
    Percent(f64),
}

impl SeekSpec {
    /// Longest jump this client will send. MPD itself accepts more, but a seek beyond a day means
    /// the caller is passing nonsense (a duration in the wrong unit, a NaN from a division).
    const MAX_SECS: f64 = 86_400.0;

    /// The argument `seekcur` receives, or an error before anything reaches the socket.
    ///
    /// `Absolute` additionally has to be non-negative: MPD reads a leading `-` as "relative to the
    /// current position", so a negative absolute value would silently become another operation.
    pub fn arg(self) -> io::Result<String> {
        match self {
            Self::Absolute(secs) => {
                if !secs.is_finite() || !(0.0..=Self::MAX_SECS).contains(&secs) {
                    return Err(invalid(format!(
                        "seek_cur: absolute {secs} is outside 0..={}",
                        Self::MAX_SECS
                    )));
                }
                Ok(format!("{secs}"))
            }
            Self::Relative(secs) => {
                if !secs.is_finite() || secs.abs() > Self::MAX_SECS {
                    return Err(invalid(format!(
                        "seek_cur: relative {secs} is outside +-{}",
                        Self::MAX_SECS
                    )));
                }
                if secs > 0.0 {
                    Ok(format!("+{secs}"))
                } else if secs < 0.0 {
                    Ok(format!("{secs}"))
                } else {
                    // -0.0 would render as "+-0", and both zeroes mean "stay here".
                    Ok("+0".to_string())
                }
            }
            Self::Percent(percent) => {
                if !percent.is_finite() || !(0.0..=100.0).contains(&percent) {
                    return Err(invalid(format!(
                        "seek_cur: percent {percent} is outside 0..=100"
                    )));
                }
                Ok(format!("{percent}%"))
            }
        }
    }
}

/// Library counters from `stats`, all in plain seconds (or plain counts).
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Stats {
    pub artists: u64,
    pub albums: u64,
    pub songs: u64,
    /// Seconds the daemon process has been up.
    pub uptime_secs: u64,
    /// Seconds of audio actually played since the daemon started.
    pub playtime_secs: u64,
    /// Total length of everything in the database.
    pub db_playtime_secs: u64,
    /// Unix timestamp of the last database update.
    pub db_update_secs: u64,
}

impl From<Fields> for Stats {
    fn from(f: Fields) -> Self {
        Self {
            artists: field_u64(&f, "artists").unwrap_or(0),
            albums: field_u64(&f, "albums").unwrap_or(0),
            songs: field_u64(&f, "songs").unwrap_or(0),
            uptime_secs: field_u64(&f, "uptime").unwrap_or(0),
            playtime_secs: field_u64(&f, "playtime").unwrap_or(0),
            db_playtime_secs: field_u64(&f, "db_playtime").unwrap_or(0),
            db_update_secs: field_u64(&f, "db_update").unwrap_or(0),
        }
    }
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
    /// Crossfade in seconds as `status` reports it; 0 when the field is absent.
    ///
    /// MPD 0.24 does not put this field in `status` at all (verified live), so there the value
    /// stays 0 and `Client::crossfade` explains why it cannot be read back either.
    pub crossfade: i32,
    /// ReplayGain mode from `replay_gain_mode:`; empty when the daemon omits the field.
    ///
    /// MPD 0.24 does not report it here at all (verified live with `track` set), it only answers
    /// `replay_gain_status`; older daemons do put it in `status`, which is what this field keeps.
    pub replay_gain_mode: String,
    /// Queue version from `playlist:`; it changes whenever the queue does, which is what makes it
    /// useful as a cheap "did anything move" check.
    pub playlist_version: u32,
    /// Last error the daemon recorded, from `error:`; `None` when the field is absent or empty.
    pub error: Option<String>,
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
            crossfade: map
                .get("crossfade")
                .and_then(|v| v.trim().parse::<i32>().ok())
                .unwrap_or(0),
            replay_gain_mode: map
                .get("replay_gain_mode")
                .map(|v| v.trim().to_string())
                .unwrap_or_default(),
            playlist_version: num("playlist").unwrap_or(0) as u32,
            // An empty `error:` (the daemon clears it with an empty value) is not an error.
            error: map
                .get("error")
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty()),
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

#[cfg(test)]
mod tests {
    //! Pure-function tests: everything here runs without a daemon.
    //!
    //! The interesting property is not "the string looks nice" but "a bad value never reaches the
    //! socket": each validator is a separate function precisely so this can be checked without one.

    use super::*;

    fn fields(pairs: &[(&str, &str)]) -> Fields {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn quote_escapes_backslash_and_double_quote_only() {
        assert_eq!(quote(""), "\"\"");
        assert_eq!(quote("plain"), "\"plain\"");
        assert_eq!(quote("a b"), "\"a b\"");
        // A quote would end the argument early; a backslash would escape whatever follows it.
        assert_eq!(quote("say \"hi\""), "\"say \\\"hi\\\"\"");
        assert_eq!(quote("c:\\music"), "\"c:\\\\music\"");
        assert_eq!(quote("trailing\\"), "\"trailing\\\\\"");
        // Non-ASCII passes through untouched: MPD speaks UTF-8.
        assert_eq!(quote("Björk — Jóga"), "\"Björk — Jóga\"");
    }

    #[test]
    fn seek_spec_builds_the_three_wire_forms() {
        assert_eq!(SeekSpec::Absolute(12.5).arg().unwrap(), "12.5");
        assert_eq!(SeekSpec::Absolute(0.0).arg().unwrap(), "0");
        assert_eq!(SeekSpec::Relative(5.0).arg().unwrap(), "+5");
        assert_eq!(SeekSpec::Relative(-5.0).arg().unwrap(), "-5");
        // -0.0 must not turn into "+-0".
        assert_eq!(SeekSpec::Relative(-0.0).arg().unwrap(), "+0");
        assert_eq!(SeekSpec::Percent(50.0).arg().unwrap(), "50%");
        assert_eq!(SeekSpec::Percent(0.0).arg().unwrap(), "0%");
        assert_eq!(SeekSpec::Percent(100.0).arg().unwrap(), "100%");
    }

    #[test]
    fn seek_spec_refuses_values_that_would_be_a_bad_line() {
        for bad in [
            SeekSpec::Absolute(-5.0),
            SeekSpec::Absolute(f64::NAN),
            SeekSpec::Absolute(f64::INFINITY),
            SeekSpec::Absolute(86_401.0),
            SeekSpec::Relative(f64::NAN),
            SeekSpec::Relative(86_401.0),
            SeekSpec::Relative(-86_401.0),
            SeekSpec::Percent(-1.0),
            SeekSpec::Percent(101.0),
            SeekSpec::Percent(f64::NAN),
        ] {
            let err = bad.arg().expect_err(&format!("{bad:?} should be refused"));
            assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        }
        // The documented boundaries stay usable.
        assert!(SeekSpec::Absolute(86_400.0).arg().is_ok());
        assert!(SeekSpec::Relative(-86_400.0).arg().is_ok());
    }

    #[test]
    fn prio_line_checks_the_range_and_the_priority() {
        assert_eq!(prio_line(0, 0, 0).unwrap(), "prio 0 0:0");
        assert_eq!(prio_line(255, 3, 7).unwrap(), "prio 255 3:7");
        // A priority outside 0..=255 is not expressible: the argument is a u8.
        assert!(prio_line(200, 5, 2).is_err());
    }

    #[test]
    fn tag_lines_quote_the_value_and_reject_bad_tag_names() {
        assert_eq!(
            tag_line("addtagid", 190, "Title", Some("A\"B")).unwrap(),
            "addtagid 190 Title \"A\\\"B\""
        );
        assert_eq!(
            tag_line("cleartagid", 190, "Title", None).unwrap(),
            "cleartagid 190 Title"
        );
        assert!(tag_line("addtagid", 1, "", Some("x")).is_err());
        assert!(tag_line("addtagid", 1, "Two Words", Some("x")).is_err());
        assert!(tag_line("cleartagid", 1, "a\"b", None).is_err());
    }

    #[test]
    fn crossfade_line_rejects_negative_seconds() {
        assert_eq!(crossfade_line(0).unwrap(), "crossfade 0");
        assert_eq!(crossfade_line(7).unwrap(), "crossfade 7");
        assert!(crossfade_line(-1).is_err());
    }

    #[test]
    fn replay_gain_mode_round_trips_its_four_words() {
        for mode in [
            ReplayGainMode::Off,
            ReplayGainMode::Track,
            ReplayGainMode::Album,
            ReplayGainMode::Auto,
        ] {
            assert_eq!(ReplayGainMode::parse(mode.as_str()), Some(mode));
        }
        assert_eq!(
            ReplayGainMode::parse(" track\n"),
            Some(ReplayGainMode::Track)
        );
        // Anything unknown stays unknown instead of silently becoming `off`.
        assert_eq!(ReplayGainMode::parse("loud"), None);
        assert_eq!(ReplayGainMode::parse(""), None);
        assert_eq!(ReplayGainMode::default(), ReplayGainMode::Off);
    }

    #[test]
    fn status_parses_the_new_fields_and_ignores_unknown_ones() {
        let st = Status::from(fields(&[
            ("state", "play"),
            ("volume", "62"),
            ("song", "17"),
            ("songid", "190"),
            ("elapsed", "4.029"),
            ("duration", "408.000"),
            ("playlistlength", "77"),
            ("repeat", "1"),
            ("random", "0"),
            ("single", "0"),
            ("consume", "0"),
            ("bitrate", "983"),
            ("audio", "44100:16:2"),
            ("crossfade", "5"),
            ("replay_gain_mode", "track"),
            ("playlist", "155"),
            ("error", "Failed to decode"),
            ("partition", "default"),
            ("something_new", "ignored"),
        ]));
        assert_eq!(st.state, "play");
        assert_eq!(st.volume, 62);
        assert_eq!(st.song, Some(17));
        assert_eq!(st.songid, Some(190));
        assert_eq!(st.elapsed, 4.029);
        assert_eq!(st.duration, 408.0);
        assert_eq!(st.queue_len, 77);
        assert!(st.repeat);
        assert!(!st.random);
        assert_eq!(st.bitrate, Some(983));
        assert_eq!(st.audio.as_deref(), Some("44100:16:2"));
        assert_eq!(st.crossfade, 5);
        assert_eq!(st.replay_gain_mode, "track");
        assert_eq!(st.playlist_version, 155);
        assert_eq!(st.error.as_deref(), Some("Failed to decode"));
    }

    #[test]
    fn status_defaults_when_the_daemon_says_little() {
        let st = Status::from(fields(&[("state", "stop"), ("playlist", "0")]));
        assert_eq!(st.volume, -1);
        assert_eq!(st.song, None);
        assert_eq!(st.crossfade, 0);
        assert_eq!(st.replay_gain_mode, "");
        assert_eq!(st.playlist_version, 0);
        // An empty `error:` is the daemon clearing it, not an error.
        assert_eq!(st.error, None);
        let cleared = Status::from(fields(&[("error", "")]));
        assert_eq!(cleared.error, None);
        // The old `time:` fallback for duration still works.
        let legacy = Status::from(fields(&[("time", "27:408")]));
        assert_eq!(legacy.duration, 408.0);
    }

    #[test]
    fn stats_parses_into_seconds() {
        let s = Stats::from(fields(&[
            ("uptime", "51424"),
            ("playtime", "16947"),
            ("artists", "2221"),
            ("albums", "2825"),
            ("songs", "40381"),
            ("db_playtime", "9409958"),
            ("db_update", "1791985270"),
            ("decoder", "ignored"),
        ]));
        assert_eq!(
            s,
            Stats {
                artists: 2221,
                albums: 2825,
                songs: 40381,
                uptime_secs: 51424,
                playtime_secs: 16947,
                db_playtime_secs: 9409958,
                db_update_secs: 1791985270,
            }
        );
        // A daemon that answers nothing yields zeroes, not a parse error.
        assert_eq!(Stats::from(Vec::new()), Stats::default());
    }

    // ---- scripted daemon ---------------------------------------------------------------
    //
    // The mutating calls need a peer that answers, but a test cannot talk to a real one: it would
    // edit somebody's queue. So the peer is a `TcpListener` on port 0 that reads one command at a
    // time, records the exact line and answers from a rule table. That is what makes "the wire line
    // is what we think it is" a checked fact instead of a comment.

    struct Fake {
        addr: String,
        seen: std::sync::Arc<std::sync::Mutex<Vec<String>>>,
        join: Option<std::thread::JoinHandle<()>>,
    }

    impl Fake {
        /// `rules` maps a command-line prefix to the reply it earns; anything else gets `OK`.
        fn start(rules: &'static [(&'static str, &'static str)]) -> Self {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind 127.0.0.1:0");
            let addr = listener.local_addr().expect("local_addr").to_string();
            let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let record = std::sync::Arc::clone(&seen);
            let join = std::thread::spawn(move || {
                let Ok((stream, _)) = listener.accept() else {
                    return;
                };
                let mut writer = stream.try_clone().expect("clone stream");
                let mut reader = BufReader::new(stream);
                writer.write_all(b"OK MPD 0.24.15\n").expect("banner");
                writer.flush().ok();
                loop {
                    let mut line = String::new();
                    match reader.read_line(&mut line) {
                        // 0 = client hung up (the test dropped it); the recording is complete.
                        Ok(0) | Err(_) => break,
                        Ok(_) => {}
                    }
                    let line = line.trim_end_matches(['\r', '\n']).to_string();
                    record.lock().expect("record lock").push(line.clone());
                    let reply = rules
                        .iter()
                        .find(|(prefix, _)| line.starts_with(prefix))
                        .map(|(_, text)| *text)
                        .unwrap_or("OK\n");
                    if writer.write_all(reply.as_bytes()).is_err() {
                        break;
                    }
                    writer.flush().ok();
                }
            });
            Self {
                addr,
                seen,
                join: Some(join),
            }
        }

        fn client(&self) -> Client {
            Client::connect(&self.addr, Duration::from_secs(2)).expect("connect to fake daemon")
        }

        /// The command lines the fake received. Drop the client first: the thread ends on EOF.
        fn seen(mut self) -> Vec<String> {
            if let Some(join) = self.join.take() {
                join.join().expect("fake daemon thread");
            }
            self.seen.lock().expect("record lock").clone()
        }
    }

    #[test]
    fn rm_looks_the_uri_up_and_deletes_by_position() {
        let fake = Fake::start(&[(
            "listplaylistinfo",
            "file: other/track.flac\nPos: 0\nfile: songs/track.flac\nPos: 2\nOK\n",
        )]);
        let mut client = fake.client();
        // A quote inside the name has to survive the round trip, hence the escaped form below.
        client
            .rm(r#"my "list""#, "songs/track.flac")
            .expect("rm succeeds against the fake");
        drop(client);
        assert_eq!(
            fake.seen(),
            vec![
                r#"listplaylistinfo "my \"list\"""#.to_string(),
                r#"playlistdelete "my \"list\"" 2"#.to_string(),
            ]
        );
    }

    #[test]
    fn rm_refuses_a_uri_the_playlist_does_not_hold() {
        let fake = Fake::start(&[("listplaylistinfo", "file: a.flac\nPos: 0\nOK\n")]);
        let mut client = fake.client();
        let err = client.rm("list", "b.flac").expect_err("uri is not there");
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
        drop(client);
        // No `playlistdelete` may follow the failed lookup.
        assert_eq!(fake.seen(), vec![r#"listplaylistinfo "list""#.to_string()]);
    }

    #[test]
    fn percent_seek_retries_in_seconds_when_the_daemon_refuses_the_percent_form() {
        let fake = Fake::start(&[
            ("seekcur 50%", "ACK [2@0] {seekcur} Float expected: 50%\n"),
            ("status", "duration: 200.000\nOK\n"),
            ("seekcur 100.000", "OK\n"),
        ]);
        let mut client = fake.client();
        client
            .seek_cur(SeekSpec::Percent(50.0))
            .expect("fallback lands the seek");
        drop(client);
        assert_eq!(
            fake.seen(),
            vec![
                "seekcur 50%".to_string(),
                "status".to_string(),
                "seekcur 100.000".to_string(),
            ]
        );
    }

    #[test]
    fn absolute_seek_sends_one_line_and_stops_on_ack() {
        let fake = Fake::start(&[("seekcur 12.5", "ACK [50@0] {seekcur} Not seekable\n")]);
        let mut client = fake.client();
        let err = client
            .seek_cur(SeekSpec::Absolute(12.5))
            .expect_err("ACK surfaces as an error");
        assert_eq!(err.kind(), io::ErrorKind::Other);
        assert!(err.to_string().contains("Not seekable"));
        drop(client);
        // Only absolute values are retried; a refused absolute seek is not silently rewritten.
        assert_eq!(fake.seen(), vec!["seekcur 12.5".to_string()]);
    }

    #[test]
    fn crossfade_sets_then_reads_the_value_back() {
        let fake = Fake::start(&[("crossfade 7", "OK\n"), ("crossfade", "crossfade: 7\nOK\n")]);
        let mut client = fake.client();
        let reported = client.crossfade(Some(7)).expect("set crossfade");
        assert_eq!(reported, Some(7));
        drop(client);
        assert_eq!(
            fake.seen(),
            vec!["crossfade 7".to_string(), "crossfade".to_string()]
        );
    }

    #[test]
    fn crossfade_falls_back_to_status_when_the_read_form_is_refused() {
        let fake = Fake::start(&[
            (
                "crossfade",
                "ACK [2@0] {crossfade} wrong number of arguments for \"crossfade\"\n",
            ),
            ("status", "crossfade: 4\nOK\n"),
            // `status` on 0.24 carries no crossfade field; the second scenario below covers that.
        ]);
        let mut client = fake.client();
        assert_eq!(client.crossfade(None).expect("read crossfade"), Some(4));
        drop(client);
        assert_eq!(
            fake.seen(),
            vec!["crossfade".to_string(), "status".to_string()]
        );
    }

    #[test]
    fn crossfade_reports_nothing_when_the_daemon_keeps_it_secret() {
        let fake = Fake::start(&[(
            "crossfade",
            "ACK [2@0] {crossfade} wrong number of arguments for \"crossfade\"\n",
        )]);
        let mut client = fake.client();
        // Both the read form and `status` are silent: `None` means "not reported", not zero.
        assert_eq!(client.crossfade(None).expect("read crossfade"), None);
        drop(client);
        assert_eq!(
            fake.seen(),
            vec!["crossfade".to_string(), "status".to_string()]
        );
    }

    #[test]
    fn tag_calls_send_id_tag_and_quoted_value() {
        let fake = Fake::start(&[("addtagid 7 Title", "OK\n"), ("cleartagid 7 Title", "OK\n")]);
        let mut client = fake.client();
        client.addtagid(7, "Title", "A\"B").expect("addtagid");
        client.cleartagid(7, "Title").expect("cleartagid");
        drop(client);
        assert_eq!(
            fake.seen(),
            vec![
                "addtagid 7 Title \"A\\\"B\"".to_string(),
                "cleartagid 7 Title".to_string(),
            ]
        );
    }

    #[test]
    fn update_and_rescan_read_the_queue_job_id() {
        let fake = Fake::start(&[
            ("update", "updating_db: 9\nOK\n"),
            ("rescan", "updating_db: 10\nOK\n"),
        ]);
        let mut client = fake.client();
        assert_eq!(client.update(None).expect("update"), 9);
        assert_eq!(client.rescan(Some("a b")).expect("rescan"), 10);
        drop(client);
        assert_eq!(
            fake.seen(),
            vec!["update".to_string(), "rescan \"a b\"".to_string()]
        );
    }

    #[test]
    fn replay_gain_status_round_trips_and_rejects_unknown_words() {
        let fake = Fake::start(&[
            ("replay_gain_mode track", "OK\n"),
            ("replay_gain_status", "replay_gain_mode: track\nOK\n"),
        ]);
        let mut client = fake.client();
        client
            .replay_gain_mode(ReplayGainMode::Track)
            .expect("set mode");
        assert_eq!(
            client.replay_gain_status().expect("read mode"),
            ReplayGainMode::Track
        );
        drop(client);
        assert_eq!(
            fake.seen(),
            vec![
                "replay_gain_mode track".to_string(),
                "replay_gain_status".to_string(),
            ]
        );
    }

    #[test]
    fn update_job_id_is_read_from_the_reply() {
        let reply = fields(&[("updating_db", "2")]);
        assert_eq!(field_u64(&reply, "updating_db"), Some(2));
        assert_eq!(field(&reply, "updating_db"), Some("2"));
        assert_eq!(field_u64(&fields(&[]), "updating_db"), None);
    }
}
