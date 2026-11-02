//! Execute recognised intents against MPD and phrase the spoken reply.
//!
//! Port of `mpd_voice/session.py`. The phrase tables below are generated from
//! the Python module, so the wording cannot drift between the two clients.

use crate::config::Config;
use crate::intents::{self, Intent};
use crate::json::Value;
use crate::mpd::{Meta, MpdClient, MpdError, SEARCH_TAGS};
use crate::song::{describe, duration_to_clock};
use std::path::{Path, PathBuf};

pub const RU: [(&str, &str); 48] = [
    ("nothing", "Сейчас ничего не играет."),
    ("now_moods", "{what} ({moods})"),
    ("paused_state", "На паузе: {what}."),
    ("stopped_state", "Воспроизведение остановлено."),
    ("started", "Играю."),
    ("paused", "Пауза."),
    ("resumed", "Продолжаю."),
    ("stopped", "Остановил."),
    ("volume", "Громкость {value} процентов."),
    ("volume_unsupported", "Устройство не поддерживает регулировку громкости."),
    ("muted", "Звук выключен."),
    ("unmuted", "Вернул громкость {value} процентов."),
    ("seek_forward", "Перемотал вперёд на {seconds} секунд."),
    ("seek_back", "Перемотал назад на {seconds} секунд."),
    ("seek_to", "Перемотал на {position}."),
    ("playing_album", "Играю альбом {name}, треков: {count}."),
    ("playing_artist", "Играю {name}, треков: {count}."),
    ("playing_track", "Играю {name}."),
    ("playing_many", "Играю {count} треков по запросу {name}."),
    ("not_found", "Не нашёл: {name}."),
    ("added", "Добавил в очередь треков: {count}."),
    ("similar_added", "Добавил в очередь похожих треков: {count}."),
    ("similar_empty", "Похожих треков не нашлось."),
    ("similar_nothing", "Сейчас ничего не играет."),
    ("similar_no_dir", "Каталог музыки не задан или не существует."),
    ("similar_missing", "Не нашёл файл текущего трека в каталоге музыки."),
    ("similar_failed", "Помощник по похожим трекам не сработал."),
    ("describe_failed", "Описание трека не получилось."),
    ("mood_added", "Добавил {count} треков в настроении {mood}."),
    ("mood_empty", "Не нашёл треков в настроении {mood}."),
    ("mood_no_dir", "Каталог музыки не задан или не существует."),
    ("mood_missing", "Файл тегов настроений не найден: {path}. Соберите его командой: music-mtg-tags --dir ~/music --out {path} --json"),
    ("mood_broken", "Не смог прочитать файл тегов: все {count} строк повреждены."),
    ("mood_failed", "Не смог прочитать файл тегов настроений."),
    ("queue_cleared", "Очередь очищена."),
    ("playlists", "Плейлисты: {names}."),
    ("playlists_empty", "Плейлистов нет."),
    ("playlist_loaded", "Загрузил плейлист {name}, треков: {count}."),
    ("playlist_saved", "Сохранил очередь как плейлист {name}."),
    ("mode_on", "{what} включено."),
    ("mode_off", "{what} выключено."),
    ("crossfade", "Кроссфейд {value} секунд."),
    ("updating", "Обновляю библиотеку."),
    ("help", "Скажите: громче, тише, следующий, пауза, продолжи, что играет, включи альбом или исполнителя."),
    ("bye", "Выключаюсь."),
    ("unknown", "Не понял: {text}."),
    ("error", "MPD вернул ошибку: {message}."),
    ("offline", "Нет связи с MPD."),
];

pub const EN: [(&str, &str); 48] = [
    ("nothing", "Nothing is playing right now."),
    ("now_moods", "{what} ({moods})"),
    ("paused_state", "Paused: {what}."),
    ("stopped_state", "Playback is stopped."),
    ("started", "Playing."),
    ("paused", "Paused."),
    ("resumed", "Resuming."),
    ("stopped", "Stopped."),
    ("volume", "Volume {value} percent."),
    ("volume_unsupported", "This output does not support volume control."),
    ("muted", "Muted."),
    ("unmuted", "Volume back to {value} percent."),
    ("seek_forward", "Skipped forward {seconds} seconds."),
    ("seek_back", "Skipped back {seconds} seconds."),
    ("seek_to", "Jumped to {position}."),
    ("playing_album", "Playing album {name}, {count} tracks."),
    ("playing_artist", "Playing {name}, {count} tracks."),
    ("playing_track", "Playing {name}."),
    ("playing_many", "Playing {count} tracks matching {name}."),
    ("not_found", "Nothing found for: {name}."),
    ("added", "Added {count} tracks to the queue."),
    ("similar_added", "Added {count} similar tracks to the queue."),
    ("similar_empty", "No similar tracks found."),
    ("similar_nothing", "Nothing is playing right now."),
    ("similar_no_dir", "The music directory is not set or does not exist."),
    ("similar_missing", "The current track is not under the music directory."),
    ("similar_failed", "The similarity helper failed."),
    ("describe_failed", "The description helper failed."),
    ("mood_added", "Added {count} {mood} tracks to the queue."),
    ("mood_empty", "No tracks found with mood {mood}."),
    ("mood_no_dir", "The music directory is not set or does not exist."),
    ("mood_missing", "Mood tag file not found: {path}. Build it with: music-mtg-tags --dir ~/music --out {path} --json"),
    ("mood_broken", "Could not read the tag file: all {count} lines are broken."),
    ("mood_failed", "Could not read the mood tag file."),
    ("queue_cleared", "Queue cleared."),
    ("playlists", "Playlists: {names}."),
    ("playlists_empty", "There are no playlists."),
    ("playlist_loaded", "Loaded playlist {name}, {count} tracks."),
    ("playlist_saved", "Saved the queue as playlist {name}."),
    ("mode_on", "{what} on."),
    ("mode_off", "{what} off."),
    ("crossfade", "Crossfade {value} seconds."),
    ("updating", "Updating the library."),
    ("help", "Try: louder, quieter, next, pause, resume, what is playing, play album or artist."),
    ("bye", "Shutting down."),
    ("unknown", "I did not understand: {text}."),
    ("error", "MPD reported an error: {message}."),
    ("offline", "MPD is unreachable."),
];

pub const MODE_NAMES_RU: [(&str, &str); 4] = [
    ("random", "Перемешивание"),
    ("repeat", "Повтор"),
    ("single", "Повтор одного трека"),
    ("consume", "Удаление проигранного"),
];

pub const MODE_NAMES_EN: [(&str, &str); 4] = [
    ("random", "Shuffle"),
    ("repeat", "Repeat"),
    ("single", "Single track repeat"),
    ("consume", "Consume"),
];

