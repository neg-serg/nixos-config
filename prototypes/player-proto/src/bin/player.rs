//! rmpc-inspired MPD frontend on the Vulkan UI stack.
//!
//! Layout: top bar (tabs + connection), left library pane, centre queue, right now-playing
//! panel with album art, progress and volume, bottom key hints. Everything is drawn with
//! three pipelines (SDF shapes, glyph atlas, textured quads); MPD talks over plain TCP in a
//! worker thread, so the UI never blocks on the socket.

use std::sync::mpsc::{Receiver, Sender, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

use ash::vk;
use winit::event::{ElementState, KeyEvent, MouseScrollDelta, WindowEvent};
use winit::keyboard::{Key, NamedKey};

use player_proto::gpu::{create_gpu, InitTiming};
use player_proto::mpd::{Client, Entry, Song, Status};
use player_proto::scene::DrawList;
use player_proto::text::Fonts;
use player_proto::theme::{self};
use player_proto::Timing;

// ---------------------------------------------------------------- palette

type Rgba = [f32; 4];

const BG: Rgba = [0.043, 0.051, 0.067, 1.0];
const BG_TOP: Rgba = [0.063, 0.075, 0.098, 1.0];
const PANEL: Rgba = [0.071, 0.082, 0.106, 1.0];
const PANEL_HI: Rgba = [0.094, 0.110, 0.141, 1.0];
const BORDER: Rgba = [1.0, 1.0, 1.0, 0.06];
const TEXT: Rgba = [0.906, 0.925, 0.957, 1.0];
const DIM: Rgba = [0.545, 0.596, 0.663, 1.0];
const FAINT: Rgba = [0.353, 0.396, 0.463, 1.0];
const ACCENT: Rgba = [0.353, 0.812, 1.0, 1.0];
const ACCENT2: Rgba = [0.478, 0.545, 1.0, 1.0];
const ACCENT_DIM: Rgba = [0.353, 0.812, 1.0, 0.16];
const PLAYING_BG: Rgba = [0.353, 0.812, 1.0, 0.10];

fn rgba(r: f32, g: f32, b: f32, a: f32) -> Rgba {
    [r, g, b, a]
}

// ---------------------------------------------------------------- mpd worker

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Collection {
    Artist,
    Album,
    Playlist,
}

#[derive(Debug)]
enum Cmd {
    PlayIndex(usize),
    DeleteIndex(usize),
    ClearQueue,
    JumpToCurrent,
    PlayUri(String),
    Toggle,
    Pause(bool),
    Next,
    Prev,
    Stop,
    Seek(f64),
    SeekRelative(f64),
    Volume(i32),
    VolumeRelative(i32),
    Repeat(bool),
    Random(bool),
    Single(bool),
    Consume(bool),
    LoadDir(String),
    LoadArtists,
    LoadAlbums,
    LoadPlaylists,
    PlayCollection { kind: Collection, name: String },
    EnqueueCollection { kind: Collection, name: String },
    MoveTrack { from: usize, to: usize },
    SavePlaylist(String),
    DeletePlaylist(String),
    RenamePlaylist { from: String, to: String },
    AddToPlaylist { name: String, uri: String },
    RefreshOutputs,
    SetOutput { id: u32, on: bool },
    EnqueueDir(String),
    Search(String),
    Refresh,
}

#[derive(Debug)]
enum Update {
    Status {
        status: Status,
        song: Option<Song>,
    },
    Queue(Vec<Song>),
    Library {
        path: String,
        entries: Vec<Entry>,
    },
    Art {
        uri: String,
        w: u32,
        h: u32,
        rgba: Vec<u8>,
    },
    Search(Vec<Song>),
    Artists(Vec<String>),
    Albums(Vec<String>),
    Playlists(Vec<String>),
    Outputs(Vec<player_proto::mpd::Output>),
    Connected(bool),
    Error(String),
}

/// MPD only speaks URIs relative to its music_directory, and `config` is refused for
/// non-local clients, so the few conventional roots are probed instead.
fn resolve_cover(uri: &str) -> Option<Vec<u8>> {
    let mut roots: Vec<String> = Vec::new();
    if let Ok(dir) = std::env::var("MPD_MUSIC_DIR") {
        roots.push(dir);
    }
    if let Ok(home) = std::env::var("HOME") {
        roots.push(format!("{home}/music"));
        roots.push(format!("{home}/Music"));
    }
    roots.push("/music".to_string());
    roots.push("/var/lib/mpd/music".to_string());
    for root in roots {
        let path = format!("{}/{}", root.trim_end_matches('/'), uri);
        if std::path::Path::new(&path).is_file() {
            if let Some(pic) = player_proto::cover::embedded_picture(&path) {
                return Some(pic);
            }
        }
    }
    None
}

fn spawn_mpd_worker(addr: String, tx: Sender<Update>, rx_cmd: Receiver<Cmd>) {
    let dry_run = std::env::var("PLAYER_DRY_RUN").is_ok();
    thread::spawn(move || {
        let mut client: Option<Client> = None;
        let mut last_queue_len: Option<usize> = None;
        let mut last_art_uri: Option<String> = None;
        let mut connected = false;
        loop {
            if client.is_none() {
                match Client::connect(&addr, Duration::from_millis(2000)) {
                    Ok(c) => {
                        client = Some(c);
                        connected = true;
                        let _ = tx.send(Update::Connected(true));
                        let _ = tx.send(Update::Library {
                            path: "/".into(),
                            entries: vec![],
                        });
                    }
                    Err(e) => {
                        if connected {
                            connected = false;
                            let _ = tx.send(Update::Connected(false));
                            let _ = tx.send(Update::Error(format!("{e}")));
                        }
                        thread::sleep(Duration::from_secs(2));
                        continue;
                    }
                }
            }
            let c = client.as_mut().unwrap();

            while let Ok(cmd) = rx_cmd.try_recv() {
                if dry_run {
                    // Verification mode: read-only commands still run (lists have to load for
                    // the UI to be testable), state-changing ones are only recorded.
                    let read_only = matches!(
                        cmd,
                        Cmd::LoadDir(_)
                            | Cmd::LoadArtists
                            | Cmd::LoadAlbums
                            | Cmd::LoadPlaylists
                            | Cmd::RefreshOutputs
                            | Cmd::Search(_)
                            | Cmd::Refresh
                    );
                    if !read_only {
                        eprintln!("[dry-run] {cmd:?}");
                        continue;
                    }
                }
                let res: Result<(), player_proto::mpd::MpdError> = (|| {
                    match cmd {
                        Cmd::PlayIndex(i) => c.play_index(i),
                        Cmd::DeleteIndex(i) => c.command(&format!("delete {i}")).map(|_| ()),
                        Cmd::ClearQueue => c.command("clear").map(|_| ()),
                        Cmd::JumpToCurrent => Ok(()),
                        Cmd::PlayUri(uri) => {
                            c.command(&format!("clear"))?;
                            c.command(&format!("add \"{}\"", uri.replace('"', "\\\"")))?;
                            c.play()
                        }
                        Cmd::Toggle => {
                            let playing = c.status().map(|s| s.state == "play").unwrap_or(false);
                            c.toggle(playing)
                        }
                        Cmd::Pause(on) => c.pause(on),
                        Cmd::Next => c.next(),
                        Cmd::Prev => c.prev(),
                        Cmd::Stop => c.stop(),
                        Cmd::Seek(pos) => c.seek(pos),
                        Cmd::SeekRelative(delta) => {
                            let st = c.status()?;
                            c.seek((st.elapsed + delta).max(0.0))
                        }
                        Cmd::Volume(v) => c.set_volume(v),
                        Cmd::VolumeRelative(delta) => {
                            let st = c.status()?;
                            let base = if st.volume < 0 { 100 } else { st.volume };
                            c.set_volume(base + delta)
                        }
                        Cmd::Repeat(on) => c.repeat(on),
                        Cmd::Random(on) => c.random(on),
                        Cmd::Single(on) => c.single(on),
                        Cmd::Consume(on) => c.consume(on),
                        Cmd::LoadDir(path) => {
                            let entries = c.list_dir(&path)?;
                            let _ = tx.send(Update::Library { path, entries });
                            Ok(())
                        }
                        Cmd::EnqueueDir(uri) => {
                            if uri.ends_with('/') {
                                c.command(&format!("add \"{}\"", uri.replace('"', "\\\"")))?;
                            } else {
                                c.command(&format!("add \"{}\"", uri.replace('"', "\\\"")))?;
                            }
                            Ok(())
                        }
                        Cmd::Search(q) => {
                            let found = c.search(&q)?;
                            let _ = tx.send(Update::Search(found));
                            Ok(())
                        }
                        Cmd::LoadArtists => {
                            let v = c.list_tag("Artist")?;
                            let _ = tx.send(Update::Artists(v));
                            Ok(())
                        }
                        Cmd::LoadAlbums => {
                            let v = c.list_tag("Album")?;
                            let _ = tx.send(Update::Albums(v));
                            Ok(())
                        }
                        Cmd::LoadPlaylists => {
                            let v = c.playlists()?;
                            let _ = tx.send(Update::Playlists(v));
                            Ok(())
                        }
                        Cmd::PlayCollection { kind, name } => {
                            let songs = match kind {
                                Collection::Artist => c.find("Artist", &name)?,
                                Collection::Album => c.find("Album", &name)?,
                                Collection::Playlist => c.playlist_songs(&name)?,
                            };
                            let uris: Vec<String> = songs.into_iter().map(|s| s.file).collect();
                            c.add_and_play(&uris)
                        }
                        Cmd::EnqueueCollection { kind, name } => {
                            let songs = match kind {
                                Collection::Artist => c.find("Artist", &name)?,
                                Collection::Album => c.find("Album", &name)?,
                                Collection::Playlist => c.playlist_songs(&name)?,
                            };
                            let uris: Vec<String> = songs.into_iter().map(|s| s.file).collect();
                            c.append(&uris)
                        }
                        Cmd::MoveTrack { from, to } => {
                            c.move_track(from, to)?;
                            last_queue_len = None; // a move does not change playlistlength
                            Ok(())
                        }
                        Cmd::SavePlaylist(name) => {
                            c.save_playlist(&name)?;
                            let v = c.playlists()?;
                            let _ = tx.send(Update::Playlists(v));
                            Ok(())
                        }
                        Cmd::DeletePlaylist(name) => {
                            c.delete_playlist(&name)?;
                            let v = c.playlists()?;
                            let _ = tx.send(Update::Playlists(v));
                            Ok(())
                        }
                        Cmd::RenamePlaylist { from, to } => {
                            c.rename_playlist(&from, &to)?;
                            let v = c.playlists()?;
                            let _ = tx.send(Update::Playlists(v));
                            Ok(())
                        }
                        Cmd::AddToPlaylist { name, uri } => c.playlist_add(&name, &uri),
                        Cmd::RefreshOutputs => {
                            let v = c.outputs()?;
                            let _ = tx.send(Update::Outputs(v));
                            Ok(())
                        }
                        Cmd::SetOutput { id, on } => {
                            c.set_output(id, on)?;
                            let v = c.outputs()?;
                            let _ = tx.send(Update::Outputs(v));
                            Ok(())
                        }
                        Cmd::Refresh => Ok(()),
                    }
                })();
                if let Err(e) = res {
                    let _ = tx.send(Update::Error(format!("{e}")));
                }
            }

            match c.status() {
                Ok(status) => {
                    let song = c.current_song().unwrap_or(None);
                    if let Some(s) = &song {
                        if last_art_uri.as_deref() != Some(s.file.as_str()) {
                            last_art_uri = Some(s.file.clone());
                            if let Some(bytes) = resolve_cover(&s.file) {
                                if let Ok(img) = image::load_from_memory(&bytes) {
                                    let img = img.to_rgba8();
                                    let (w, h) = img.dimensions();
                                    let _ = tx.send(Update::Art {
                                        uri: s.file.clone(),
                                        w,
                                        h,
                                        rgba: img.into_raw(),
                                    });
                                }
                            }
                        }
                    }
                    if last_queue_len != Some(status.queue_len) {
                        last_queue_len = Some(status.queue_len);
                        if let Ok(q) = c.queue() {
                            let _ = tx.send(Update::Queue(q));
                        }
                    }
                    let _ = tx.send(Update::Status { status, song });
                }
                Err(_) => {
                    client = None;
                    connected = false;
                    let _ = tx.send(Update::Connected(false));
                    continue;
                }
            }
            thread::sleep(Duration::from_millis(300));
        }
    });
}

// ---------------------------------------------------------------- model

/// Where keystrokes go. rmpc's model in miniature: a normal mode, two prompt modes and help.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum InputMode {
    Normal,
    Search,
    Command,
    Help,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Group {
    Move,
    Playback,
    Panes,
    Modes,
    App,
}

/// Single source of truth for both the handler and the `?` overlay.
struct KeyHint {
    keys: &'static str,
    action: &'static str,
    group: Group,
}

/// ЙЦУКЕН -> QWERTY for the keys the user's rmpc config also duplicates in Cyrillic, so the
/// player works with a Russian layout active.
fn latinize(ch: &str) -> Option<&'static str> {
    Some(match ch {
        "з" | "З" => "p",
        "й" | "Й" => "q",
        "ы" | "Ы" => "s",
        "г" | "Г" => "u",
        "ц" | "Ц" => "w",
        "и" | "И" => "b",
        "а" | "А" => "f",
        "щ" | "Щ" => "o",
        "я" | "Я" => "z",
        "к" | "К" => "r",
        "н" | "Н" => "y",
        "о" | "О" => "j",
        "л" | "Л" => "k",
        "п" | "П" => "g",
        "р" | "Р" => "h",
        "ш" | "Ш" => "i",
        "д" | "Д" => "l",
        "ф" | "Ф" => "a",
        "в" | "В" => "d",
        "т" | "Т" => "n",
        "с" | "С" => "c",
        "м" | "М" => "v",
        "ч" | "Ч" => "x",
        _ => return None,
    })
}