/// What the client says back and how the session should continue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reply {
    pub text: String,
    pub ok: bool,
    pub should_exit: bool,
}

impl Reply {
    pub fn ok(text: impl Into<String>) -> Self {
        Reply {
            text: text.into(),
            ok: true,
            should_exit: false,
        }
    }

    pub fn failed(text: impl Into<String>) -> Self {
        Reply {
            text: text.into(),
            ok: false,
            should_exit: false,
        }
    }
}

fn phrase_table(lang: &str) -> &'static [(&'static str, &'static str)] {
    if lang == "en" {
        &EN
    } else {
        &RU
    }
}

fn mode_names(lang: &str) -> &'static [(&'static str, &'static str)] {
    if lang == "en" {
        &MODE_NAMES_EN
    } else {
        &MODE_NAMES_RU
    }
}

/// `str.format(**kwargs)` for the placeholders the reply table uses.
fn format_template(template: &str, args: &[(&str, String)]) -> String {
    let mut out = template.to_string();
    for (key, value) in args {
        out = out.replace(&format!("{{{key}}}"), value);
    }
    out
}

/// Expand a leading `~` the way `Path.expanduser()` does for our config values.
pub fn expand_user(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    if path == "~" {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home);
        }
    }
    PathBuf::from(path)
}

/// fnmatch-style glob: `*`, `?`, `[abc]`, `[!abc]`.
pub fn glob_match(pattern: &str, text: &str) -> bool {
    let pattern: Vec<char> = pattern.chars().collect();
    let text: Vec<char> = text.chars().collect();
    glob_at(&pattern, &text)
}

fn glob_at(pattern: &[char], text: &[char]) -> bool {
    if pattern.is_empty() {
        return text.is_empty();
    }
    match pattern[0] {
        '*' => {
            for index in 0..=text.len() {
                if glob_at(&pattern[1..], &text[index..]) {
                    return true;
                }
            }
            false
        }
        '?' => !text.is_empty() && glob_at(&pattern[1..], &text[1..]),
        '[' => {
            let Some(close) = pattern.iter().position(|ch| *ch == ']') else {
                return false;
            };
            if text.is_empty() {
                return false;
            }
            let mut set = &pattern[1..close];
            let negated = matches!(set.first(), Some('!') | Some('^'));
            if negated {
                set = &set[1..];
            }
            let mut hit = false;
            let mut index = 0;
            while index < set.len() {
                if index + 2 < set.len() && set[index + 1] == '-' {
                    if (set[index]..=set[index + 2]).contains(&text[0]) {
                        hit = true;
                    }
                    index += 3;
                } else {
                    if set[index] == text[0] {
                        hit = true;
                    }
                    index += 1;
                }
            }
            if hit != negated && glob_at(&pattern[close + 1..], &text[1..]) {
                return true;
            }
            false
        }
        ch => !text.is_empty() && text[0] == ch && glob_at(&pattern[1..], &text[1..]),
    }
}

/// Deterministic-enough shuffle for the mood pool (no crates, no crypto).
fn shuffle<T>(items: &mut [T]) {
    let mut state = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|delta| delta.as_nanos() as u64)
        .unwrap_or(0x9E37_79B9_7F4A_7C15)
        ^ (u64::from(std::process::id()) << 32)
        | 1;
    for index in (1..items.len()).rev() {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        let pick = (state % (index as u64 + 1)) as usize;
        items.swap(index, pick);
    }
}

/// Maps intents onto MPD commands; knows nothing about audio.
pub struct Controller {
    pub client: MpdClient,
    pub cfg: Config,
    volume_before_mute: Option<i64>,
    /// Mood labels per track path: the tag file is a few tens of MB, so a
    /// lookup is one streaming pass and the answer is remembered.
    mood_cache: std::collections::HashMap<String, Vec<String>>,
}

impl Controller {
    pub fn new(client: MpdClient, cfg: Config) -> Self {
        Controller {
            client,
            cfg,
            volume_before_mute: None,
            mood_cache: std::collections::HashMap::new(),
        }
    }

    fn t(&self, key: &str, lang: &str, args: &[(&str, String)]) -> String {
        let table = phrase_table(lang);
        let template = table
            .iter()
            .find(|(name, _)| *name == key)
            .map(|(_, value)| *value)
            .or_else(|| EN.iter().find(|(name, _)| *name == key).map(|(_, v)| *v))
            .unwrap_or(key);
        format_template(template, args)
    }

    pub fn handle_text(&mut self, text: &str) -> Reply {
        let intent = intents::parse(text);
        if !intent.understood() {
            let shown = intent.raw.trim().to_string();
            return Reply::failed(self.t("unknown", &intent.lang, &[("text", shown)]));
        }
        self.execute(&intent)
    }

    /// What MPD is playing (used by `mpd-voice status`).
    pub fn now_playing(&mut self, lang: &str) -> Reply {
        let lang = if lang.is_empty() {
            self.cfg.language.clone()
        } else {
            lang.to_string()
        };
        self.now(&lang)
    }

    pub fn execute(&mut self, intent: &Intent) -> Reply {
        let result = self.dispatch(intent);
        match result {
            Ok(reply) => reply,
            Err(error) => match error {
                MpdError::Connection(_) => Reply::failed(self.t("offline", &intent.lang, &[])),
                MpdError::Ack { message, .. } => {
                    Reply::failed(self.t("error", &intent.lang, &[("message", message)]))
                }
            },
        }
    }

    fn dispatch(&mut self, intent: &Intent) -> Result<Reply, MpdError> {
        let lang = intent.lang.clone();
        match intent.name.as_str() {
            "play" => {
                self.client.play(None)?;
                Ok(Reply::ok(self.t("started", &lang, &[])))
            }
            "pause" => {
                self.client.pause(true)?;
                Ok(Reply::ok(self.t("paused", &lang, &[])))
            }
            "resume" => {
                self.client.resume()?;
                Ok(Reply::ok(self.t("resumed", &lang, &[])))
            }
            "toggle" => {
                let paused = self.client.toggle_pause()?;
                let key = if paused { "paused" } else { "resumed" };
                Ok(Reply::ok(self.t(key, &lang, &[])))
            }
            "stop" => {
                self.client.stop()?;
                Ok(Reply::ok(self.t("stopped", &lang, &[])))
            }
            "next" => {
                self.client.next()?;
                Ok(self.now(&lang))
            }
            "previous" => {
                self.client.previous()?;
                Ok(self.now(&lang))
            }
            "volume_up" => {
                let step = intent.number.unwrap_or(self.cfg.volume_step).abs();
                self.client.adjust_volume(step)?;
                Ok(self.report_volume(&lang))
            }
            "volume_down" => {
                let step = intent.number.unwrap_or(self.cfg.volume_step).abs();
                self.client.adjust_volume(-step)?;
                Ok(self.report_volume(&lang))
            }
            "volume_set" => {
                self.client.set_volume(intent.number.unwrap_or(0))?;
                Ok(self.report_volume(&lang))
            }
            "volume_get" => Ok(self.report_volume(&lang)),
            "mute" => {
                let Some(current) = self.client.volume()? else {
                    return Ok(Reply::failed(self.t("volume_unsupported", &lang, &[])));
                };
                if current != 0 {
                    self.volume_before_mute = Some(current);
                }
                self.client.set_volume(0)?;
                Ok(Reply::ok(self.t("muted", &lang, &[])))
            }
            "unmute" => {
                let value = self.volume_before_mute.unwrap_or(self.cfg.volume_step);
                self.client.set_volume(value)?;
                Ok(Reply::ok(self.t(
                    "unmuted",
                    &lang,
                    &[("value", value.to_string())],
                )))
            }
            "now_playing" => Ok(self.now(&lang)),
            "seek_forward" => {
                let seconds = intent.number.unwrap_or(10);
                self.client.seek_relative(seconds as f64)?;
                Ok(Reply::ok(self.t(
                    "seek_forward",
                    &lang,
                    &[("seconds", seconds.to_string())],
                )))
            }
            "seek_back" => {
                let seconds = intent.number.unwrap_or(10);
                self.client.seek_relative(-(seconds as f64))?;
                Ok(Reply::ok(self.t(
                    "seek_back",
                    &lang,
                    &[("seconds", seconds.to_string())],
                )))
            }
            "seek_to" => {
                let seconds = intent.number.unwrap_or(0) as f64;
                self.client.seek_to(seconds)?;
                Ok(Reply::ok(self.t(
                    "seek_to",
                    &lang,
                    &[("position", duration_to_clock(seconds))],
                )))
            }
            "shuffle_on" => {
                let enabled = self.client.set_random(true)?;
                Ok(self.mode_reply(&lang, "random", enabled))
            }
            "shuffle_off" => {
                let enabled = self.client.set_random(false)?;
                Ok(self.mode_reply(&lang, "random", enabled))
            }
            "repeat_on" => {
                let enabled = self.client.set_repeat(true)?;
                Ok(self.mode_reply(&lang, "repeat", enabled))
            }
            "repeat_off" => {
                let enabled = self.client.set_repeat(false)?;
                Ok(self.mode_reply(&lang, "repeat", enabled))
            }
            "repeat_single" => {
                self.client.set_single(true)?;
                self.client.set_repeat(true)?;
                Ok(self.mode_reply(&lang, "single", true))
            }
            "consume_toggle" => {
                let enabled = self.client.flip_mode("consume")?;
                Ok(self.mode_reply(&lang, "consume", enabled))
            }
            "play_album" => {
                let found = self.album_tracks(&intent.value)?;
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                let count = self.replace_and_play(&found)?;
                let name = found[0]
                    .get("album")
                    .filter(|album| !album.is_empty())
                    .unwrap_or(&intent.value)
                    .to_string();
                Ok(Reply::ok(self.t(
                    "playing_album",
                    &lang,
                    &[("name", name), ("count", count.to_string())],
                )))
            }
            "play_artist" => {
                let mut found = self.client.search("artist", &intent.value)?;
                if found.is_empty() {
                    found = self.client.search("albumartist", &intent.value)?;
                }
                if found.is_empty() {
                    found = self.client.search_any(&intent.value)?;
                }
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                let count = self.replace_and_play(&found)?;
                let name = found[0]
                    .get("albumartist")
                    .or_else(|| found[0].get("artist"))
                    .filter(|value| !value.is_empty())
                    .unwrap_or(&intent.value)
                    .to_string();
                Ok(Reply::ok(self.t(
                    "playing_artist",
                    &lang,
                    &[("name", name), ("count", count.to_string())],
                )))
            }
            "play_track" | "play_any" => {
                let found = self.search("title", &intent.value)?;
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                self.replace_and_play(&found)?;
                Ok(Reply::ok(self.t(
                    "playing_track",
                    &lang,
                    &[("name", describe(&found[0]))],
                )))
            }
            "play_genre" => {
                let found = self.search("genre", &intent.value)?;
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                let count = self.replace_and_play(&found)?;
                Ok(Reply::ok(self.t(
                    "playing_many",
                    &lang,
                    &[("name", intent.value.clone()), ("count", count.to_string())],
                )))
            }
            "play_directory" => {
                let found = self.search("file", &intent.value)?;
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                let count = self.replace_and_play(&found)?;
                Ok(Reply::ok(self.t(
                    "playing_many",
                    &lang,
                    &[("name", intent.value.clone()), ("count", count.to_string())],
                )))
            }
            "play_playlist" => {
                self.client.clear()?;
                self.client.load_playlist(&intent.value)?;
                self.client.play(Some(0))?;
                let tracks = self.client.queue()?;
                Ok(Reply::ok(self.t(
                    "playlist_loaded",
                    &lang,
                    &[
                        ("name", intent.value.clone()),
                        ("count", tracks.len().to_string()),
                    ],
                )))
            }
            "add_to_queue" => {
                let tag = if intent.tag.is_empty() {
                    "any".to_string()
                } else {
                    intent.tag.clone()
                };
                if tag == "playlist" {
                    let count = self.client.playlist_songs(&intent.value)?.len();
                    self.client.load_playlist(&intent.value)?;
                    return Ok(Reply::ok(self.t(
                        "playlist_loaded",
                        &lang,
                        &[("name", intent.value.clone()), ("count", count.to_string())],
                    )));
                }
                let tag = if SEARCH_TAGS.contains(&tag.as_str()) {
                    tag
                } else {
                    "any".to_string()
                };
                let found = self.search(&tag, &intent.value)?;
                if found.is_empty() {
                    return Ok(self.not_found(&lang, &intent.value));
                }
                let uris: Vec<String> = found
                    .iter()
                    .filter_map(|song| song.get("file").map(str::to_string))
                    .collect();
                let added = self.client.add_many(&uris)?;
                Ok(Reply::ok(self.t(
                    "added",
                    &lang,
                    &[("count", added.to_string())],
                )))
            }
            "queue_similar" => Ok(self.queue_similar(&lang)),
            "describe_track" => Ok(self.describe_track(&lang)),
            "play_mood" => Ok(self.play_mood(&lang, &intent.value)),
            "clear_queue" => {
                self.client.clear()?;
                Ok(Reply::ok(self.t("queue_cleared", &lang, &[])))
            }
            "list_playlists" => {
                let names = self.client.playlists()?;
                if names.is_empty() {
                    return Ok(Reply::ok(self.t("playlists_empty", &lang, &[])));
                }
                Ok(Reply::ok(self.t(
                    "playlists",
                    &lang,
                    &[("names", names.join(", "))],
                )))
            }
            "save_playlist" => {
                self.client.save_playlist(&intent.value)?;
                Ok(Reply::ok(self.t(
                    "playlist_saved",
                    &lang,
                    &[("name", intent.value.clone())],
                )))
            }
            "update_library" => {
                self.client.update("")?;
                Ok(Reply::ok(self.t("updating", &lang, &[])))
            }
            "help" => Ok(Reply::ok(self.t("help", &lang, &[]))),
            "exit" => Ok(Reply {
                text: self.t("bye", &lang, &[]),
                ok: true,
                should_exit: true,
            }),
            _ => Ok(Reply::failed(self.t(
                "unknown",
                &lang,
                &[("text", intent.raw.clone())],
            ))),
        }
    }