/// Mirrors the user's own rmpc keymap (`~/.config/rmpc/config.ron`): global, navigation and
/// queue sections, plus the Cyrillic duplicates that config already carries. Keys that exist in
/// rmpc but have no counterpart here (outputs, playlists, rename, move) are listed as such.
const KEYMAP: &[KeyHint] = &[
    KeyHint {
        keys: "j / k",
        action: "вниз / вверх (цифра N — повторить)",
        group: Group::Move,
    },
    KeyHint {
        keys: "ctrl+d / ctrl+u",
        action: "полстраницы вниз / вверх",
        group: Group::Move,
    },
    KeyHint {
        keys: "g / G",
        action: "в начало / в конец",
        group: Group::Move,
    },
    KeyHint {
        keys: "ctrl+n / ctrl+p",
        action: "вниз / вверх (emacs)",
        group: Group::Move,
    },
    KeyHint {
        keys: "ctrl+a / ctrl+e",
        action: "в начало / в конец (emacs)",
        group: Group::Move,
    },
    KeyHint {
        keys: "tab / shift+tab",
        action: "следующая / предыдущая панель",
        group: Group::Panes,
    },
    KeyHint {
        keys: "1 / 0 / ?",
        action: "очередь / библиотека / поиск",
        group: Group::Panes,
    },
    KeyHint {
        keys: "enter",
        action: "играть выбранное / войти в каталог",
        group: Group::Playback,
    },
    KeyHint {
        keys: "p",
        action: "пауза / продолжить",
        group: Group::Playback,
    },
    KeyHint {
        keys: "s",
        action: "стоп",
        group: Group::Playback,
    },
    KeyHint {
        keys: "> / <",
        action: "следующий / предыдущий трек",
        group: Group::Playback,
    },
    KeyHint {
        keys: "f / b",
        action: "+5 / −5 секунд",
        group: Group::Playback,
    },
    KeyHint {
        keys: "= / -",
        action: "громкость + / − шаг",
        group: Group::Playback,
    },
    KeyHint {
        keys: "space",
        action: "в очереди — к текущему треку, в библиотеке — в очередь",
        group: Group::Playback,
    },
    KeyHint {
        keys: "z / r / y / R",
        action: "repeat / random / single / consume",
        group: Group::Modes,
    },
    KeyHint {
        keys: "d / C",
        action: "удалить трек / очистить очередь (дважды)",
        group: Group::Modes,
    },
    KeyHint {
        keys: "/",
        action: "поиск",
        group: Group::App,
    },
    KeyHint {
        keys: ":",
        action: "команда",
        group: Group::App,
    },
    KeyHint {
        keys: "w",
        action: "эта справка",
        group: Group::App,
    },
    KeyHint {
        keys: "u / U",
        action: "перечитать библиотеку",
        group: Group::App,
    },
    KeyHint {
        keys: "t",
        action: "сменить тему (наше дополнение)",
        group: Group::App,
    },
    KeyHint {
        keys: "q",
        action: "выход",
        group: Group::App,
    },
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Destructive {
    DeleteSelected,
    ClearQueue,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Pane {
    Queue,
    Library,
    Artists,
    Albums,
    Playlists,
    Search,
}

/// Interactive rectangles produced by the last frame; the mouse handler walks them in reverse
/// so the topmost element wins.
#[derive(Clone, Copy, Debug)]
struct HitArea {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    action: Hit,
}

impl HitArea {
    fn contains(&self, px: f32, py: f32) -> bool {
        px >= self.x && px <= self.x + self.w && py >= self.y && py <= self.y + self.h
    }
}

#[derive(Clone, Copy, Debug)]
enum Hit {
    Tab(Pane),
    Row(Pane, usize),
    Transport(i8),
    Chip(u8),
    Seek(f32),
    Volume(f32),
    Output(usize),
    CloseOverlay,
}

fn hit(hits: &mut Vec<HitArea>, x: f32, y: f32, w: f32, h: f32, action: Hit) {
    hits.push(HitArea { x, y, w, h, action });
}

/// A list of names (artists, albums, playlists) with its own cursor and smooth scroll.
#[derive(Default)]
struct Picker {
    items: Vec<String>,
    sel: usize,
    scroll: f32,
    target: f32,
}

impl Picker {
    fn set(&mut self, items: Vec<String>) {
        self.items = items;
        self.sel = 0;
        self.scroll = 0.0;
        self.target = 0.0;
    }

    fn len(&self) -> usize {
        self.items.len()
    }

    fn selected(&self) -> Option<&String> {
        self.items.get(self.sel)
    }

    fn move_by(&mut self, delta: i32, visible: usize) {
        if self.items.is_empty() {
            return;
        }
        let next = (self.sel as i32 + delta).clamp(0, self.items.len() as i32 - 1) as usize;
        self.sel = next;
        self.follow(visible);
    }

    fn jump(&mut self, end: bool, visible: usize) {
        if self.items.is_empty() {
            return;
        }
        self.sel = if end { self.items.len() - 1 } else { 0 };
        self.follow(visible);
    }

    fn follow(&mut self, visible: usize) {
        let sel = self.sel as f32;
        let min = (sel - visible as f32 + 1.0).max(0.0);
        self.target = self.target.clamp(min, sel);
    }
}

struct Model {
    status: Status,
    current: Option<Song>,
    queue: Vec<Song>,
    queue_sel: usize,
    queue_scroll: f32,
    queue_scroll_target: f32,
    artists: Picker,
    albums: Picker,
    playlists: Picker,
    outputs: Vec<player_proto::mpd::Output>,
    outputs_open: bool,
    outputs_focus: usize,
    /// Some(uri) while the Playlists pane is in "add this song" mode (`a`).
    pick_target: Option<String>,
    lib_path: String,
    lib_entries: Vec<Entry>,
    lib_filter: String,
    lib_sel: usize,
    lib_scroll: f32,
    lib_scroll_target: f32,
    view: Pane,
    search_input: String,
    search_active: bool,
    mode: InputMode,
    cmdline: String,
    /// Numeric prefix for the next motion (`3j`), cleared after use.
    count: Option<u32>,
    search_results: Vec<Song>,
    art: Option<(u32, u32, Vec<u8>)>,
    art_uri: String,
    connected: bool,
    user_moved: bool,
    /// Pending destructive action: (label, action kind, timestamp). A second key press within
    /// three seconds performs it; otherwise the toast just asks for confirmation.
    confirm: Option<(String, Destructive, Instant)>,
    toast: Option<(String, Instant)>,
    last_update: Instant,
    elapsed_base: f64,
    elapsed_at: Instant,
}

impl Model {
    fn new() -> Self {
        Self {
            status: Status::default(),
            current: None,
            queue: Vec::new(),
            queue_sel: 0,
            queue_scroll: 0.0,
            queue_scroll_target: 0.0,
            artists: Picker::default(),
            albums: Picker::default(),
            playlists: Picker::default(),
            outputs: Vec::new(),
            outputs_open: false,
            outputs_focus: 0,
            pick_target: None,
            lib_path: "/".into(),
            lib_entries: Vec::new(),
            lib_filter: std::env::var("PLAYER_FILTER").unwrap_or_default(),
            lib_sel: 0,
            lib_scroll: 0.0,
            lib_scroll_target: 0.0,
            view: match std::env::var("PLAYER_VIEW").as_deref() {
                Ok("library") => Pane::Library,
                Ok("search") => Pane::Search,
                _ => Pane::Queue,
            },
            search_input: std::env::var("PLAYER_SEARCH").unwrap_or_default(),
            search_active: false,
            mode: InputMode::Normal,
            cmdline: String::new(),
            count: None,
            search_results: Vec::new(),
            art: None,
            art_uri: String::new(),
            connected: false,
            user_moved: false,
            confirm: None,
            toast: None,
            last_update: Instant::now(),
            elapsed_base: 0.0,
            elapsed_at: Instant::now(),
        }
    }

    /// Elapsed time extrapolated from the last MPD snapshot, so the progress bar moves
    /// smoothly between polls instead of jumping every 300 ms.
    fn elapsed(&self) -> f64 {
        if self.status.state == "play" {
            self.elapsed_base + self.elapsed_at.elapsed().as_secs_f64()
        } else {
            self.elapsed_base
        }
    }

    fn duration(&self) -> f64 {
        if self.status.duration > 0.0 {
            self.status.duration
        } else {
            self.current.as_ref().map(|s| s.duration).unwrap_or(0.0)
        }
    }

    fn apply(&mut self, update: Update) {
        match update {
            Update::Status { status, song } => {
                // `select_current_song_on_change: false` in the user's rmpc config: the cursor
                // stays where it is when the track changes. Space jumps to the current track.
                if (status.elapsed - self.elapsed_base).abs() > 0.05
                    || status.state != self.status.state
                {
                    self.elapsed_base = status.elapsed;
                    self.elapsed_at = Instant::now();
                }
                if self.status.state != "play" && status.state == "play" {
                    self.elapsed_at = Instant::now();
                }
                self.status = status;
                self.current = song;
                self.last_update = Instant::now();
            }
            Update::Queue(q) => {
                let first_load = self.queue.is_empty();
                if self.queue_sel >= q.len() {
                    self.queue_sel = q.len().saturating_sub(1);
                }
                // Land on the playing track instead of row 0 the first time the queue arrives.
                if first_load {
                    if let Some(playing) = self.status.song {
                        if playing < q.len() {
                            self.queue_sel = playing;
                            self.queue_scroll_target = playing as f32;
                            self.queue_scroll = playing.saturating_sub(3) as f32;
                        }
                    }
                }
                self.queue = q;
            }
            Update::Library { path, entries } => {
                self.lib_path = path;
                self.lib_entries = entries;
                self.lib_filter.clear();
                self.lib_sel = 0;
                self.lib_scroll = 0.0;
                self.lib_scroll_target = 0.0;
            }
            Update::Art { uri, w, h, rgba } => {
                self.art_uri = uri;
                self.art = Some((w, h, rgba));
            }
            Update::Artists(v) => self.artists.set(v),
            Update::Albums(v) => self.albums.set(v),
            Update::Playlists(v) => self.playlists.set(v),
            Update::Outputs(v) => self.outputs = v,
            Update::Search(results) => {
                self.search_results = results;
                self.view = Pane::Search;
            }
            Update::Connected(on) => {
                self.connected = on;
                if !on {
                    self.toast = Some(("MPD отключён".to_string(), Instant::now()));
                }
            }
            Update::Error(e) => {
                self.toast = Some((e, Instant::now()));
            }
        }
    }
}

// ---------------------------------------------------------------- app

struct App {
    window: Option<winit::window::Window>,
    gpu: Option<player_proto::gpu::Gpu>,
    fonts: Option<Fonts>,
    model: Model,
    tx: Sender<Cmd>,
    rx: Receiver<Update>,
    timing: Timing,
    frames: u64,
    shot_path: Option<String>,
    shot_frames: u32,
    bench_frames: Option<u32>,
    render_size: Option<(u32, u32)>,
    keys: Vec<String>,
    shot_seq: Option<String>,
    key_cursor: usize,
    pending_shot: bool,
    dump_state_each_key: bool,
    /// Last swapchain recreation, used to rate-limit resize storms.
    last_resize: Instant,
    /// Monitor scale factor, refreshed from winit on every scale/resize event.
    scale: f32,
    /// Frame at which a scripted run exits; a short linger lets the MPD worker drain the
    /// commands the script produced (it polls every 300 ms).
    exit_frame: Option<u64>,
    hits: Vec<HitArea>,
    cursor: (f32, f32),
    last_click: Option<(Instant, Pane, usize)>,
    art_uploaded: String,
    started: Instant,
    theme_name: String,
}

impl App {
    fn new(tx: Sender<Cmd>, rx: Receiver<Update>) -> Self {
        Self {
            window: None,
            gpu: None,
            fonts: None,
            model: Model::new(),
            tx,
            rx,
            timing: Timing::new(),
            frames: 0,
            shot_path: std::env::args()
                .find(|a| a.starts_with("--shot="))
                .map(|a| a[7..].to_string()),
            shot_frames: std::env::args()
                .find(|a| a.starts_with("--shot-after="))
                .and_then(|a| a[13..].parse().ok())
                .unwrap_or(120),
            render_size: std::env::args()
                .find(|a| a.starts_with("--render-size="))
                .and_then(|a| {
                    let (w, h) = a[14..].split_once('x')?;
                    Some((w.parse().ok()?, h.parse().ok()?))
                }),
            keys: std::env::args()
                .find(|a| a.starts_with("--keys="))
                .map(|a| a[7..].split(',').map(|s| s.to_string()).collect())
                .unwrap_or_default(),
            shot_seq: std::env::args()
                .find(|a| a.starts_with("--shot-seq="))
                .map(|a| a[11..].to_string()),
            key_cursor: 0,
            pending_shot: false,
            dump_state_each_key: std::env::var("PLAYER_DUMP_STATE").is_ok(),
            last_resize: Instant::now() - Duration::from_secs(1),
            scale: 1.0,
            exit_frame: None,
            hits: Vec::new(),
            cursor: (0.0, 0.0),
            last_click: None,
            bench_frames: std::env::args()
                .find(|a| a.starts_with("--bench="))
                .and_then(|a| a[8..].parse().ok()),
            art_uploaded: String::new(),
            started: Instant::now(),
            theme_name: std::env::args()
                .find(|a| a.starts_with("--theme="))
                .map(|a| a[8..].to_string())
                .unwrap_or_else(|| "dark".to_string()),
        }
    }

    fn drain_updates(&mut self) {
        loop {
            match self.rx.try_recv() {
                Ok(u) => {
                    if std::env::var("PLAYER_DEBUG_UPDATES").is_ok() {
                        let tag = match &u {
                            Update::Status { .. } => "status",
                            Update::Queue(q) => {
                                return {
                                    eprintln!("[update] queue({})", q.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Library { entries, .. } => {
                                return {
                                    eprintln!("[update] library({})", entries.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Artists(v) => {
                                return {
                                    eprintln!("[update] artists({})", v.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Albums(v) => {
                                return {
                                    eprintln!("[update] albums({})", v.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Playlists(v) => {
                                return {
                                    eprintln!("[update] playlists({})", v.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Outputs(v) => {
                                return {
                                    eprintln!("[update] outputs({})", v.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Search(v) => {
                                return {
                                    eprintln!("[update] search({})", v.len());
                                    self.model.apply(u)
                                }
                            }
                            Update::Art { .. } => "art",
                            Update::Connected(b) => {
                                return {
                                    eprintln!("[update] connected({b})");
                                    self.model.apply(u)
                                }
                            }
                            Update::Error(e) => {
                                return {
                                    eprintln!("[update] error({e})");
                                    self.model.apply(u)
                                }
                            }
                        };
                        eprintln!("[update] {tag}");
                    }
                    self.model.apply(u)
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => break,
            }
        }
    }

    fn clamp_selection(&mut self) {
        let visible = self.visible_rows();
        let len = self.current_list_len();
        if len == 0 {
            return;
        }
        if self.model.queue_sel >= len {
            self.model.queue_sel = len - 1;
        }
        let sel_scroll = match self.model.view {
            Pane::Queue => self.model.queue_sel as f32,
            _ => self.model.lib_sel as f32,
        };
        let min_scroll = (sel_scroll - visible as f32 + 1.0).max(0.0);
        let max_scroll = sel_scroll;
        let cur = match self.model.view {
            Pane::Queue => &mut self.model.queue_scroll_target,
            _ => &mut self.model.lib_scroll_target,
        };
        *cur = (*cur).clamp(min_scroll, max_scroll);
    }

    /// Layout size in logical units: the surface is physical, the UI is authored in CSS-ish px.
    fn logical_size(&self) -> (u32, u32) {
        match self.gpu.as_ref() {
            Some(g) => (
                (g.extent.width as f32 / self.scale).round().max(1.0) as u32,
                (g.extent.height as f32 / self.scale).round().max(1.0) as u32,
            ),
            None => (1440, 900),
        }
    }

    fn visible_rows(&self) -> usize {
        let (_, h) = self.logical_size();
        let row = player_proto::theme::GEOM.row_h;
        (((h as f32 - 190.0) / row).floor() as usize).max(3)
    }

    /// Artists/Albums/Playlists are all name lists; the queue, library and search keep their
    /// own shapes, so this returns `None` for those.
    fn active_picker(&self) -> Option<&Picker> {
        match self.model.view {
            Pane::Artists => Some(&self.model.artists),
            Pane::Albums => Some(&self.model.albums),
            Pane::Playlists => Some(&self.model.playlists),
            _ => None,
        }
    }

    fn active_picker_mut(&mut self) -> Option<&mut Picker> {
        match self.model.view {
            Pane::Artists => Some(&mut self.model.artists),
            Pane::Albums => Some(&mut self.model.albums),
            Pane::Playlists => Some(&mut self.model.playlists),
            _ => None,
        }
    }

    fn collection_kind(&self) -> Option<Collection> {
        match self.model.view {
            Pane::Artists => Some(Collection::Artist),
            Pane::Albums => Some(Collection::Album),
            Pane::Playlists => Some(Collection::Playlist),
            _ => None,
        }
    }

    fn current_list_len(&self) -> usize {
        if let Some(p) = self.active_picker() {
            return p.len();
        }
        match self.model.view {
            Pane::Queue => self.model.queue.len(),
            Pane::Library => self.filtered_library().len(),
            Pane::Search => self.model.search_results.len(),
            _ => 0,
        }
    }

    /// Library entries after the incremental filter (dirs and songs alike).
    fn filtered_library(&self) -> Vec<&Entry> {
        let needle = self.model.lib_filter.to_lowercase();
        self.model
            .lib_entries
            .iter()
            .filter(|e| {
                if needle.is_empty() {
                    return true;
                }
                let name = match e {
                    Entry::Dir { name, .. } => name,
                    Entry::Song { song, .. } => &song.title,
                };
                name.to_lowercase().contains(&needle)
            })
            .collect()
    }

    fn handle_key(&mut self, event: &KeyEvent, shift: bool, ctrl: bool) {
        if event.state != ElementState::Pressed {
            return;
        }
        let key = event.logical_key.clone();
        self.handle_key_spec(&key, shift, ctrl);
    }

    /// The keyboard state machine, separated from winit's event type so scripted runs
    /// (`--keys=`) exercise exactly the same path as a real keyboard.
    ///
    /// Modes mirror rmpc: Normal for navigation, `/` for search, `:` for commands, `?` for help.
    /// A numeric prefix (`3j`) applies to the next motion, like vim.
    fn handle_key_spec(&mut self, key: &Key, shift: bool, ctrl: bool) {
        match self.model.mode {
            InputMode::Help => {
                self.model.mode = InputMode::Normal;
                return;
            }
            InputMode::Search => {
                match key {
                    Key::Named(NamedKey::Escape) => {
                        self.model.mode = InputMode::Normal;
                        self.model.search_input.clear();
                        self.model.view = Pane::Queue;
                    }
                    Key::Named(NamedKey::Enter) => {
                        let q = self.model.search_input.clone();
                        if !q.is_empty() {
                            let _ = self.tx.send(Cmd::Search(q));
                        }
                        self.model.mode = InputMode::Normal;
                    }
                    Key::Named(NamedKey::Backspace) => {
                        self.model.search_input.pop();
                    }
                    Key::Character(ch) => self.model.search_input.push_str(ch),
                    _ => {}
                }
                return;
            }
            InputMode::Command => {
                match key {
                    Key::Named(NamedKey::Escape) => {
                        self.model.mode = InputMode::Normal;
                        self.model.cmdline.clear();
                    }
                    Key::Named(NamedKey::Enter) => {
                        let line = std::mem::take(&mut self.model.cmdline);
                        self.model.mode = InputMode::Normal;
                        self.run_command(&line);
                    }
                    Key::Named(NamedKey::Backspace) => {
                        self.model.cmdline.pop();
                    }
                    Key::Character(ch) => self.model.cmdline.push_str(ch),
                    _ => {}
                }
                return;
            }
            InputMode::Normal => {}
        }

        // The outputs overlay owns the keyboard while it is open.
        if self.model.outputs_open {
            let last = self.model.outputs.len().saturating_sub(1);
            match key {
                Key::Named(NamedKey::Escape) => {
                    self.model.outputs_open = false;
                    return;
                }
                Key::Named(NamedKey::ArrowDown) => {
                    self.model.outputs_focus = (self.model.outputs_focus + 1).min(last);
                    return;
                }
                Key::Named(NamedKey::ArrowUp) => {
                    self.model.outputs_focus = self.model.outputs_focus.saturating_sub(1);
                    return;
                }
                Key::Named(NamedKey::Enter) | Key::Named(NamedKey::Space) => {
                    if let Some(out) = self.model.outputs.get(self.model.outputs_focus) {
                        let _ = self.tx.send(Cmd::SetOutput {
                            id: out.id,
                            on: !out.enabled,
                        });
                    }
                    return;
                }
                Key::Character(c) if c == "o" || c == "O" => {
                    self.model.outputs_open = false;
                    return;
                }
                Key::Character(c) if c == "j" => {
                    self.model.outputs_focus = (self.model.outputs_focus + 1).min(last);
                    return;
                }
                Key::Character(c) if c == "k" => {
                    self.model.outputs_focus = self.model.outputs_focus.saturating_sub(1);
                    return;
                }
                _ => return,
            }
        }

        // Numeric prefix (`5j`). Digits 0-3 are pane shortcuts (rmpc uses them for tabs), so
        // counts start at 4; that keeps both habits without a timeout.
        if let Key::Character(ch) = key {
            if !ch.is_empty() && ch.chars().all(|c| c.is_ascii_digit()) {
                if let Some(d) = ch.chars().next().and_then(|c| c.to_digit(10)) {
                    let cur = self.model.count.unwrap_or(0);
                    if d >= 4 || cur > 0 {
                        self.model.count = Some((cur * 10 + d).min(999));
                        return;
                    }
                }
            }
        }
        let repeat = self.model.count.take().unwrap_or(1).max(1) as i32;
        let page = self.visible_rows() as i32;

        match key {
            Key::Named(NamedKey::ArrowDown) => self.move_selection(repeat),
            Key::Named(NamedKey::ArrowUp) => self.move_selection(-repeat),
            Key::Named(NamedKey::PageDown) => self.move_selection(page * repeat),
            Key::Named(NamedKey::PageUp) => self.move_selection(-page * repeat),
            Key::Named(NamedKey::Home) => self.jump_selection(false),
            Key::Named(NamedKey::End) => self.jump_selection(true),
            Key::Named(NamedKey::Tab) => {
                const ORDER: [Pane; 6] = [
                    Pane::Queue,
                    Pane::Library,
                    Pane::Artists,
                    Pane::Albums,
                    Pane::Playlists,
                    Pane::Search,
                ];
                let idx = ORDER
                    .iter()
                    .position(|p| *p == self.model.view)
                    .unwrap_or(0);
                let next = if shift {
                    (idx + ORDER.len() - 1) % ORDER.len()
                } else {
                    (idx + 1) % ORDER.len()
                };
                self.model.view = ORDER[next];
            }
            Key::Named(NamedKey::Enter) => self.activate(),
            Key::Named(NamedKey::Space) => match self.model.view {
                Pane::Queue => {
                    if let Some(pos) = self.model.status.song {
                        self.model.queue_sel = pos;
                        self.model.queue_scroll_target = pos as f32;
                    }
                }
                Pane::Library => self.enqueue_selected(),
                Pane::Search => self.activate(),
                _ => {
                    if let (Some(kind), Some(name)) = (
                        self.collection_kind(),
                        self.active_picker().and_then(|p| p.selected().cloned()),
                    ) {
                        let _ = self.tx.send(Cmd::EnqueueCollection {
                            kind,
                            name: name.clone(),
                        });
                        self.model.toast = Some((format!("в очередь: {name}"), Instant::now()));
                    }
                }
            },
            Key::Named(NamedKey::ArrowRight) => {
                let _ = self.tx.send(Cmd::SeekRelative(5.0 * repeat as f64));
            }
            Key::Named(NamedKey::ArrowLeft) => {
                let _ = self.tx.send(Cmd::SeekRelative(-5.0 * repeat as f64));
            }
            Key::Named(NamedKey::F1) => self.model.mode = InputMode::Help,
            Key::Named(NamedKey::Escape) => {
                if self.model.view != Pane::Queue {
                    self.model.view = Pane::Queue;
                }
            }
            Key::Character(raw) => {
                let latin = latinize(raw);
                let ch = latin.unwrap_or(raw.as_str());
                let shift = shift
                    || matches!(
                        raw.as_str(),
                        "G" | "П"
                            | "Д"
                            | "Щ"
                            | "З"
                            | "Г"
                            | "К"
                            | "В"
                            | "Ф"
                            | "С"
                            | "Т"
                            | "О"
                            | "Л"
                    );
                match (ch, ctrl, shift) {
                    // navigation (rmpc "navigation" section)
                    ("j", false, _) => self.move_selection(repeat),
                    ("k", false, _) => self.move_selection(-repeat),
                    ("g", false, false) => self.jump_selection(false),
                    ("G", _, _) => self.jump_selection(true),
                    ("h", false, _) | ("l", false, _) => {} // Left/Right: no side-by-side panes here
                    ("d", true, _) => self.move_selection(page / 2 * repeat),
                    ("u", true, _) => self.move_selection(-(page / 2) * repeat),
                    ("n", true, _) => self.move_selection(repeat),
                    ("p", true, _) => self.move_selection(-repeat),
                    ("a", true, _) => self.jump_selection(false),
                    ("e", true, _) => self.jump_selection(true),
                    ("n", false, _) => self.move_selection(repeat), // next search result
                    ("N", _, _) => self.move_selection(-repeat),

                    // global (rmpc "global" section)
                    ("1", _, _) => self.switch_pane(Pane::Queue),
                    ("0", _, _) => self.switch_pane(Pane::Library),
                    ("2", _, _) => self.switch_pane(Pane::Artists),
                    ("3", _, _) => self.switch_pane(Pane::Albums),
                    ("P", _, _) => self.switch_pane(Pane::Playlists),
                    ("o", false, _) | ("O", _, _) => {
                        self.model.outputs_open = true;
                        let _ = self.tx.send(Cmd::RefreshOutputs);
                    }
                    ("p", false, _) => {
                        let _ = self.tx.send(Cmd::Toggle);
                    }
                    ("s", false, _) => {
                        let _ = self.tx.send(Cmd::Stop);
                    }
                    ("s", true, _) => {
                        // rmpc <C-s> = Save: open the command line pre-filled.
                        self.model.mode = InputMode::Command;
                        self.model.cmdline = "save ".into();
                    }
                    (">", _, _) => {
                        let _ = self.tx.send(Cmd::Next);
                    }
                    ("<", _, _) => {
                        let _ = self.tx.send(Cmd::Prev);
                    }
                    ("f", false, _) => {
                        let _ = self.tx.send(Cmd::SeekRelative(5.0 * repeat as f64));
                    }
                    ("b", false, _) => {
                        let _ = self.tx.send(Cmd::SeekRelative(-5.0 * repeat as f64));
                    }
                    ("=", _, _) => {
                        let _ = self.tx.send(Cmd::VolumeRelative(5 * repeat));
                    }
                    ("-", _, _) => {
                        let _ = self.tx.send(Cmd::VolumeRelative(-5 * repeat));
                    }
                    ("z", false, _) => {
                        let on = !self.model.status.repeat;
                        let _ = self.tx.send(Cmd::Repeat(on));
                    }
                    ("r", false, _) => {
                        let on = !self.model.status.random;
                        let _ = self.tx.send(Cmd::Random(on));
                    }
                    ("y", false, _) => {
                        let on = !self.model.status.single;
                        let _ = self.tx.send(Cmd::Single(on));
                    }
                    ("R", _, _) => {
                        let on = !self.model.status.consume;
                        let _ = self.tx.send(Cmd::Consume(on));
                    }
                    ("u", false, _) | ("U", _, _) => {
                        // (U also re-reads the library; the DB rescan itself is MPD's job.)
                        let path = self.model.lib_path.clone();
                        let _ = self.tx.send(Cmd::LoadDir(path));
                        self.model.toast = Some(("библиотека перечитана".into(), Instant::now()));
                    }
                    ("w", false, _) => self.model.mode = InputMode::Help,
                    ("?", _, _) => {
                        self.model.view = Pane::Search;
                        self.model.mode = InputMode::Search;
                        self.model.search_input.clear();
                    }
                    ("/", _, _) => {
                        self.model.view = Pane::Search;
                        self.model.mode = InputMode::Search;
                        self.model.search_input.clear();
                    }
                    (":", _, _) => {
                        self.model.mode = InputMode::Command;
                        self.model.cmdline.clear();
                    }
                    ("a", false, _) => self.start_playlist_pick(),
                    ("t", false, _) => {
                        self.model.toast = None;
                        self.theme_name = if self.theme_name == "warm" {
                            "dark".into()
                        } else {
                            "warm".into()
                        }
                    }
                    ("q", false, _) => std::process::exit(0),
                    ("q", true, _) => std::process::exit(0),

                    // queue edits: destructive, so they need a second press (see Destructive)
                    ("J", _, _) => self.move_queue_row(1),
                    ("K", _, _) => self.move_queue_row(-1),
                    ("d", false, _) => self.confirm_destructive(Destructive::DeleteSelected),
                    ("C", _, _) => self.confirm_destructive(Destructive::ClearQueue),

                    _ => {}
                }
            }
            _ => {}
        }
    }

    /// `a` (rmpc AddToPlaylist): remember the selected song and switch to the playlists pane.
    fn start_playlist_pick(&mut self) {
        let uri = match self.model.view {
            Pane::Queue => self
                .model
                .queue
                .get(self.model.queue_sel)
                .map(|s| s.file.clone()),
            Pane::Library => self
                .filtered_library()
                .get(self.model.lib_sel)
                .map(|e| match e {
                    Entry::Song { path, .. } => path.clone(),
                    Entry::Dir { path, .. } => path.clone(),
                }),
            Pane::Search => self
                .model
                .search_results
                .get(self.model.lib_sel)
                .map(|s| s.file.clone()),
            _ => None,
        };
        match uri {
            Some(uri) => {
                self.model.pick_target = Some(uri);
                self.switch_pane(Pane::Playlists);
                self.model.toast = Some(("выбери плейлист и нажми enter".into(), Instant::now()));
            }
            None => self.model.toast = Some(("нечего добавлять".into(), Instant::now())),
        }
    }

    /// `J`/`K`: reorder the queue (rmpc MoveDown/MoveUp). The cursor follows the row and the
    /// worker refetches the queue, because a move leaves playlistlength unchanged.
    fn move_queue_row(&mut self, delta: i32) {
        if self.model.view != Pane::Queue {
            return;
        }
        let len = self.model.queue.len();
        if len < 2 {
            return;
        }
        let from = self.model.queue_sel;
        let to = (from as i32 + delta).clamp(0, len as i32 - 1) as usize;
        if from == to {
            return;
        }
        let _ = self.tx.send(Cmd::MoveTrack { from, to });
        self.model.queue_sel = to;
        self.model.queue_scroll_target = to as f32;
        self.model.queue.swap(from, to);
    }

    /// Switch panes and lazily fetch the list the pane needs.
    fn switch_pane(&mut self, pane: Pane) {
        self.model.view = pane;
        match pane {
            Pane::Artists if self.model.artists.len() == 0 => {
                let _ = self.tx.send(Cmd::LoadArtists);
            }
            Pane::Albums if self.model.albums.len() == 0 => {
                let _ = self.tx.send(Cmd::LoadAlbums);
            }
            Pane::Playlists if self.model.playlists.len() == 0 => {
                let _ = self.tx.send(Cmd::LoadPlaylists);
            }
            _ => {}
        }
    }

    /// Mouse: the last drawn frame's rectangles decide what was hit. Rows need a double click
    /// to act (play / enter), a single click only moves the cursor there.
    fn handle_click(&mut self) {
        let (cx, cy) = self.cursor;
        let Some(area) = self.hits.iter().rev().find(|h| h.contains(cx, cy)).copied() else {
            return;
        };
        let now = Instant::now();
        let double = matches!(&self.last_click, Some((at, _, _)) if at.elapsed() < Duration::from_millis(400));
        match area.action {
            Hit::Tab(pane) => self.switch_pane(pane),
            Hit::Row(pane, index) => {
                let same = matches!(&self.last_click, Some((_, p, i)) if *p == pane && *i == index);
                self.last_click = Some((now, pane, index));
                self.select_row(pane, index);
                if same || double {
                    self.activate_row(pane, index);
                }
            }
            Hit::Transport(dir) => {
                let cmd = match dir {
                    -1 => Cmd::Prev,
                    1 => Cmd::Next,
                    _ => Cmd::Toggle,
                };
                let _ = self.tx.send(cmd);
            }
            Hit::Chip(which) => match which {
                0 => {
                    let on = !self.model.status.repeat;
                    let _ = self.tx.send(Cmd::Repeat(on));
                }
                1 => {
                    let on = !self.model.status.random;
                    let _ = self.tx.send(Cmd::Random(on));
                }
                2 => {
                    let on = !self.model.status.single;
                    let _ = self.tx.send(Cmd::Single(on));
                }
                _ => {
                    let on = !self.model.status.consume;
                    let _ = self.tx.send(Cmd::Consume(on));
                }
            },
            Hit::Seek(bar_w) => {
                let total = self.model.duration();
                if total > 0.0 && bar_w > 0.0 {
                    let frac = ((cx - area.x) / area.w).clamp(0.0, 1.0) as f64;
                    let _ = self.tx.send(Cmd::Seek(total * frac));
                }
            }
            Hit::Volume(bar_w) => {
                if bar_w > 0.0 {
                    let frac = ((cx - area.x) / area.w).clamp(0.0, 1.0);
                    let _ = self.tx.send(Cmd::Volume((frac * 100.0).round() as i32));
                }
            }
            Hit::Output(i) => {
                if let Some(out) = self.model.outputs.get(i) {
                    let _ = self.tx.send(Cmd::SetOutput {
                        id: out.id,
                        on: !out.enabled,
                    });
                }
            }
            Hit::CloseOverlay => self.model.outputs_open = false,
        }
    }

    /// Keep the swapchain and the shader's resolution in step with the surface. Bursts of
    /// near-identical configures are coalesced, and a size that is already close enough is
    /// accepted as is — otherwise a tiling compositor and the app can chase each other.
    fn sync_surface(&mut self, width: u32, height: u32) {
        let Some(gpu) = self.gpu.as_mut() else { return };
        let (cur_w, cur_h) = (gpu.extent.width, gpu.extent.height);
        let close = width.abs_diff(cur_w) <= 2 && height.abs_diff(cur_h) <= 2;
        if close {
            return;
        }
        if self.last_resize.elapsed() < Duration::from_millis(200) {
            // Debounced, but make sure the next event still gets through.
            return;
        }
        self.last_resize = Instant::now();
        match unsafe { gpu.recreate_swapchain(width, height) } {
            Ok(()) => eprintln!(
                "[event] swapchain {}x{} (scale {})",
                gpu.extent.width, gpu.extent.height, self.scale
            ),
            Err(e) => eprintln!("[event] swapchain recreate failed: {e}"),
        }
    }

    fn select_row(&mut self, pane: Pane, index: usize) {
        match pane {
            Pane::Queue => {
                self.model.queue_sel = index;
                self.model.queue_scroll_target = index as f32;
            }
            Pane::Library => {
                self.model.lib_sel = index;
                self.model.lib_scroll_target = index as f32;
            }
            Pane::Search => self.model.lib_sel = index,
            Pane::Artists => self.model.artists.sel = index,
            Pane::Albums => self.model.albums.sel = index,
            Pane::Playlists => self.model.playlists.sel = index,
        }
        self.model.user_moved = true;
    }

    fn activate_row(&mut self, pane: Pane, index: usize) {
        match pane {
            Pane::Queue => {
                let _ = self.tx.send(Cmd::PlayIndex(index));
            }
            Pane::Search => {
                if let Some(song) = self.model.search_results.get(index) {
                    let _ = self.tx.send(Cmd::PlayUri(song.file.clone()));
                }
            }
            Pane::Library => {
                self.model.lib_sel = index;
                self.activate();
            }
            Pane::Artists | Pane::Albums | Pane::Playlists => {
                self.model.view = pane;
                self.select_row(pane, index);
                self.activate();
            }
        }
    }

    /// Enqueue the selected library entry (rmpc `<Space>` = Add).
    fn enqueue_selected(&mut self) {
        if let Some(entry) = self.filtered_library().get(self.model.lib_sel).copied() {
            let uri = match entry {
                Entry::Dir { path, .. } => path.clone(),
                Entry::Song { path, .. } => path.clone(),
            };
            let _ = self.tx.send(Cmd::EnqueueDir(uri));
            self.model.toast = Some(("добавлено в очередь".into(), Instant::now()));
        }
    }

    /// Queue edits take two presses: rmpc binds them to a single key, but an irreversible
    /// delete deserves a confirmation, so the first press only warns for three seconds.
    fn confirm_destructive(&mut self, action: Destructive) {
        let now = Instant::now();
        let armed = matches!(
            &self.model.confirm,
            Some((_, kind, at)) if *kind == action && at.elapsed() < Duration::from_secs(3)
        );
        if std::env::var("PLAYER_DEBUG_KEYS").is_ok() {
            eprintln!(
                "[confirm] armed={armed} prev={:?}",
                self.model
                    .confirm
                    .as_ref()
                    .map(|(_, k, at)| (k, at.elapsed()))
            );
        }
        if armed {
            self.model.confirm = None;
            match action {
                Destructive::DeleteSelected => {
                    let _ = self.tx.send(Cmd::DeleteIndex(self.model.queue_sel));
                }
                Destructive::ClearQueue => {
                    let _ = self.tx.send(Cmd::ClearQueue);
                }
            }
            return;
        }
        let label = match action {
            Destructive::DeleteSelected => "удалить выбранный трек? нажми d ещё раз",
            Destructive::ClearQueue => "очистить очередь? нажми C ещё раз",
        };
        self.model.toast = Some((label.to_string(), now));
        self.model.confirm = Some((label.to_string(), action, now));
    }

    /// `:` commands. Deliberately small; each maps onto the same `Cmd` channel the keys use, so
    /// dry-run mode covers them too.
    fn run_command(&mut self, line: &str) {
        let mut parts = line.trim().split_whitespace();
        let Some(cmd) = parts.next() else { return };
        let arg = parts.next();
        let n: Option<i64> = arg.and_then(|a| a.parse().ok());
        let flag = arg;
        match (cmd, n) {
            ("q" | "quit", _) => std::process::exit(0),
            ("play", Some(idx)) => {
                let _ = self.tx.send(Cmd::PlayIndex((idx.max(1) - 1) as usize));
            }
            ("pause", _) => {
                let _ = self.tx.send(Cmd::Pause(true));
            }
            ("resume", _) => {
                let _ = self.tx.send(Cmd::Pause(false));
            }
            ("next", _) => {
                let _ = self.tx.send(Cmd::Next);
            }
            ("prev", _) => {
                let _ = self.tx.send(Cmd::Prev);
            }
            ("stop", _) => {
                let _ = self.tx.send(Cmd::Stop);
            }
            ("seek", Some(secs)) => {
                let _ = self.tx.send(Cmd::Seek(secs as f64));
            }
            ("vol" | "volume", Some(v)) => {
                let _ = self.tx.send(Cmd::Volume(v as i32));
            }
            ("repeat" | "random" | "single" | "consume", _) => {
                let on = matches!(flag, Some("1") | Some("on") | Some("true"));
                let _ = match cmd {
                    "repeat" => self.tx.send(Cmd::Repeat(on)),
                    "random" => self.tx.send(Cmd::Random(on)),
                    "single" => self.tx.send(Cmd::Single(on)),
                    _ => self.tx.send(Cmd::Consume(on)),
                };
            }
            ("save", _) => {
                if let Some(name) = flag {
                    let _ = self.tx.send(Cmd::SavePlaylist(name.to_string()));
                    self.model.toast = Some((format!("очередь сохранена: {name}"), Instant::now()));
                } else {
                    self.model.toast = Some(("usage: :save <имя>".into(), Instant::now()));
                }
            }
            ("rmplaylist", _) => {
                if let Some(name) = flag {
                    let _ = self.tx.send(Cmd::DeletePlaylist(name.to_string()));
                    self.model.toast = Some((format!("удалён плейлист: {name}"), Instant::now()));
                }
            }
            ("renameplaylist", _) => {
                let mut rest = line.split_whitespace().skip(1);
                match (rest.next(), rest.next()) {
                    (Some(from), Some(to)) => {
                        let _ = self.tx.send(Cmd::RenamePlaylist {
                            from: from.to_string(),
                            to: to.to_string(),
                        });
                        self.model.toast = Some((format!("{from} → {to}"), Instant::now()));
                    }
                    _ => {
                        self.model.toast = Some((
                            "usage: :renameplaylist <старое> <новое>".into(),
                            Instant::now(),
                        ))
                    }
                }
            }
            ("theme", _) => {
                let name = flag.unwrap_or("dark");
                self.theme_name = if theme::Theme::by_name(name).name == name {
                    name.to_string()
                } else {
                    "dark".into()
                };
            }
            ("search", _) => {
                if let Some(q) = flag {
                    let _ = self.tx.send(Cmd::Search(q.to_string()));
                }
            }
            (other, _) => {
                self.model.toast = Some((format!("неизвестная команда: {other}"), Instant::now()));
            }
        }
    }

    /// Apply a scripted key token through the same logic the real keyboard uses.
    /// Apply a scripted key token through the *same* handler the real keyboard uses, so a
    /// scripted run is a real test of the state machine rather than a parallel code path.
    fn apply_token(&mut self, token: &str) {
        use winit::keyboard::SmolStr;
        if token == "noop" {
            // burns one scripted interval so async MPD replies can land before the next dump
            return;
        }
        let (ctrl, body) = match token.strip_prefix("ctrl+") {
            Some(rest) => (true, rest),
            None => (false, token),
        };
        let named = match body {
            "tab" => Some(NamedKey::Tab),
            "enter" => Some(NamedKey::Enter),
            "space" => Some(NamedKey::Space),
            "up" => Some(NamedKey::ArrowUp),
            "down" => Some(NamedKey::ArrowDown),
            "left" => Some(NamedKey::ArrowLeft),
            "right" => Some(NamedKey::ArrowRight),
            "pgup" => Some(NamedKey::PageUp),
            "pgdown" => Some(NamedKey::PageDown),
            "home" => Some(NamedKey::Home),
            "end" => Some(NamedKey::End),
            "esc" => Some(NamedKey::Escape),
            "backspace" => Some(NamedKey::Backspace),
            "f1" => Some(NamedKey::F1),
            _ => None,
        };
        // Aliases for characters that are awkward to pass through a comma-separated argv.
        let body = match body {
            "slash" => "/",
            "colon" => ":",
            "question" => "?",
            "plus" => "+",
            "minus" => "-",
            "equals" => "=",
            "dot" => ".",
            "comma" => ",",
            other => other,
        };
        let key = match named {
            Some(n) => Key::Named(n),
            None => Key::Character(SmolStr::new(body)),
        };
        self.handle_key_spec(&key, false, ctrl);
    }

    /// One-line state dump for the scripted test harness (`--dump-state`).
    fn dump_state(&self, token: &str) {
        let view = match self.model.view {
            Pane::Queue => "queue",
            Pane::Library => "library",
            Pane::Artists => "artists",
            Pane::Albums => "albums",
            Pane::Playlists => "playlists",
            Pane::Search => "search",
        };
        let mode = match self.model.mode {
            InputMode::Normal => "normal",
            InputMode::Search => "search",
            InputMode::Command => "command",
            InputMode::Help => "help",
        };
        let sel = match self.model.view {
            Pane::Queue => self.model.queue_sel,
            _ => self.model.lib_sel,
        };
        eprintln!(
            "[state] token={token} mode={mode} view={view} sel={sel} song={} qlen={} lib={} cmd='{}' search='{}' theme={} outputs={} pn={}",
            self.model.status.song.map(|v| v as i64).unwrap_or(-1),
            self.model.queue.len(),
            self.model.lib_entries.len(),
            self.model.cmdline,
            self.model.search_input,
            self.theme_name,
            self.model.outputs_open,
            match self.model.view {
                Pane::Artists => self.model.artists.len(),
                Pane::Albums => self.model.albums.len(),
                Pane::Playlists => self.model.playlists.len(),
                _ => 0,
            }
        );
    }

    fn move_selection(&mut self, delta: i32) {
        let visible = self.visible_rows();
        if self.active_picker().is_some() {
            if let Some(p) = self.active_picker_mut() {
                p.move_by(delta, visible);
            }
            return;
        }
        let len = self.current_list_len();
        if len == 0 {
            return;
        }
        let cur = match self.model.view {
            Pane::Queue => &mut self.model.queue_sel,
            _ => &mut self.model.lib_sel,
        };
        self.model.user_moved = true;
        let next = (*cur as i32 + delta).clamp(0, len as i32 - 1);
        *cur = next as usize;
        self.clamp_selection();
    }

    fn jump_selection(&mut self, to_end: bool) {
        let visible = self.visible_rows();
        if self.active_picker().is_some() {
            if let Some(p) = self.active_picker_mut() {
                p.jump(to_end, visible);
            }
            return;
        }
        let len = self.current_list_len();
        if len == 0 {
            return;
        }
        let value = if to_end { len - 1 } else { 0 };
        match self.model.view {
            Pane::Queue => self.model.queue_sel = value,
            _ => self.model.lib_sel = value,
        }
        self.clamp_selection();
    }

    fn activate(&mut self) {
        if let (Some(uri), Some(name)) = (
            self.model.pick_target.clone(),
            self.model.playlists.selected().cloned(),
        ) {
            let _ = self.tx.send(Cmd::AddToPlaylist {
                name: name.clone(),
                uri,
            });
            self.model.toast = Some((format!("добавлено в {name}"), Instant::now()));
            self.model.pick_target = None;
            self.model.view = Pane::Queue;
            return;
        }
        if let (Some(kind), Some(name)) = (
            self.collection_kind(),
            self.active_picker().and_then(|p| p.selected().cloned()),
        ) {
            let _ = self.tx.send(Cmd::PlayCollection {
                kind,
                name: name.clone(),
            });
            self.model.toast = Some((format!("играю: {name}"), Instant::now()));
            return;
        }
        match self.model.view {
            Pane::Queue | Pane::Search => {
                let (index, uri) = match self.model.view {
                    Pane::Queue => (Some(self.model.queue_sel), None),
                    Pane::Search => (
                        None,
                        self.model
                            .search_results
                            .get(self.model.lib_sel)
                            .map(|s| s.file.clone()),
                    ),
                    _ => (None, None),
                };
                if let Some(i) = index {
                    let _ = self.tx.send(Cmd::PlayIndex(i));
                } else if let Some(u) = uri {
                    let _ = self.tx.send(Cmd::PlayUri(u));
                }
            }
            Pane::Artists | Pane::Albums | Pane::Playlists => {}
            Pane::Library => {
                if let Some(entry) = self.filtered_library().get(self.model.lib_sel).copied() {
                    match entry {
                        Entry::Dir { path, .. } => {
                            let _ = self.tx.send(Cmd::LoadDir(format!("{path}/")));
                        }
                        Entry::Song { path, .. } => {
                            let _ = self.tx.send(Cmd::PlayUri(path.clone()));
                        }
                    }
                }
            }
        }
    }

    fn animate(&mut self) {
        let lerp = |cur: f32, target: f32| cur + (target - cur) * 0.35;
        self.model.queue_scroll = lerp(self.model.queue_scroll, self.model.queue_scroll_target);
        self.model.lib_scroll = lerp(self.model.lib_scroll, self.model.lib_scroll_target);
    }
}

// ---------------------------------------------------------------- drawing

fn fmt_time(secs: f64) -> String {
    let s = secs.max(0.0) as u64;
    format!("{}:{:02}", s / 60, s % 60)
}

/// One frame of UI. Every colour, size and radius comes from the theme, so a variant is data.
fn draw_ui(
    fonts: &mut Fonts,
    m: &Model,
    extent: vk::Extent2D,
    t: f32,
    th: &theme::Theme,
    hits: &mut Vec<HitArea>,
) -> DrawList {
    use player_proto::theme::{Face, GEOM, TYPE};

    let mut list = DrawList::new();
    let (w, h) = (extent.width as f32, extent.height as f32);
    let row_h = GEOM.row_h;
    let pad = GEOM.pad;

    // ---------------- background
    list.gradient(0.0, 0.0, w, h, th.bg_top, th.bg_bottom);

    // ---------------- top bar
    let top = 56.0;
    list.gradient(
        0.0,
        0.0,
        w,
        top,
        theme::with_alpha(th.panel_hi, 0.9),
        theme::with_alpha(th.panel_hi, 0.55),
    );
    list.rect(0.0, top - GEOM.line, w, GEOM.line, th.border);

    let logo = 28.0;
    list.rounded(
        pad,
        (top - logo) * 0.5,
        logo,
        logo,
        GEOM.radius_sm,
        th.accent,
        th.accent2,
    );
    let logo_w = fonts.measure("P", 15.0, Face::UiSemiBold);
    fonts.layout_line(
        &mut list,
        "P",
        pad + (logo - logo_w) * 0.5,
        (top - logo) * 0.5 + 5.0,
        15.0,
        Face::UiSemiBold,
        th.text_on_accent,
    );
    let title_x = pad + logo + 10.0;
    fonts.layout_line(
        &mut list,
        "Player",
        title_x,
        16.0,
        TYPE.title,
        Face::UiSemiBold,
        th.text,
    );

    // tabs
    let tabs = [
        ("Queue", Pane::Queue),
        ("Library", Pane::Library),
        ("Artists", Pane::Artists),
        ("Albums", Pane::Albums),
        ("Playlists", Pane::Playlists),
        ("Search", Pane::Search),
    ];
    let mut tx = title_x + fonts.measure("Player", TYPE.title, Face::UiSemiBold) + 26.0;
    for (label, pane) in tabs {
        let active = m.view == pane;
        let tw = fonts.measure(label, TYPE.heading, Face::UiMedium) + 26.0;
        let reserve = 220.0; // connection state + track counter on the right
        if !active && tx + tw > w - reserve {
            continue;
        }
        if active {
            list.rounded(
                tx,
                15.0,
                tw,
                26.0,
                GEOM.radius_pill,
                th.accent_soft,
                theme::with_alpha(th.accent2, 0.10),
            );
            list.rounded(tx, 15.0, tw, 26.0, GEOM.radius_pill, [0.0; 4], [0.0; 4]);
        }
        let fg = if active { th.accent } else { th.text_dim };
        fonts.layout_line(
            &mut list,
            label,
            tx + 13.0,
            19.0,
            TYPE.heading,
            Face::UiMedium,
            fg,
        );
        if active {
            list.rounded(
                tx + 6.0,
                15.0 + 26.0 - 2.0,
                tw - 12.0,
                2.0,
                1.0,
                th.accent,
                th.accent2,
            );
        }
        hit(hits, tx, 12.0, tw, 32.0, Hit::Tab(pane));
        tx += tw + 6.0;
    }

    // right side: queue size + connection
    let queue_label = format!("{}", m.status.queue_len);
    let qw_ = fonts.measure(&queue_label, TYPE.label, Face::Mono);
    fonts.layout_line(
        &mut list,
        &queue_label,
        w - pad - qw_,
        20.0,
        TYPE.label,
        Face::Mono,
        th.text_faint,
    );
    let fmt_label = "tracks";
    let fw = fonts.measure(fmt_label, TYPE.caption, Face::UiRegular);
    fonts.layout_line(
        &mut list,
        fmt_label,
        w - pad - qw_ - 6.0 - fw,
        20.0,
        TYPE.caption,
        Face::UiRegular,
        th.text_faint,
    );
    let (dot, state_label) = if m.connected {
        (th.success, "mpd")
    } else {
        (th.danger, "offline")
    };
    let pulse = 0.65 + 0.35 * (t * 2.2).sin().abs();
    let state_x = w - pad - qw_ - 6.0 - fw - 40.0;
    list.rounded(
        state_x,
        22.0,
        7.0,
        7.0,
        3.5,
        theme::with_alpha(dot, pulse),
        theme::with_alpha(dot, pulse),
    );
    fonts.layout_line(
        &mut list,
        state_label,
        state_x + 12.0,
        19.0,
        TYPE.caption,
        Face::UiRegular,
        th.text_dim,
    );

    // ---------------- panels
    let show_left = w >= 1080.0;
    let show_right = w >= 820.0;
    let left_w = if show_left { 292.0 } else { 0.0 };
    let right_w = if show_right { 344.0 } else { 0.0 };
    let body_top = top + 12.0;
    let body_bottom = h - 40.0;
    let body_h = body_bottom - body_top;

    // ---------------- library
    if show_left {
        list.shadow(16.0, body_top, left_w, body_h, GEOM.radius_lg, 26.0, 0.35);
        list.rounded(
            20.0,
            body_top,
            left_w,
            body_h,
            GEOM.radius_lg,
            th.panel,
            th.panel,
        );
        list.rect(20.0, body_top, left_w, GEOM.line, th.border_hi);

        let active = m.view == Pane::Library;
        fonts.layout_line(
            &mut list,
            "LIBRARY",
            36.0,
            body_top + 14.0,
            TYPE.micro,
            Face::UiMedium,
            if active { th.accent } else { th.text_faint },
        );
        if active {
            list.rounded(28.0, body_top + 16.0, 2.0, 10.0, 1.0, th.accent, th.accent2);
        }
        let has_filter = !m.lib_filter.is_empty();
        let path_label = if has_filter {
            format!(
                "/{}  ·  filter: {}",
                m.lib_path.trim_end_matches('/'),
                m.lib_filter
            )
        } else {
            fonts.fit(&m.lib_path, TYPE.caption, left_w - 40.0, Face::Mono)
        };
        fonts.layout_fitted(
            &mut list,
            &path_label,
            28.0,
            body_top + 32.0,
            TYPE.caption,
            Face::Mono,
            if has_filter { th.accent } else { th.text_faint },
            left_w - 40.0,
        );

        let needle = m.lib_filter.to_lowercase();
        let lib_filtered: Vec<&Entry> = m
            .lib_entries
            .iter()
            .filter(|e| {
                if needle.is_empty() {
                    return true;
                }
                let name = match e {
                    Entry::Dir { name, .. } => name,
                    Entry::Song { song, .. } => &song.title,
                };
                name.to_lowercase().contains(&needle)
            })
            .collect();
        let rows_y = body_top + 58.0;
        list.set_clip(Some([20.0, rows_y - 4.0, left_w, body_h - 62.0]));
        for (i, entry) in lib_filtered.iter().enumerate() {
            let y = rows_y + i as f32 * row_h - m.lib_scroll * row_h;
            if y < rows_y - row_h || y > body_bottom {
                continue;
            }
            let selected = active && i == m.lib_sel;
            if selected {
                list.rounded(
                    28.0,
                    y,
                    left_w - 16.0,
                    row_h - 6.0,
                    GEOM.radius_md,
                    th.selection,
                    theme::with_alpha(th.accent2, 0.12),
                );
                list.rounded(28.0, y + 5.0, 2.0, row_h - 16.0, 1.0, th.accent, th.accent2);
            }
            let (icon, label, is_dir) = match *entry {
                Entry::Dir { name, .. } => ("▸", name.clone(), true),
                Entry::Song { song, .. } => ("♪", song.title.clone(), false),
            };
            fonts.layout_line(
                &mut list,
                icon,
                34.0,
                y + 8.0,
                TYPE.label,
                Face::Symbols,
                if is_dir { th.accent } else { th.text_faint },
            );
            let color = if selected {
                th.text
            } else if is_dir {
                theme::with_alpha(th.text, 0.9)
            } else {
                th.text_dim
            };
            fonts.layout_fitted(
                &mut list,
                &label,
                48.0,
                y + 7.0,
                TYPE.body,
                Face::UiRegular,
                color,
                left_w - 38.0,
            );
        }
        if lib_filtered.is_empty() {
            let msg = if m.lib_filter.is_empty() {
                "пусто"
            } else {
                "нет совпадений"
            };
            fonts.layout_line(
                &mut list,
                msg,
                36.0,
                rows_y + 6.0,
                TYPE.label,
                Face::UiRegular,
                th.text_faint,
            );
        }
        list.set_clip(None);
    }

    // ---------------- queue / search
    let qx = if show_left {
        20.0 + left_w + 12.0
    } else {
        20.0
    };
    let qw = (w - qx - right_w - if show_right { 24.0 } else { 20.0 }).max(160.0);
    list.shadow(qx, body_top, qw, body_h, GEOM.radius_lg, 26.0, 0.35);
    list.rounded(qx, body_top, qw, body_h, GEOM.radius_lg, th.panel, th.panel);
    list.rect(qx, body_top, qw, GEOM.line, th.border_hi);

    let search_mode = m.view == Pane::Search;
    let picker_active = matches!(m.view, Pane::Artists | Pane::Albums | Pane::Playlists);
    let active_centre = matches!(
        m.view,
        Pane::Queue | Pane::Artists | Pane::Albums | Pane::Playlists | Pane::Search
    );
    let picking = m.pick_target.is_some() && m.view == Pane::Playlists;
    let centre_title = if picking {
        "ДОБАВИТЬ В ПЛЕЙЛИСТ"
    } else {
        match m.view {
            Pane::Search => "SEARCH",
            Pane::Artists => "ARTISTS",
            Pane::Albums => "ALBUMS",
            Pane::Playlists => "PLAYLISTS",
            _ => "QUEUE",
        }
    };
    fonts.layout_line(
        &mut list,
        centre_title,
        qx + 18.0,
        body_top + 14.0,
        TYPE.micro,
        Face::UiMedium,
        if active_centre {
            th.accent
        } else {
            th.text_faint
        },
    );
    let counter = match m.view {
        Pane::Search => format!("{} results", m.search_results.len()),
        Pane::Artists => format!("{}", m.artists.len()),
        Pane::Albums => format!("{}", m.albums.len()),
        Pane::Playlists => format!("{}", m.playlists.len()),
        _ => format!(
            "{}/{}",
            m.status.song.map(|s| s + 1).unwrap_or(0),
            m.queue.len()
        ),
    };
    let cw = fonts.measure(&counter, TYPE.caption, Face::Mono);
    fonts.layout_line(
        &mut list,
        &counter,
        qx + qw - 18.0 - cw,
        body_top + 14.0,
        TYPE.caption,
        Face::Mono,
        th.text_faint,
    );

    if search_mode {
        let caret = if m.search_active { "▏" } else { "" };
        let shown = format!("/{}{}", m.search_input, caret);
        fonts.layout_fitted(
            &mut list,
            &shown,
            qx + 18.0,
            body_top + 30.0,
            TYPE.body,
            Face::Mono,
            if m.search_active {
                th.accent
            } else {
                th.text_dim
            },
            qw - 36.0,
        );
        if m.search_results.is_empty() && !m.search_active {
            fonts.layout_line(
                &mut list,
                "enter — искать по библиотеке",
                qx + 18.0,
                body_top + 52.0,
                TYPE.label,
                Face::UiRegular,
                th.text_faint,
            );
        }
    }

    let q_rows_y = if search_mode {
        body_top + 60.0
    } else {
        body_top + 38.0
    };

    if picker_active {
        let (picker, offset) = match m.view {
            Pane::Artists => (&m.artists, m.artists.scroll),
            Pane::Albums => (&m.albums, m.albums.scroll),
            _ => (&m.playlists, m.playlists.scroll),
        };
        let compact = GEOM.row_h_compact;
        list.set_clip(Some([qx, q_rows_y - 6.0, qw, body_h - 44.0]));
        for (i, name) in picker.items.iter().enumerate() {
            let y = q_rows_y + i as f32 * compact - offset * compact;
            if y < q_rows_y - compact || y > body_bottom {
                continue;
            }
            let selected = i == picker.sel;
            hit(hits, qx, y, qw, compact, Hit::Row(m.view, i));
            if selected {
                list.rounded(
                    qx + 10.0,
                    y,
                    qw - 20.0,
                    compact - 4.0,
                    GEOM.radius_md,
                    th.selection,
                    theme::with_alpha(th.accent2, 0.14),
                );
                list.rounded(
                    qx + 10.0,
                    y + 5.0,
                    2.0,
                    compact - 14.0,
                    1.0,
                    th.accent,
                    th.accent2,
                );
            }
            let idx = format!("{:03}", i + 1);
            fonts.layout_line(
                &mut list,
                &idx,
                qx + 20.0,
                y + 10.0,
                TYPE.caption,
                Face::Mono,
                if selected {
                    theme::with_alpha(th.text, 0.7)
                } else {
                    th.text_faint
                },
            );
            let color = if selected {
                th.text
            } else {
                theme::with_alpha(th.text, 0.88)
            };
            fonts.layout_fitted(
                &mut list,
                name,
                qx + 54.0,
                y + 9.0,
                TYPE.body,
                Face::UiRegular,
                color,
                qw - 76.0,
            );
        }
        if picker.items.is_empty() {
            fonts.layout_line(
                &mut list,
                "загружаю…",
                qx + 20.0,
                q_rows_y + 8.0,
                TYPE.label,
                Face::UiRegular,
                th.text_faint,
            );
        }
        if picker.items.len() as f32 > 1.0 {
            let visible = (body_h - 44.0) / compact;
            let ratio = (visible / picker.items.len() as f32).clamp(0.05, 1.0);
            let track_h = (body_h - 44.0) * ratio;
            let max_scroll = (picker.items.len() as f32 - visible).max(0.0);
            let pos = if max_scroll > 0.0 {
                (offset / max_scroll).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let top_y = q_rows_y + pos * ((body_h - 44.0) - track_h);
            list.rounded(
                qx + qw - 7.0,
                top_y,
                3.0,
                track_h,
                1.5,
                theme::with_alpha(th.text, 0.14),
                theme::with_alpha(th.text, 0.10),
            );
        }
        list.set_clip(None);
    }
    let skip_row_loop = picker_active;
    list.set_clip(Some([qx, q_rows_y - 6.0, qw, body_h - 44.0]));
    let playing_index = m.status.song.unwrap_or(usize::MAX);
    let rows: &[Song] = if search_mode {
        &m.search_results
    } else {
        &m.queue
    };
    let rows_offset = if search_mode { 0.0 } else { m.queue_scroll };
    let mut drawn_rows = 0usize;
    for (i, song) in rows.iter().enumerate().filter(|_| !skip_row_loop) {
        let y = q_rows_y + i as f32 * row_h - rows_offset * row_h;
        if y < q_rows_y - row_h || y > body_bottom {
            continue;
        }
        drawn_rows += 1;
        let verts_before = list.vertices.len();
        let _ = verts_before;
        let selected = active_centre && i == m.queue_sel;
        hit(
            hits,
            qx,
            y,
            qw,
            row_h,
            Hit::Row(
                if search_mode {
                    Pane::Search
                } else {
                    Pane::Queue
                },
                i,
            ),
        );
        let playing = !search_mode && i == playing_index;
        if playing {
            list.rounded(
                qx + 10.0,
                y,
                qw - 20.0,
                row_h - 4.0,
                GEOM.radius_md,
                th.playing_bg,
                th.playing_bg,
            );
        }
        if selected {
            list.rounded(
                qx + 10.0,
                y,
                qw - 20.0,
                row_h - 4.0,
                GEOM.radius_md,
                th.selection,
                theme::with_alpha(th.accent2, 0.14),
            );
            list.rounded(
                qx + 10.0,
                y + 5.0,
                2.0,
                row_h - 14.0,
                1.0,
                th.accent,
                th.accent2,
            );
        }
        if playing {
            for b in 0..3 {
                let phase = t * 5.5 + b as f32 * 0.9;
                let amp = 0.30 + 0.70 * (phase.sin() * 0.5 + 0.5);
                let bh = 4.0 + amp * 10.0;
                list.rounded(
                    qx + 20.0 + b as f32 * 5.0,
                    y + row_h * 0.5 - 2.0 - bh * 0.5,
                    3.0,
                    bh,
                    1.5,
                    th.accent,
                    th.accent2,
                );
            }
        }
        let idx_label = format!("{:02}", i + 1);
        // On the selection pill the accent loses contrast, so accent colouring is reserved for
        // the playing row when it is not the selected one.
        let highlight = playing && !selected;
        fonts.layout_line(
            &mut list,
            &idx_label,
            qx + 40.0,
            y + 9.0,
            TYPE.caption,
            Face::Mono,
            if highlight {
                th.accent
            } else if selected {
                theme::with_alpha(th.text, 0.75)
            } else {
                th.text_faint
            },
        );
        let title_color = if selected {
            th.text
        } else if playing {
            th.accent
        } else {
            theme::with_alpha(th.text, 0.88)
        };
        let title_w = qw - 210.0;
        let face = if playing {
            Face::UiSemiBold
        } else {
            Face::UiRegular
        };
        let secondary = if selected {
            theme::with_alpha(th.text, 0.72)
        } else {
            th.text_faint
        };
        fonts.layout_fitted(
            &mut list,
            &song.title,
            qx + 68.0,
            y + 4.0,
            TYPE.body,
            face,
            title_color,
            title_w,
        );
        fonts.layout_fitted(
            &mut list,
            &song.artist,
            qx + 68.0,
            y + 19.0,
            TYPE.caption,
            Face::UiRegular,
            secondary,
            title_w,
        );
        let dur = fmt_time(song.duration);
        let dw = fonts.measure(&dur, TYPE.caption, Face::Mono);
        fonts.layout_line(
            &mut list,
            &dur,
            qx + qw - 20.0 - dw,
            y + 9.0,
            TYPE.caption,
            Face::Mono,
            if selected {
                theme::with_alpha(th.text, 0.75)
            } else {
                th.text_faint
            },
        );
    }
    if std::env::var("PLAYER_DEBUG_DRAW").is_ok() {
        eprintln!(
            "[draw] rows={} drawn={} q_rows_y={q_rows_y} body_bottom={body_bottom} row_h={row_h} h={h} verts={}",
            rows.len(),
            drawn_rows,
            list.vertices.len()
        );
    }
    if rows.is_empty() && !search_mode {
        fonts.layout_line(
            &mut list,
            "очередь пуста",
            qx + 20.0,
            q_rows_y + 8.0,
            TYPE.label,
            Face::UiRegular,
            th.text_faint,
        );
    }
    if rows.len() as f32 > 1.0 {
        let visible = (body_h - 44.0) / row_h;
        let ratio = (visible / rows.len() as f32).clamp(0.05, 1.0);
        let track_h = (body_h - 44.0) * ratio;
        let max_scroll = (rows.len() as f32 - visible).max(0.0);
        let pos = if max_scroll > 0.0 {
            (rows_offset / max_scroll).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let top_y = q_rows_y + pos * ((body_h - 44.0) - track_h);
        list.rounded(
            qx + qw - 7.0,
            top_y,
            3.0,
            track_h,
            1.5,
            theme::with_alpha(th.text, 0.14),
            theme::with_alpha(th.text, 0.10),
        );
    }
    list.set_clip(None);

    // ---------------- now playing
    if show_right {
        let rx = w - right_w - 16.0;
        list.shadow(rx, body_top, right_w, body_h, GEOM.radius_lg, 26.0, 0.35);
        list.rounded(
            rx,
            body_top,
            right_w,
            body_h,
            GEOM.radius_lg,
            th.panel,
            th.panel,
        );
        list.rect(rx, body_top, right_w, GEOM.line, th.border_hi);
        if m.art.is_some() {
            list.set_clip(Some([rx, body_top, right_w, body_h]));
            list.image(rx, body_top, right_w, body_h, GEOM.radius_lg, th.backdrop);
            list.set_clip(None);
            list.rounded(
                rx,
                body_top,
                right_w,
                body_h,
                GEOM.radius_lg,
                theme::with_alpha(th.bg_bottom, 0.55),
                theme::with_alpha(th.bg_bottom, 0.82),
            );
        }

        let art_size = right_w - pad * 2.0;
        let art_y = body_top + pad;
        list.glow(
            rx + pad - 18.0,
            art_y - 18.0,
            art_size + 36.0,
            art_size + 36.0,
            GEOM.radius_art + 8.0,
            96.0,
            theme::with_alpha(th.accent, 0.12),
        );
        list.shadow(
            rx + pad,
            art_y + 8.0,
            art_size,
            art_size,
            GEOM.radius_art,
            24.0,
            0.50,
        );
        if m.art.is_some() {
            list.image(
                rx + pad,
                art_y,
                art_size,
                art_size,
                GEOM.radius_art,
                [1.0, 1.0, 1.0, 1.0],
            );
        } else {
            list.rounded(
                rx + pad,
                art_y,
                art_size,
                art_size,
                GEOM.radius_art,
                th.panel_inset,
                th.panel,
            );
            let glyph = "♪";
            let gw = fonts.measure(glyph, 64.0, Face::Symbols);
            fonts.layout_line(
                &mut list,
                glyph,
                rx + pad + (art_size - gw) * 0.5,
                art_y + art_size * 0.33,
                64.0,
                Face::Symbols,
                theme::with_alpha(th.text, 0.08),
            );
        }

        let info_y = art_y + art_size + 18.0;
        let info_w = right_w - pad * 2.0;
        let title = m
            .current
            .as_ref()
            .map(|s| s.title.clone())
            .unwrap_or_else(|| "Ничего не играет".into());
        let artist = m
            .current
            .as_ref()
            .map(|s| s.artist.clone())
            .unwrap_or_default();
        let album = m
            .current
            .as_ref()
            .map(|s| s.album.clone())
            .unwrap_or_default();
        let mut title_size = TYPE.display;
        for candidate in [TYPE.display, TYPE.display - 2.0, TYPE.display - 4.0] {
            title_size = candidate;
            if fonts.measure(&title, candidate, Face::UiSemiBold) <= info_w {
                break;
            }
        }
        fonts.layout_fitted(
            &mut list,
            &title,
            rx + pad,
            info_y,
            title_size,
            Face::UiSemiBold,
            th.text,
            info_w,
        );
        fonts.layout_fitted(
            &mut list,
            &artist,
            rx + pad,
            info_y + 30.0,
            TYPE.label + 1.0,
            Face::UiMedium,
            th.accent,
            info_w,
        );
        fonts.layout_fitted(
            &mut list,
            &album,
            rx + pad,
            info_y + 50.0,
            TYPE.label,
            Face::UiRegular,
            th.text_dim,
            info_w,
        );
        if let (Some(pos), true) = (m.status.song, !m.queue.is_empty()) {
            let line = format!("{:02} / {:02}", pos + 1, m.queue.len());
            fonts.layout_line(
                &mut list,
                &line,
                rx + pad,
                info_y + 68.0,
                TYPE.caption,
                Face::Mono,
                th.text_faint,
            );
        }

        // progress
        let total = m.duration();
        let elapsed = m.elapsed().min(total.max(0.001));
        let progress = if total > 0.0 {
            (elapsed / total) as f32
        } else {
            0.0
        };
        let bar_y = info_y + 94.0;
        let bar_w = info_w;
        list.rounded(
            rx + pad,
            bar_y,
            bar_w,
            6.0,
            3.0,
            th.panel_inset,
            th.panel_inset,
        );
        hit(
            hits,
            rx + pad - 6.0,
            bar_y - 8.0,
            bar_w + 12.0,
            22.0,
            Hit::Seek(bar_w),
        );
        if progress > 0.0 {
            let filled = (bar_w * progress.clamp(0.0, 1.0)).max(6.0);
            list.rounded(rx + pad, bar_y, filled, 6.0, 3.0, th.accent, th.accent2);
            list.rounded(
                rx + pad + filled - 5.0,
                bar_y - 3.5,
                10.0,
                12.0,
                5.0,
                th.text,
                theme::with_alpha(th.text, 0.9),
            );
        }
        let e_label = fmt_time(elapsed);
        let t_label = fmt_time(total);
        fonts.layout_line(
            &mut list,
            &e_label,
            rx + pad,
            bar_y + 10.0,
            TYPE.caption,
            Face::Mono,
            th.text_dim,
        );
        let tw2 = fonts.measure(&t_label, TYPE.caption, Face::Mono);
        fonts.layout_line(
            &mut list,
            &t_label,
            rx + pad + bar_w - tw2,
            bar_y + 10.0,
            TYPE.caption,
            Face::Mono,
            th.text_faint,
        );

        // transport
        let ty = bar_y + 42.0;
        let center = rx + pad + bar_w * 0.5;
        let playing = m.status.state == "play";
        list.rounded(
            center - 26.0,
            ty - 7.0,
            52.0,
            34.0,
            GEOM.radius_pill,
            theme::with_alpha(th.accent, 0.16),
            theme::with_alpha(th.accent2, 0.10),
        );
        hit(
            hits,
            center - 100.0,
            ty - 8.0,
            40.0,
            34.0,
            Hit::Transport(-1),
        );
        hit(hits, center - 26.0, ty - 8.0, 52.0, 34.0, Hit::Transport(0));
        hit(hits, center + 60.0, ty - 8.0, 40.0, 34.0, Hit::Transport(1));
        list.rounded(
            center - 26.0,
            ty - 7.0,
            52.0,
            34.0,
            GEOM.radius_pill,
            [0.0; 4],
            [0.0; 4],
        );
        for (sym, dx, size, color, face) in [
            ("◀◀", -74.0, 15.0, th.text_dim, Face::Symbols),
            (
                if playing { "▮▮" } else { "▶" },
                0.0,
                19.0,
                th.text,
                Face::Symbols,
            ),
            ("▶▶", 74.0, 15.0, th.text_dim, Face::Symbols),
        ] {
            let sw = fonts.measure(sym, size, face);
            fonts.layout_line(
                &mut list,
                sym,
                center + dx - sw * 0.5,
                ty,
                size,
                face,
                color,
            );
        }

        // volume
        let vol_y = ty + 44.0;
        let vol = if m.status.volume < 0 {
            0
        } else {
            m.status.volume
        };
        fonts.layout_line(
            &mut list,
            "VOL",
            rx + pad,
            vol_y - 1.0,
            TYPE.micro,
            Face::UiMedium,
            th.text_faint,
        );
        let vbar_x = rx + pad + 34.0;
        let vbar_w = info_w - 74.0;
        list.rounded(
            vbar_x,
            vol_y,
            vbar_w,
            4.0,
            2.0,
            th.panel_inset,
            th.panel_inset,
        );
        hit(
            hits,
            vbar_x - 6.0,
            vol_y - 8.0,
            vbar_w + 12.0,
            20.0,
            Hit::Volume(vbar_w),
        );
        if vol > 0 {
            list.rounded(
                vbar_x,
                vol_y,
                vbar_w * (vol as f32 / 100.0),
                4.0,
                2.0,
                theme::with_alpha(th.text, 0.75),
                theme::with_alpha(th.text, 0.6),
            );
        }
        let vol_label = format!("{vol}%");
        let vw = fonts.measure(&vol_label, TYPE.caption, Face::Mono);
        fonts.layout_line(
            &mut list,
            &vol_label,
            rx + pad + info_w - vw,
            vol_y - 2.0,
            TYPE.caption,
            Face::Mono,
            th.text_dim,
        );

        // mode chips
        let mut cx = rx + pad;
        let chip_y = vol_y + 24.0;
        for (chip_index, (label, on)) in [
            ("repeat", m.status.repeat),
            ("random", m.status.random),
            ("single", m.status.single),
            ("consume", m.status.consume),
        ]
        .into_iter()
        .enumerate()
        {
            let cw2 = fonts.measure(label, TYPE.caption, Face::UiMedium) + 18.0;
            hit(hits, cx, chip_y, cw2, 22.0, Hit::Chip(chip_index as u8));
            let (bg1, bg2, fg) = if on {
                (
                    th.accent_soft,
                    theme::with_alpha(th.accent2, 0.12),
                    th.accent,
                )
            } else {
                (
                    theme::with_alpha(th.text, 0.05),
                    theme::with_alpha(th.text, 0.03),
                    th.text_faint,
                )
            };
            list.rounded(cx, chip_y, cw2, 22.0, GEOM.radius_pill, bg1, bg2);
            fonts.layout_line(
                &mut list,
                label,
                cx + 9.0,
                chip_y + 4.0,
                TYPE.caption,
                Face::UiMedium,
                fg,
            );
            cx += cw2 + 6.0;
        }

        // "next up": the queue entry after the playing one, when known.
        if let Some(pos) = m.status.song {
            if let Some(next) = m.queue.get(pos + 1) {
                let y = chip_y + 62.0;
                fonts.layout_line(
                    &mut list,
                    "ДАЛЕЕ",
                    rx + pad,
                    y,
                    TYPE.micro,
                    Face::UiMedium,
                    th.text_faint,
                );
                fonts.layout_fitted(
                    &mut list,
                    &next.title,
                    rx + pad,
                    y + 16.0,
                    TYPE.label,
                    Face::UiMedium,
                    theme::with_alpha(th.text, 0.86),
                    info_w,
                );
                fonts.layout_fitted(
                    &mut list,
                    &next.artist,
                    rx + pad,
                    y + 32.0,
                    TYPE.caption,
                    Face::UiRegular,
                    th.text_faint,
                    info_w,
                );
            }
        }

        if let Some(audio) = &m.status.audio {
            let line = match m.status.bitrate {
                Some(b) => format!("{audio} · {b} kbps"),
                None => audio.clone(),
            };
            fonts.layout_fitted(
                &mut list,
                &line,
                rx + pad,
                body_bottom - 22.0,
                TYPE.caption,
                Face::Mono,
                th.text_faint,
                info_w,
            );
        }
    }

    // ---------------- status bar
    list.gradient(
        0.0,
        h - 36.0,
        w,
        36.0,
        theme::with_alpha(th.panel_hi, 0.7),
        theme::with_alpha(th.panel, 0.9),
    );
    list.rect(0.0, h - 36.0, w, GEOM.line, th.border);
    if m.mode == InputMode::Command || m.mode == InputMode::Search {
        let (sigil, text, hint) = if m.mode == InputMode::Command {
            (":", m.cmdline.clone(), "enter — выполнить · esc — отмена")
        } else {
            ("/", m.search_input.clone(), "enter — искать · esc — отмена")
        };
        let caret = "▏";
        let line = format!("{sigil}{text}{caret}");
        list.rounded(
            pad - 4.0,
            h - 32.0,
            (w - pad * 2.0 + 8.0).min(w - 8.0),
            26.0,
            GEOM.radius_md,
            th.panel_inset,
            th.panel_inset,
        );
        fonts.layout_line(
            &mut list,
            &line,
            pad,
            h - 27.0,
            TYPE.body,
            Face::Mono,
            th.accent,
        );
        let lw = fonts.measure(&line, TYPE.body, Face::Mono);
        fonts.layout_fitted(
            &mut list,
            hint,
            pad + lw + 16.0,
            h - 26.0,
            TYPE.caption,
            Face::UiRegular,
            th.text_faint,
            w - pad * 2.0 - lw - 20.0,
        );
    } else if show_right || w < 700.0 {
        let hints = "j/k move · tab pane · enter play · p pause · s stop · >/< track · f/b ±5s · =/- vol · z r y R modes · / find · : cmd · w help · q quit";
        fonts.layout_fitted(
            &mut list,
            hints,
            pad,
            h - 25.0,
            TYPE.caption,
            Face::UiRegular,
            th.text_faint,
            w - pad * 2.0,
        );
    } else {
        let state = if m.status.state == "play" {
            "▶"
        } else {
            "■"
        };
        let line = format!(
            "{state} {} — {}   {} / {}",
            m.current
                .as_ref()
                .map(|s| s.title.as_str())
                .unwrap_or("ничего не играет"),
            m.current.as_ref().map(|s| s.artist.as_str()).unwrap_or(""),
            fmt_time(m.elapsed()),
            fmt_time(m.duration())
        );
        fonts.layout_fitted(
            &mut list,
            &line,
            pad,
            h - 25.0,
            TYPE.caption,
            Face::UiRegular,
            th.text_dim,
            w - pad * 2.0,
        );
    }
    if m.outputs_open {
        list.rect(0.0, 0.0, w, h, theme::with_alpha(th.bg_bottom, 0.78));
        let panel_w = 520.0_f32.min(w - 80.0);
        let row_h2 = 34.0;
        let panel_h = 92.0 + m.outputs.len().max(1) as f32 * row_h2;
        let px = (w - panel_w) * 0.5;
        let py = (h - panel_h) * 0.5;
        list.rounded(px, py, panel_w, panel_h, GEOM.radius_lg, th.panel, th.panel);
        list.rect(px, py, panel_w, GEOM.line, th.border_hi);
        fonts.layout_line(
            &mut list,
            "ВЫХОДЫ",
            px + 24.0,
            py + 20.0,
            TYPE.micro,
            Face::UiMedium,
            th.text_faint,
        );
        let hint = "клик / space — переключить · o или esc — закрыть";
        let hw = fonts.measure(hint, TYPE.caption, Face::UiRegular);
        fonts.layout_line(
            &mut list,
            hint,
            px + panel_w - 24.0 - hw,
            py + 20.0,
            TYPE.caption,
            Face::UiRegular,
            th.text_faint,
        );
        if m.outputs.is_empty() {
            fonts.layout_line(
                &mut list,
                "нет данных — нажми o",
                px + 24.0,
                py + 56.0,
                TYPE.label,
                Face::UiRegular,
                th.text_faint,
            );
        }
        for (i, out) in m.outputs.iter().enumerate() {
            let y = py + 56.0 + i as f32 * row_h2;
            let on = out.enabled;
            hit(
                hits,
                px + 16.0,
                y,
                panel_w - 32.0,
                row_h2 - 4.0,
                Hit::Output(i),
            );
            let focused = i == m.outputs_focus;
            if focused {
                list.rounded(
                    px + 12.0,
                    y - 2.0,
                    panel_w - 24.0,
                    row_h2,
                    GEOM.radius_md + 2.0,
                    theme::with_alpha(th.accent, 0.10),
                    theme::with_alpha(th.accent2, 0.08),
                );
            }
            list.rounded(
                px + 16.0,
                y,
                panel_w - 32.0,
                row_h2 - 4.0,
                GEOM.radius_md,
                if on {
                    th.selection
                } else {
                    theme::with_alpha(th.text, 0.03)
                },
                if on {
                    theme::with_alpha(th.accent2, 0.12)
                } else {
                    theme::with_alpha(th.text, 0.02)
                },
            );
            list.rounded(
                px + 28.0,
                y + 12.0,
                8.0,
                8.0,
                4.0,
                if on {
                    th.success
                } else {
                    theme::with_alpha(th.text, 0.25)
                },
                if on {
                    th.success
                } else {
                    theme::with_alpha(th.text, 0.25)
                },
            );
            fonts.layout_fitted(
                &mut list,
                &out.name,
                px + 48.0,
                y + 8.0,
                TYPE.body,
                Face::UiRegular,
                if on { th.text } else { th.text_dim },
                panel_w - 160.0,
            );
            let state = if on { "on" } else { "off" };
            let sw = fonts.measure(state, TYPE.caption, Face::Mono);
            fonts.layout_line(
                &mut list,
                state,
                px + panel_w - 32.0 - sw,
                y + 10.0,
                TYPE.caption,
                Face::Mono,
                if on { th.success } else { th.text_faint },
            );
        }
    }

    if m.mode == InputMode::Help {
        list.rect(0.0, 0.0, w, h, theme::with_alpha(th.bg_bottom, 0.78));
        // Column widths follow the content: mono key strings and Russian action labels differ a
        // lot in width, so a fixed offset overlaps them.
        let key_w = KEYMAP
            .iter()
            .map(|r| fonts.measure(r.keys, TYPE.caption, Face::Mono))
            .fold(0.0_f32, f32::max);
        let act_w = KEYMAP
            .iter()
            .map(|r| fonts.measure(r.action, TYPE.caption, Face::UiRegular))
            .fold(0.0_f32, f32::max)
            .clamp(120.0, 240.0);
        let col_w = key_w + 14.0 + act_w;
        let panel_w = (col_w * 2.0 + 56.0).min(w - 64.0);
        let rows = KEYMAP.len().div_ceil(2);
        let panel_h = 92.0 + rows as f32 * 26.0;
        let px = (w - panel_w) * 0.5;
        let py = (h - panel_h) * 0.5;
        list.rounded(px, py, panel_w, panel_h, GEOM.radius_lg, th.panel, th.panel);
        list.rect(px, py, panel_w, GEOM.line, th.border_hi);
        fonts.layout_line(
            &mut list,
            "КЛАВИШИ",
            px + 28.0,
            py + 20.0,
            TYPE.micro,
            Face::UiMedium,
            th.text_faint,
        );
        fonts.layout_line(
            &mut list,
            "в духе rmpc",
            px + 28.0,
            py + 38.0,
            TYPE.label,
            Face::UiRegular,
            th.text_dim,
        );
        let hint = "? или esc — закрыть";
        let hw = fonts.measure(hint, TYPE.caption, Face::UiRegular);
        fonts.layout_line(
            &mut list,
            hint,
            px + panel_w - 28.0 - hw,
            py + 22.0,
            TYPE.caption,
            Face::UiRegular,
            th.text_faint,
        );
        for (i, row) in KEYMAP.iter().enumerate() {
            let col = (i % 2) as f32;
            let line = (i / 2) as f32;
            let x = px + 28.0 + col * col_w;
            let y = py + 74.0 + line * 26.0;
            fonts.layout_line(
                &mut list,
                row.keys,
                x,
                y,
                TYPE.caption,
                Face::Mono,
                th.accent,
            );
            fonts.layout_fitted(
                &mut list,
                row.action,
                x + key_w + 14.0,
                y,
                TYPE.caption,
                Face::UiRegular,
                th.text_dim,
                act_w,
            );
        }
    }

    if let Some((msg, at)) = &m.toast {
        if at.elapsed().as_secs() < 4 {
            let tw = fonts.measure(msg, TYPE.label, Face::UiMedium);
            list.rounded(
                w * 0.5 - tw * 0.5 - 14.0,
                h - 76.0,
                tw + 28.0,
                26.0,
                GEOM.radius_pill,
                theme::with_alpha(th.danger, 0.22),
                theme::with_alpha(th.danger, 0.14),
            );
            fonts.layout_line(
                &mut list,
                msg,
                w * 0.5 - tw * 0.5,
                h - 71.0,
                TYPE.label,
                Face::UiMedium,
                theme::with_alpha(th.danger, 1.0),
            );
        }
    }

    list
}

impl winit::application::ApplicationHandler for App {
    fn suspended(&mut self, _event_loop: &winit::event_loop::ActiveEventLoop) {
        eprintln!("[event] suspended (compositor unmapped the surface)");
    }

    fn resumed(&mut self, event_loop: &winit::event_loop::ActiveEventLoop) {
        eprintln!("[event] resumed");
        // A stable Wayland app_id so the compositor can target the window with a rule
        // (float at the design size instead of being tiled into a column).
        #[cfg(all(unix, not(any(target_os = "macos", target_os = "ios"))))]
        let attrs = winit::platform::wayland::WindowAttributesExtWayland::with_name(
            winit::window::Window::default_attributes(),
            "player",
            "player",
        )
        .with_title("Player — MPD");
        #[cfg(not(all(unix, not(any(target_os = "macos", target_os = "ios")))))]
        let attrs = winit::window::Window::default_attributes().with_title("Player — MPD");
        let attrs = attrs.with_inner_size({
            let arg = std::env::args().find(|a| a.starts_with("--size="));
            let (w, h) = arg
                .and_then(|a| {
                    let v = a[7..].to_string();
                    let (w, h) = v.split_once('x')?;
                    Some((w.parse::<f64>().ok()?, h.parse::<f64>().ok()?))
                })
                .unwrap_or((1440.0, 900.0));
            winit::dpi::LogicalSize::new(w, h)
        });
        let window = match event_loop.create_window(attrs) {
            Ok(w) => w,
            Err(e) => {
                eprintln!("window: {e}");
                event_loop.exit();
                return;
            }
        };
        self.timing.mark("window");
        {
            let size = window.inner_size();
            let scale = window.scale_factor();
            eprintln!(
                "[window] inner_size={}x{} scale={scale}",
                size.width, size.height
            );
        }
        let mut init = InitTiming {
            timing: &mut self.timing,
        };
        match create_gpu(&window, &mut init, self.render_size) {
            Some(mut gpu) => {
                gpu.set_capture_size(self.render_size);
                self.gpu = Some(gpu);
            }
            None => {
                eprintln!("vulkan init failed");
                event_loop.exit();
                return;
            }
        }
        if let Some(gpu) = self.gpu.as_ref() {
            eprintln!(
                "[swapchain] extent={}x{} format={:?}",
                gpu.extent.width, gpu.extent.height, gpu.format
            );
        }
        self.fonts = Some(Fonts::new());
        self.timing.mark("ready");
        let _ = self.tx.send(Cmd::LoadDir("/".into()));
        if let Ok(q) = std::env::var("PLAYER_SEARCH") {
            if !q.is_empty() {
                let _ = self.tx.send(Cmd::Search(q));
            }
        }
        window.request_redraw();
        self.window = Some(window);
    }

    fn window_event(
        &mut self,
        event_loop: &winit::event_loop::ActiveEventLoop,
        _id: winit::window::WindowId,
        event: WindowEvent,
    ) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::KeyboardInput { event, .. } => self.handle_key(&event, false, false),
            WindowEvent::CursorMoved { position, .. } => {
                self.cursor = (position.x as f32, position.y as f32);
            }
            WindowEvent::MouseInput {
                state: ElementState::Pressed,
                button: winit::event::MouseButton::Left,
                ..
            } => {
                self.handle_click();
            }
            WindowEvent::MouseWheel { delta, .. } => {
                let step = match delta {
                    MouseScrollDelta::LineDelta(_, y) => y as i32,
                    MouseScrollDelta::PixelDelta(p) => (p.y / 30.0) as i32,
                };
                self.move_selection(-step);
            }
            WindowEvent::Occluded(v) => eprintln!("[event] occluded={v}"),
            WindowEvent::Focused(v) => eprintln!("[event] focused={v}"),
            WindowEvent::Resized(size) => {
                eprintln!("[event] resized={}x{}", size.width, size.height);
                if size.width == 0 || size.height == 0 {
                    return; // minimised: keep the last swapchain
                }
                self.sync_surface(size.width, size.height);
            }
            WindowEvent::ScaleFactorChanged { scale_factor, .. } => {
                eprintln!("[event] scale_factor={scale_factor}");
                self.scale = scale_factor as f32;
                if let Some(fonts) = self.fonts.as_mut() {
                    fonts.set_scale(self.scale);
                    // Glyph cache stays valid: atlas UVs do not depend on scale.
                }
                // The buffer has to be rebuilt even if the logical size did not change: the
                // physical size did. Re-derive from the window, not from the old extent.
                if let Some(w) = self.window.as_ref() {
                    let size = w.inner_size();
                    self.sync_surface(size.width, size.height);
                }
                if let Some(w) = self.window.as_ref() {
                    w.request_redraw();
                }
            }
            WindowEvent::RedrawRequested => {
                if let Some(at) = self.exit_frame {
                    if self.frames >= at {
                        self.timing.report(false);
                        event_loop.exit();
                        return;
                    }
                }
                self.drain_updates();
                self.animate();
                // Layout size: logical units by default (physical / scale), or the pinned
                // capture size. The shader gets exactly this as its resolution, so the UI always
                // fills the surface instead of covering a fraction of it.
                if let Some(fonts) = self.fonts.as_mut() {
                    fonts.set_scale(self.scale);
                }
                let (lw, lh) = self.logical_size();
                let extent = match self.render_size {
                    Some((w, h)) => ash::vk::Extent2D {
                        width: w,
                        height: h,
                    },
                    None => ash::vk::Extent2D {
                        width: lw,
                        height: lh,
                    },
                };
                if let Some(gpu) = self.gpu.as_mut() {
                    gpu.set_push_res(extent.width as f32, extent.height as f32);
                }
                // The driver says the surface no longer matches the swapchain: rebuild before
                // the next frame instead of accumulating mismatched buffers.
                if self.gpu.as_ref().is_some_and(|g| g.needs_resize) {
                    if let Some(gpu) = self.gpu.as_mut() {
                        gpu.needs_resize = false;
                    }
                    self.last_resize = Instant::now() - Duration::from_secs(1);
                    let size = self
                        .window
                        .as_ref()
                        .map(|w| w.inner_size())
                        .unwrap_or_default();
                    self.sync_surface(size.width.max(1), size.height.max(1));
                    if let Some(gpu) = self.gpu.as_ref() {
                        if let Some(fonts) = self.fonts.as_mut() {
                            fonts.set_scale(self.scale);
                        }
                        let (lw, lh) = self.logical_size();
                        let _ = (lw, lh, gpu.extent);
                    }
                }

                // upload art once per track
                if let Some((aw, ah, rgba)) = self.model.art.clone() {
                    if self.art_uploaded != self.model.art_uri {
                        if let Some(gpu) = self.gpu.as_mut() {
                            match unsafe { gpu.upload_art(aw, ah, &rgba) } {
                                Ok(()) => self.art_uploaded = self.model.art_uri.clone(),
                                Err(e) => eprintln!("art upload failed: {e}"),
                            }
                        }
                    }
                }
                // Scripted keys: one token per 30 frames, so each state gets its own capture.
                if !self.keys.is_empty() {
                    let due = 60 + self.key_cursor * 30;
                    if self.frames as usize >= due && self.key_cursor < self.keys.len() {
                        let token = self.keys[self.key_cursor].clone();
                        self.apply_token(&token);
                        self.key_cursor += 1;
                        self.pending_shot = true;
                        eprintln!(
                            "[keys] applied {token} at frame {} (cursor {})",
                            self.frames, self.key_cursor
                        );
                        if self.dump_state_each_key {
                            self.dump_state(&token);
                        }
                    }
                }
                let t = self.started.elapsed().as_secs_f32();
                let theme = theme::Theme::by_name(&self.theme_name);
                let mut hits: Vec<HitArea> = Vec::new();
                let list = draw_ui(
                    self.fonts.as_mut().unwrap(),
                    &self.model,
                    extent,
                    t,
                    theme,
                    &mut hits,
                );
                self.hits = hits;
                let clear = theme.bg_bottom;
                // Glyphs land in the CPU atlas while building the list, so the GPU copy has to
                // happen after layout and before the draw that references those UVs.
                if let Some(fonts) = self.fonts.as_mut() {
                    if fonts.atlas_dirty {
                        if let Some(gpu) = self.gpu.as_mut() {
                            match unsafe { gpu.upload_atlas(&fonts.atlas) } {
                                Ok(()) => fonts.atlas_dirty = false,
                                Err(e) => eprintln!("atlas upload failed: {e}"),
                            }
                        }
                    }
                }
                self.frames += 1;
                if self.frames == 1 || self.frames % 120 == 0 {
                    eprintln!(
                        "[frame] n={} verts={} batches={} queue={} lib={} connected={}",
                        self.frames,
                        list.vertices.len(),
                        list.batches.len(),
                        self.model.queue.len(),
                        self.model.lib_entries.len(),
                        self.model.connected
                    );
                    eprintln!(
                        "[frame] extent={}x{} h={} body_h={} rows",
                        extent.width,
                        extent.height,
                        self.logical_size().1,
                        self.model.queue.len()
                    );
                }
                if std::env::var("PLAYER_DEBUG").is_ok() && self.frames % 30 == 0 {
                    let mut shape = 0;
                    let mut text = 0;
                    let mut image = 0;
                    for b in &list.batches {
                        match b.kind {
                            player_proto::scene::Kind::Shape => shape += b.count,
                            player_proto::scene::Kind::Text => text += b.count,
                            player_proto::scene::Kind::Image => image += b.count,
                        }
                    }
                    eprintln!(
                        "frame {}: verts={} batches={} shape={} text={} image={} | queue={} lib={} connected={} art={}",
                        self.frames,
                        list.vertices.len(),
                        list.batches.len(),
                        shape,
                        text,
                        image,
                        self.model.queue.len(),
                        self.model.lib_entries.len(),
                        self.model.connected,
                        self.model.art.is_some()
                    );
                }
                if let (Some(gpu), Some(window)) = (self.gpu.as_mut(), self.window.as_ref()) {
                    if let Err(e) = unsafe { gpu.draw(&list, clear) } {
                        eprintln!("draw failed: {e}");
                        event_loop.exit();
                        return;
                    }
                    if let Some(frames) = self.bench_frames {
                        if self.frames == self.shot_frames as u64 {
                            if unsafe { gpu.bench(&list, frames, clear) }.is_ok() {
                                self.timing.report(false);
                            }
                            event_loop.exit();
                            return;
                        }
                    }
                    if let (Some(prefix), true) = (self.shot_seq.clone(), self.pending_shot) {
                        self.pending_shot = false;
                        let path = format!("{prefix}-{}.ppm", self.key_cursor);
                        if unsafe { gpu.shot(&list, &path, clear) }.is_ok()
                            && self.key_cursor == self.keys.len()
                        {
                            self.exit_frame = Some(self.frames + 40);
                        }
                    }
                    if let Ok(path) = std::env::var("PLAYER_DUMP_SWAPCHAIN") {
                        if self.frames == 90 {
                            if let Err(e) =
                                unsafe { gpu.dump_presented(gpu.last_present_index, &path) }
                            {
                                eprintln!("swapchain dump failed: {e}");
                            }
                        }
                    }
                    if let Some(path) = self.shot_path.clone() {
                        if self.frames == self.shot_frames as u64 {
                            if unsafe { gpu.shot(&list, &path, clear) }.is_ok() {
                                self.timing.report(false);
                            }
                            event_loop.exit();
                            return;
                        }
                    }
                    window.request_redraw();
                }
            }
            _ => {}
        }
    }

    fn about_to_wait(&mut self, event_loop: &winit::event_loop::ActiveEventLoop) {
        event_loop.set_control_flow(winit::event_loop::ControlFlow::WaitUntil(
            Instant::now() + Duration::from_millis(16),
        ));
    }
}

fn main() {
    let addr = std::env::args()
        .find(|a| a.starts_with("--mpd="))
        .map(|a| a[6..].to_string())
        .unwrap_or_else(|| "127.0.0.1:6600".to_string());
    let (tx_cmd, rx_cmd) = std::sync::mpsc::channel();
    let (tx_up, rx_up) = std::sync::mpsc::channel();
    spawn_mpd_worker(addr, tx_up, rx_cmd);
    let mut app = App::new(tx_cmd, rx_up);
    let event_loop = match winit::event_loop::EventLoop::new() {
        Ok(el) => el,
        Err(e) => {
            // winit's error is accurate but unhelpful on its own: say which piece is missing.
            eprintln!("не удалось подключиться к Wayland: {e}");
            let display = std::env::var("WAYLAND_DISPLAY").unwrap_or_else(|_| "<не задан>".into());
            let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "<не задан>".into());
            eprintln!("  WAYLAND_DISPLAY={display}  XDG_RUNTIME_DIR={runtime}");
            let socket = std::path::Path::new(&runtime).join(&display);
            eprintln!(
                "  сокет {}: {}",
                socket.display(),
                if socket.exists() {
                    "есть"
                } else {
                    "не найден"
                }
            );
            for lib in [
                "libwayland-client.so.0",
                "libxkbcommon.so.0",
                "libvulkan.so.1",
            ] {
                eprintln!("  {lib}: ищи через launch-live.sh (он выставляет LD_LIBRARY_PATH)");
            }
            eprintln!(
                "подсказка: запускай через ./launch-live.sh — он проверяет библиотеки до старта"
            );
            std::process::exit(1);
        }
    };
    let _ = event_loop.run_app(&mut app);
    if let Some(mut gpu) = app.gpu.take() {
        gpu.destroy();
    }
}