    fn mode_reply(&self, lang: &str, mode: &str, enabled: bool) -> Reply {
        let name = mode_names(lang)
            .iter()
            .find(|(key, _)| *key == mode)
            .map(|(_, value)| (*value).to_string())
            .unwrap_or_else(|| mode.to_string());
        let key = if enabled { "mode_on" } else { "mode_off" };
        Reply::ok(self.t(key, lang, &[("what", name)]))
    }

    fn not_found(&self, lang: &str, name: &str) -> Reply {
        Reply::failed(self.t("not_found", lang, &[("name", name.to_string())]))
    }

    fn report_volume(&mut self, lang: &str) -> Reply {
        match self.client.volume() {
            Ok(Some(value)) => Reply::ok(self.t("volume", lang, &[("value", value.to_string())])),
            Ok(None) => Reply::failed(self.t("volume_unsupported", lang, &[])),
            Err(_) => Reply::failed(self.t("volume_unsupported", lang, &[])),
        }
    }

    fn now(&mut self, lang: &str) -> Reply {
        let song = match self.client.current_song() {
            Ok(song) => song,
            Err(error) => return self.error_reply(lang, error),
        };
        if song.get("file").is_none_or(str::is_empty) {
            return Reply::ok(self.t("nothing", lang, &[]));
        }
        let state = self
            .client
            .status()
            .map(|status| status.get("state").unwrap_or("").to_string())
            .unwrap_or_default();
        let what = describe(&song);
        let mut text = if state == "pause" {
            self.t("paused_state", lang, &[("what", what)])
        } else {
            what
        };
        let file = song.get("file").unwrap_or("").to_string();
        let moods = self.track_moods(&file, 3);
        if !moods.is_empty() {
            text = self.t(
                "now_moods",
                lang,
                &[("what", text), ("moods", moods.join(", "))],
            );
        }
        Reply::ok(text)
    }

    fn error_reply(&self, lang: &str, error: MpdError) -> Reply {
        match error {
            MpdError::Connection(_) => Reply::failed(self.t("offline", lang, &[])),
            MpdError::Ack { message, .. } => {
                Reply::failed(self.t("error", lang, &[("message", message)]))
            }
        }
    }

    /// Search by tag, falling back to `any` (paths, mixed spellings).
    fn search(&mut self, tag: &str, query: &str) -> Result<Vec<Meta>, MpdError> {
        if query.is_empty() {
            return Ok(Vec::new());
        }
        if SEARCH_TAGS.contains(&tag) {
            let found = self.client.search(tag, query)?;
            if !found.is_empty() {
                return Ok(found);
            }
        }
        self.client.search_any(query)
    }

    fn album_tracks(&mut self, query: &str) -> Result<Vec<Meta>, MpdError> {
        let found = self.client.search("album", query)?;
        if !found.is_empty() {
            return Ok(found);
        }
        let loose = self.client.search_any(query)?;
        let Some(first) = loose.first() else {
            return Ok(Vec::new());
        };
        if let Some(album) = first.get("album").filter(|album| !album.is_empty()) {
            let tracks = self.client.search("album", album)?;
            if !tracks.is_empty() {
                return Ok(tracks);
            }
        }
        Ok(loose.into_iter().take(1).collect())
    }

    fn replace_and_play(&mut self, songs: &[Meta]) -> Result<usize, MpdError> {
        self.client.clear()?;
        let uris: Vec<String> = songs
            .iter()
            .filter_map(|song| song.get("file").map(str::to_string))
            .collect();
        self.client.add_many(&uris)?;
        self.client.play(Some(0))?;
        Ok(songs.len())
    }

    /// Mood labels of one MPD track from the tag file (empty when unknown).
    ///
    /// The file holds absolute paths while MPD reports paths relative to
    /// `music_directory`, so both spellings are compared. Records without the
    /// moods (or a score below `tags_min_score`) are ignored, and the answer is
    /// cached per path: a repeat question costs nothing.
    pub fn track_moods(&mut self, file_uri: &str, limit: usize) -> Vec<String> {
        if file_uri.is_empty() || self.cfg.tags_file.is_empty() || self.cfg.music_dir.is_empty() {
            return Vec::new();
        }
        let music_dir = expand_user(&self.cfg.music_dir);
        let absolute = music_dir.join(file_uri);
        let key = absolute.display().to_string();
        if let Some(cached) = self.mood_cache.get(&key) {
            return cached.clone();
        }
        let tags_file = expand_user(&self.cfg.tags_file);
        let mut labels: Vec<String> = Vec::new();
        if tags_file.is_file() {
            let mut wanted = vec![key.clone()];
            if let Ok(real) = std::fs::canonicalize(&absolute) {
                wanted.push(real.display().to_string());
            }
            if let Ok(text) = std::fs::read_to_string(&tags_file) {
                for line in text.lines() {
                    if line.trim().is_empty() {
                        continue;
                    }
                    let Some(record) = crate::json::parse(line) else {
                        continue;
                    };
                    let path = record.get("path").and_then(Value::as_str).unwrap_or("");
                    if path.is_empty() || !wanted.iter().any(|want| want == path) {
                        continue;
                    }
                    let moods = record
                        .get("tags")
                        .and_then(|tags| tags.get("mood"))
                        .and_then(Value::as_array)
                        .unwrap_or(&[]);
                    for item in moods {
                        if !item.is_object() {
                            continue;
                        }
                        let score = item.get("score").and_then(Value::as_f64).unwrap_or(0.0);
                        if score < self.cfg.tags_min_score {
                            continue;
                        }
                        if let Some(label) = item.get("label").and_then(Value::as_str) {
                            if !labels.iter().any(|have| have == label) {
                                labels.push(label.to_string());
                            }
                            if labels.len() >= limit {
                                break;
                            }
                        }
                    }
                    break;
                }
            }
        }
        self.mood_cache.insert(key, labels.clone());
        labels
    }

    fn queue_similar(&mut self, lang: &str) -> Reply {
        let music_dir = self.music_dir_or_fail(lang, "similar_no_dir");
        let Ok(music_dir) = music_dir else {
            return music_dir.unwrap_err();
        };
        let song = match self.client.current_song() {
            Ok(song) => song,
            Err(error) => return self.error_reply(lang, error),
        };
        let Some(file) = song.get("file").filter(|file| !file.is_empty()) else {
            return Reply::failed(self.t("similar_nothing", lang, &[]));
        };
        let query = music_dir.join(file);
        if !query.is_file() {
            return Reply::failed(self.t("similar_missing", lang, &[]));
        }
        let argv = crate::audio::shlex_split(&self.cfg.similar_cmd);
        if argv.is_empty() {
            return Reply::failed(self.t("similar_failed", lang, &[]));
        }
        let output = run_helper(&argv, &query, std::time::Duration::from_secs(120));
        let Some(stdout) = output else {
            return Reply::failed(self.t("similar_failed", lang, &[]));
        };
        let Some(document) = crate::json::parse(&stdout) else {
            return Reply::failed(self.t("similar_failed", lang, &[]));
        };
        let mut uris: Vec<String> = Vec::new();
        for item in document
            .get("results")
            .and_then(Value::as_array)
            .unwrap_or(&[])
        {
            let Some(path) = item.get("path").and_then(Value::as_str) else {
                continue;
            };
            if path.is_empty() {
                continue;
            }
            if let Some(relative) = relative_uri(path, &music_dir) {
                uris.push(relative);
            }
        }
        if uris.is_empty() {
            return Reply::failed(self.t("similar_empty", lang, &[]));
        }
        match self.client.add_many(&uris) {
            Ok(added) => Reply::ok(self.t("similar_added", lang, &[("count", added.to_string())])),
            Err(error) => self.error_reply(lang, error),
        }
    }

    fn describe_track(&mut self, lang: &str) -> Reply {
        let music_dir = match self.music_dir_or_fail(lang, "similar_no_dir") {
            Ok(dir) => dir,
            Err(reply) => return reply,
        };
        let song = match self.client.current_song() {
            Ok(song) => song,
            Err(error) => return self.error_reply(lang, error),
        };
        let Some(file) = song.get("file").filter(|file| !file.is_empty()) else {
            return Reply::failed(self.t("similar_nothing", lang, &[]));
        };
        let query = music_dir.join(file);
        if !query.is_file() {
            return Reply::failed(self.t("similar_missing", lang, &[]));
        }
        let argv: Vec<String> = crate::audio::shlex_split(&self.cfg.describe_cmd)
            .into_iter()
            .map(|part| expand_user(&part).display().to_string())
            .collect();
        if argv.is_empty() {
            return Reply::failed(self.t("describe_failed", lang, &[]));
        }
        let timeout = std::time::Duration::from_secs_f64(self.cfg.describe_timeout.max(0.0));
        let Some(stdout) = run_helper(&argv, &query, timeout) else {
            return Reply::failed(self.t("describe_failed", lang, &[]));
        };
        for line in stdout.lines().rev() {
            let Some(payload) = crate::json::parse(line) else {
                continue;
            };
            if let Some(text) = payload.get("text").and_then(Value::as_str) {
                let prose = text.trim();
                if !prose.is_empty() {
                    return Reply::ok(prose.to_string());
                }
            }
            break;
        }
        Reply::failed(self.t("describe_failed", lang, &[]))
    }

    fn music_dir_or_fail(&self, lang: &str, key: &str) -> Result<PathBuf, Reply> {
        if self.cfg.music_dir.is_empty() {
            return Err(Reply::failed(self.t(key, lang, &[])));
        }
        let music_dir = expand_user(&self.cfg.music_dir);
        if !music_dir.is_dir() {
            return Err(Reply::failed(self.t(key, lang, &[])));
        }
        Ok(music_dir)
    }

    fn play_mood(&mut self, lang: &str, mood: &str) -> Reply {
        if mood.is_empty() {
            return Reply::failed(self.t("mood_empty", lang, &[("mood", mood.to_string())]));
        }
        let music_dir = match self.music_dir_or_fail(lang, "mood_no_dir") {
            Ok(dir) => dir,
            Err(reply) => return reply,
        };
        let tags_file = expand_user(&self.cfg.tags_file);
        if !tags_file.is_file() {
            return Reply::failed(self.t(
                "mood_missing",
                lang,
                &[("path", tags_file.display().to_string())],
            ));
        }
        let excludes: Vec<String> = self
            .cfg
            .tags_exclude
            .split(',')
            .map(str::trim)
            .filter(|pattern| !pattern.is_empty())
            .map(str::to_string)
            .collect();
        let Ok(text) = std::fs::read_to_string(&tags_file) else {
            return Reply::failed(self.t("mood_failed", lang, &[]));
        };
        let mut matches: Vec<String> = Vec::new();
        let mut lines = 0usize;
        let mut broken = 0usize;
        for line in text.lines() {
            if line.trim().is_empty() {
                continue;
            }
            lines += 1;
            let Some(entry) = crate::json::parse(line) else {
                broken += 1;
                continue;
            };
            if !entry.is_object() {
                broken += 1;
                continue;
            }
            if self.mood_too_short(&entry) {
                continue;
            }
            let Some(path) = self.mood_path(&entry, mood) else {
                continue;
            };
            let Some(uri) = relative_uri(&path, &music_dir) else {
                continue;
            };
            if excludes.iter().any(|pattern| glob_match(pattern, &uri)) {
                continue;
            }
            matches.push(uri);
        }
        if matches.is_empty() {
            if lines > 0 && broken == lines {
                return Reply::failed(self.t(
                    "mood_broken",
                    lang,
                    &[("count", broken.to_string())],
                ));
            }
            return Reply::failed(self.t("mood_empty", lang, &[("mood", mood.to_string())]));
        }
        let mut pool: Vec<String> = Vec::new();
        for uri in matches {
            if !pool.contains(&uri) {
                pool.push(uri);
            }
        }
        shuffle(&mut pool);
        if self.cfg.tags_limit > 0 {
            pool.truncate(self.cfg.tags_limit as usize);
        }
        match self.client.add_many(&pool) {
            Ok(added) => Reply::ok(self.t(
                "mood_added",
                lang,
                &[("count", added.to_string()), ("mood", mood.to_string())],
            )),
            Err(error) => self.error_reply(lang, error),
        }
    }

    /// Path of an entry whose mood label clears the score floor.
    fn mood_path(&self, entry: &Value, mood: &str) -> Option<String> {
        let path = entry.get("path").and_then(Value::as_str)?;
        if path.is_empty() {
            return None;
        }
        let moods = entry
            .get("tags")
            .and_then(|tags| tags.get("mood"))
            .and_then(Value::as_array)?;
        for item in moods {
            if item.get("label").and_then(Value::as_str) != Some(mood) {
                continue;
            }
            let score = item.get("score").and_then(Value::as_f64).unwrap_or(0.0);
            if score >= self.cfg.tags_min_score {
                return Some(path.to_string());
            }
        }
        None
    }

    /// True when the tagger measured a clip below `tags_min_seconds`.
    ///
    /// `audio_seconds` was added to the tagger after the first tag files were
    /// written, so an absent field cannot be judged and must not drop the
    /// track; the same goes for a value that is not a number.
    fn mood_too_short(&self, entry: &Value) -> bool {
        let Some(raw) = entry.get("audio_seconds") else {
            return false;
        };
        let Some(seconds) = raw.as_f64() else {
            return false;
        };
        seconds < self.cfg.tags_min_seconds
    }
}

fn run_helper(argv: &[String], argument: &Path, timeout: std::time::Duration) -> Option<String> {
    let mut child = std::process::Command::new(&argv[0])
        .args(&argv[1..])
        .arg(argument)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let output = child.wait_with_output().ok()?;
                if !status.success() {
                    return None;
                }
                return Some(String::from_utf8_lossy(&output.stdout).to_string());
            }
            Ok(None) if std::time::Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            Ok(None) => std::thread::sleep(std::time::Duration::from_millis(20)),
            Err(_) => return None,
        }
    }
}

/// Absolute tag-file path -> MPD URI, or `None` when outside `music_dir`.
pub fn relative_uri(path: &str, music_dir: &Path) -> Option<String> {
    let path = Path::new(path);
    if !path.is_absolute() {
        return None;
    }
    let relative = path.strip_prefix(music_dir).ok()?;
    let text = relative.display().to_string();
    if text.is_empty() || text == "." || text == ".." || text.starts_with("../") {
        return None;
    }
    Some(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mpd::MpdClient;
    use crate::testing::{FakeMpd, StubSong};
    use std::time::Duration;

    fn library() -> Vec<StubSong> {
        vec![
            StubSong::new(
                "Agalloch/The Mantle/01 - Falling Snow.flac",
                "Falling Snow",
                "Agalloch",
                "The Mantle",
            )
            .genre("doom metal"),
            StubSong::new(
                "Agalloch/The Mantle/02 - Not Unlike the Waves.flac",
                "Not Unlike the Waves",
                "Agalloch",
                "The Mantle",
            )
            .genre("doom metal"),
            StubSong::new(
                "Evoken/Antithesis of Light/01 - Quietus.flac",
                "Quietus",
                "Evoken",
                "Antithesis of Light",
            )
            .genre("funeral doom"),
        ]
    }

    struct Fixture {
        fake: FakeMpd,
        controller: Controller,
    }

    impl Fixture {
        fn new() -> Self {
            let fake = FakeMpd::start();
            fake.library(library());
            let client = MpdClient::new("127.0.0.1", fake.port, None, Duration::from_secs(5));
            let mut cfg = Config::default();
            cfg.language = "ru".to_string();
            Fixture {
                fake,
                controller: Controller::new(client, cfg),
            }
        }

        fn with_config(cfg: Config) -> Self {
            let fake = FakeMpd::start();
            fake.library(library());
            let client = MpdClient::new("127.0.0.1", fake.port, None, Duration::from_secs(5));
            Fixture {
                fake,
                controller: Controller::new(client, cfg),
            }
        }

        fn say(&mut self, phrase: &str) -> Reply {
            self.controller.handle_text(phrase)
        }
    }

    #[test]
    fn play_album_replaces_the_queue() {
        let mut f = Fixture::new();
        let reply = f.say("включи альбом The Mantle");
        assert!(reply.ok, "{}", reply.text);
        assert_eq!(f.fake.queue().len(), 2);
        assert_eq!(f.fake.state(), "play");
        assert_eq!(f.fake.position(), 0);
        assert!(reply.text.contains("The Mantle"), "{}", reply.text);
    }

    #[test]
    fn play_artist_genre_track_and_folder() {
        let mut f = Fixture::new();
        assert!(f.say("включи исполнителя Evoken").ok);
        assert_eq!(f.fake.queue().len(), 1);

        assert!(f.say("включи жанр funeral doom").ok);
        assert_eq!(f.fake.queue().len(), 1);
        assert!(f.fake.queue()[0].contains("Quietus"));

        assert!(f.say("включи трек Falling Snow").ok);
        assert_eq!(f.fake.queue().len(), 1);

        assert!(f.say("включи папку Agalloch").ok);
        assert_eq!(f.fake.queue().len(), 2);
    }

    #[test]
    fn add_to_queue_appends_without_restarting() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        let before = f.fake.queue().len();
        assert!(f.say("добавь в очередь Evoken").ok);
        assert_eq!(f.fake.queue().len(), before + 1);
        assert_eq!(f.fake.state(), "play");
    }

    #[test]
    fn unknown_library_item_leaves_the_queue_alone() {
        let mut f = Fixture::new();
        let reply = f.say("включи альбом Nonexistent Album");
        assert!(!reply.ok);
        assert!(reply.text.contains("Не нашёл"), "{}", reply.text);
        assert!(f.fake.queue().is_empty());
    }

    #[test]
    fn transport_chain() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("пауза").ok);
        assert_eq!(f.fake.state(), "pause");
        assert!(f.say("продолжи").ok);
        assert_eq!(f.fake.state(), "play");
        assert!(f.say("следующий трек").ok);
        assert_eq!(f.fake.position(), 1);
        assert!(f.say("предыдущий").ok);
        assert_eq!(f.fake.position(), 0);
        assert!(f.say("стоп").ok);
        assert_eq!(f.fake.state(), "stop");
    }

    #[test]
    fn now_playing_mentions_track_and_album() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        let reply = f.say("что играет");
        assert!(reply.ok);
        assert!(reply.text.contains("Falling Snow"), "{}", reply.text);
        assert!(reply.text.contains("The Mantle"), "{}", reply.text);
    }

    #[test]
    fn now_playing_when_paused_and_when_empty() {
        let mut f = Fixture::new();
        let reply = f.say("что играет");
        assert_eq!(reply.text, "Сейчас ничего не играет.");
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("пауза").ok);
        let reply = f.say("что играет");
        assert!(reply.text.starts_with("На паузе: "), "{}", reply.text);
    }

    #[test]
    fn volume_steps_clamping_and_absolute_values() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("громкость на 50").ok);
        assert_eq!(f.fake.volume(), 50);
        assert!(f.say("громче на 30").ok);
        assert_eq!(f.fake.volume(), 80);
        assert!(f.say("тише на 20").ok);
        assert_eq!(f.fake.volume(), 60);
        assert!(f.say("громкость на 500").ok);
        assert_eq!(f.fake.volume(), 100);
        assert!(f.say("volume 0").ok);
        assert_eq!(f.fake.volume(), 0);
    }

    #[test]
    fn mute_and_unmute_restore_the_level() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("громкость на 35").ok);
        assert!(f.say("выключи звук").ok);
        assert_eq!(f.fake.volume(), 0);
        let reply = f.say("верни звук");
        assert_eq!(f.fake.volume(), 35);
        assert!(reply.text.contains("35"), "{}", reply.text);
    }

    #[test]
    fn volume_without_a_mixer_is_reported() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        f.fake.set_no_mixer();
        let reply = f.say("какая громкость");
        assert!(!reply.ok);
        assert!(reply.text.contains("не поддерживает"), "{}", reply.text);
    }

    #[test]
    fn modes_toggle_on_the_daemon() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("перемешай").ok);
        assert_eq!(f.fake.mode("random"), 1);
        assert!(f.say("выключи шаффл").ok);
        assert_eq!(f.fake.mode("random"), 0);
        assert!(f.say("повторяй").ok);
        assert_eq!(f.fake.mode("repeat"), 1);
        assert!(f.say("не повторяй").ok);
        assert_eq!(f.fake.mode("repeat"), 0);
        assert!(f.say("повторяй один трек").ok);
        assert_eq!(f.fake.mode("single"), 1);
        assert_eq!(f.fake.mode("repeat"), 1);
        assert!(f.say("включи consume").ok);
        assert_eq!(f.fake.mode("consume"), 1);
    }

    #[test]
    fn seek_translates_to_seconds() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("перемотай вперёд на 30 секунд").ok);
        assert!(f.say("отмотай назад на минуту").ok);
        assert!(f.say("перемотай на 1:30").ok);
        let seeks: Vec<String> = f
            .fake
            .commands()
            .into_iter()
            .filter(|command| command.starts_with("seekcur"))
            .collect();
        assert_eq!(seeks, vec!["seekcur +30", "seekcur -60", "seekcur 90"]);
    }

    #[test]
    fn clear_queue_and_playlists() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("очисти очередь").ok);
        assert!(f.fake.queue().is_empty());

        assert!(f.say("включи альбом The Mantle").ok);
        assert!(f.say("сохрани плейлист evening").ok);
        assert_eq!(f.fake.playlists().len(), 1);
        let reply = f.say("покажи плейлисты");
        assert!(reply.text.contains("evening"), "{}", reply.text);
        assert!(f.say("очисти очередь").ok);
        assert!(f.say("включи плейлист evening").ok);
        assert_eq!(f.fake.state(), "play");
        assert_eq!(f.fake.queue().len(), 2);
    }

    #[test]
    fn missing_playlist_reports_an_mpd_error() {
        let mut f = Fixture::new();
        let reply = f.say("включи плейлист nope");
        assert!(!reply.ok);
        assert!(reply.text.contains("MPD"), "{}", reply.text);
    }

    #[test]
    fn empty_playlist_list_and_update() {
        let mut f = Fixture::new();
        let reply = f.say("покажи плейлисты");
        assert!(reply.ok);
        assert_eq!(reply.text, "Плейлистов нет.");
        assert!(f.say("обнови библиотеку").ok);
        assert_eq!(f.fake.updated(), vec![String::new()]);
    }

    #[test]
    fn unknown_command_leaves_mpd_alone() {
        let mut f = Fixture::new();
        let before = f.fake.commands();
        let reply = f.say("расскажи анекдот");
        assert!(!reply.ok);
        assert!(reply.text.contains("Не понял"), "{}", reply.text);
        assert_eq!(f.fake.commands(), before);
    }

    #[test]
    fn reply_language_follows_the_phrase() {
        let mut f = Fixture::new();
        assert!(f.say("включи альбом The Mantle").ok);
        let reply = f.say("volume 30");
        assert!(reply.text.contains("Volume"), "{}", reply.text);
    }

    #[test]
    fn offline_daemon_is_reported() {
        let mut cfg = Config::default();
        cfg.language = "ru".to_string();
        let client = MpdClient::new("127.0.0.1", 1, None, Duration::from_millis(500));
        let mut controller = Controller::new(client, cfg);
        let reply = controller.handle_text("что играет");
        assert!(!reply.ok);
        assert!(reply.text.contains("MPD"), "{}", reply.text);
    }

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "mpd-voice-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|delta| delta.as_nanos())
                .unwrap_or(0)
        ));
        std::fs::create_dir_all(&dir).expect("temp dir");
        dir
    }

    fn write_script(dir: &Path, name: &str, body: &str) -> String {
        let path = dir.join(name);
        std::fs::write(&path, format!("#!/bin/sh\n{body}\n")).expect("script");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&path).expect("stat").permissions().mode();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(mode | 0o111))
                .expect("chmod");
        }
        path.display().to_string()
    }

    #[test]
    fn queue_similar_appends_the_helpers_neighbours() {
        let dir = temp_dir("similar");
        let music = dir.join("music");
        let current = music.join("Agalloch/The Mantle/01 - Falling Snow.flac");
        std::fs::create_dir_all(current.parent().unwrap()).unwrap();
        std::fs::write(&current, b"").unwrap();
        let library_file = music.join("Agalloch/The Mantle/02 - Not Unlike the Waves.flac");
        std::fs::create_dir_all(library_file.parent().unwrap()).unwrap();
        std::fs::write(&library_file, b"").unwrap();
        let neighbour = music.join("Evoken/Antithesis of Light/01 - Quietus.flac");
        let body = format!(
            "cat <<EOF\n{{\"results\": [{{\"path\": \"{}\"}}, {{\"path\": \"{}\"}}]}}\nEOF",
            current.display(),
            neighbour.display()
        );
        let script = write_script(&dir, "music-similar", &body);

        let mut cfg = Config::default();
        cfg.language = "ru".to_string();
        cfg.music_dir = music.display().to_string();
        cfg.similar_cmd = format!("{script} --json");
        let mut f = Fixture::with_config(cfg);
        f.fake.library(vec![
            StubSong::new(
                "Agalloch/The Mantle/01 - Falling Snow.flac",
                "Falling Snow",
                "Agalloch",
                "The Mantle",
            ),
            StubSong::new(
                "Evoken/Antithesis of Light/01 - Quietus.flac",
                "Quietus",
                "Evoken",
                "Antithesis of Light",
            ),
        ]);
        assert!(f.say("включи альбом The Mantle").ok);
        let before = f.fake.queue().len();
        let reply = f.say("включи похожие");
        assert!(reply.ok, "{}", reply.text);
        assert_eq!(f.fake.queue().len(), before + 2);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn queue_similar_failures_are_reported() {
        let dir = temp_dir("similar-fail");
        let music = dir.join("music");
        let current = music.join("a/b.flac");
        std::fs::create_dir_all(current.parent().unwrap()).unwrap();
        std::fs::write(&current, b"").unwrap();

        // Broken JSON, a non-zero exit and an empty result set must all fail
        // without touching the queue.
        for (name, body, expect_queue_growth) in [
            ("bad", "echo 'not json'".to_string(), false),
            ("fail", "exit 3".to_string(), false),
            ("empty", "echo '{\"results\": []}'".to_string(), false),
        ] {
            let script = write_script(&dir, name, &body);
            let mut cfg = Config::default();
            cfg.language = "ru".to_string();
            cfg.music_dir = music.display().to_string();
            cfg.similar_cmd = script;
            let mut f = Fixture::with_config(cfg);
            assert!(f.say("включи альбом The Mantle").ok);
            let before = f.fake.queue().len();
            let reply = f.say("похожие");
            assert!(!reply.ok, "{name}: {}", reply.text);
            assert_eq!(
                f.fake.queue().len() - before,
                usize::from(expect_queue_growth),
                "{name}"
            );
        }
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn describe_track_uses_the_helpers_last_json_line() {
        let dir = temp_dir("describe");
        let music = dir.join("music");
        let current = music.join("a/b.flac");
        std::fs::create_dir_all(current.parent().unwrap()).unwrap();
        std::fs::write(&current, b"").unwrap();
        let library_file = music.join("Agalloch/The Mantle/01 - Falling Snow.flac");
        std::fs::create_dir_all(library_file.parent().unwrap()).unwrap();
        std::fs::write(&library_file, b"").unwrap();
        let body = "echo 'loading'; echo '{\"text\": \"Doom metal with slow riffs.\"}'";
        let script = write_script(&dir, "music-describe", body);

        let mut cfg = Config::default();
        cfg.language = "ru".to_string();
        cfg.music_dir = music.display().to_string();
        cfg.describe_cmd = script;
        let mut f = Fixture::with_config(cfg);
        assert!(f.say("включи альбом The Mantle").ok);
        let reply = f.say("опиши этот трек");
        assert!(reply.ok, "{}", reply.text);
        assert_eq!(reply.text, "Doom metal with slow riffs.");
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn play_mood_queues_tagged_tracks() {
        let dir = temp_dir("mood");
        let music = dir.join("music");
        for file in ["a/dark.flac", "a/sad.flac", "a/sample.flac"] {
            let path = music.join(file);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, b"").unwrap();
        }
        let tags = dir.join("tags.jsonl");
        let records = [
            format!(
                "{{\"path\": \"{}\", \"audio_seconds\": 200, \"tags\": {{\"mood\": [{{\"label\": \"dark\", \"score\": 0.31}}]}}}}",
                music.join("a/dark.flac").display()
            ),
            format!(
                "{{\"path\": \"{}\", \"audio_seconds\": 200, \"tags\": {{\"mood\": [{{\"label\": \"sad\", \"score\": 0.3}}]}}}}",
                music.join("a/sad.flac").display()
            ),
            // Below the score floor, and a two-second sample under the length
            // floor, which the exclude glob also covers.
            format!(
                "{{\"path\": \"{}\", \"audio_seconds\": 200, \"tags\": {{\"mood\": [{{\"label\": \"dark\", \"score\": 0.02}}]}}}}",
                music.join("a/sad.flac").display()
            ),
            format!(
                "{{\"path\": \"{}\", \"audio_seconds\": 2, \"tags\": {{\"mood\": [{{\"label\": \"dark\", \"score\": 0.9}}]}}}}",
                music.join("a/sample.flac").display()
            ),
            "not json".to_string(),
        ];
        std::fs::write(&tags, records.join("\n")).unwrap();

        let mut cfg = Config::default();
        cfg.language = "ru".to_string();
        cfg.music_dir = music.display().to_string();
        cfg.tags_file = tags.display().to_string();
        let mut f = Fixture::with_config(cfg);
        f.fake.library(vec![
            StubSong::new("a/dark.flac", "dark", "A", "A"),
            StubSong::new("a/sad.flac", "sad", "A", "A"),
            StubSong::new("a/sample.flac", "sample", "A", "A"),
        ]);
        let reply = f.say("включи мрачное");
        assert!(reply.ok, "{}", reply.text);
        assert_eq!(f.fake.queue(), vec!["a/dark.flac".to_string()]);

        let reply = f.say("включи грустное");
        assert!(reply.ok, "{}", reply.text);
        assert_eq!(
            f.fake.queue(),
            vec!["a/dark.flac".to_string(), "a/sad.flac".to_string()]
        );
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn play_mood_without_a_tag_file_says_how_to_build_it() {
        let mut cfg = Config::default();
        cfg.language = "ru".to_string();
        cfg.music_dir = "/tmp".to_string();
        cfg.tags_file = "/nonexistent/tags.jsonl".to_string();
        let mut f = Fixture::with_config(cfg);
        f.fake.library(vec![
            StubSong::new("a/dark.flac", "dark", "A", "A"),
            StubSong::new("a/sad.flac", "sad", "A", "A"),
            StubSong::new("a/sample.flac", "sample", "A", "A"),
        ]);
        let reply = f.say("включи мрачное");
        assert!(!reply.ok);
        assert!(reply.text.contains("music-mtg-tags"), "{}", reply.text);
    }

    #[test]
    fn help_and_exit_do_not_touch_mpd() {
        let mut f = Fixture::new();
        assert!(f.say("помощь").ok);
        let reply = f.say("хватит слушать");
        assert!(reply.should_exit);
        assert!(f.fake.commands().is_empty());
    }
}
