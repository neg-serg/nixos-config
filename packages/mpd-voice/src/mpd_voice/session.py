"""Execute recognised intents against MPD and phrase the spoken reply."""

from __future__ import annotations

import fnmatch
import json
import os
import random
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .config import Config
from .intents import Intent, parse
from .mpd import (
    MPDClient,
    MPDConnectionError,
    MPDError,
    SEARCH_TAGS,
)

RU = {
    "nothing": "Сейчас ничего не играет.",
    "now_moods": "{what} ({moods})",
    "paused_state": "На паузе: {what}.",
    "stopped_state": "Воспроизведение остановлено.",
    "started": "Играю.",
    "paused": "Пауза.",
    "resumed": "Продолжаю.",
    "stopped": "Остановил.",
    "volume": "Громкость {value} процентов.",
    "volume_unsupported": "Устройство не поддерживает регулировку громкости.",
    "muted": "Звук выключен.",
    "unmuted": "Вернул громкость {value} процентов.",
    "seek_forward": "Перемотал вперёд на {seconds} секунд.",
    "seek_back": "Перемотал назад на {seconds} секунд.",
    "seek_to": "Перемотал на {position}.",
    "playing_album": "Играю альбом {name}, треков: {count}.",
    "playing_artist": "Играю {name}, треков: {count}.",
    "playing_track": "Играю {name}.",
    "playing_many": "Играю {count} треков по запросу {name}.",
    "not_found": "Не нашёл: {name}.",
    "added": "Добавил в очередь треков: {count}.",
    "similar_added": "Добавил в очередь похожих треков: {count}.",
    "similar_empty": "Похожих треков не нашлось.",
    "similar_nothing": "Сейчас ничего не играет.",
    "similar_no_dir": "Каталог музыки не задан или не существует.",
    "similar_missing": "Не нашёл файл текущего трека в каталоге музыки.",
    "similar_failed": "Помощник по похожим трекам не сработал.",
    "mood_added": "Добавил {count} треков в настроении {mood}.",
    "mood_empty": "Не нашёл треков в настроении {mood}.",
    "mood_no_dir": "Каталог музыки не задан или не существует.",
    "mood_missing": "Файл тегов настроений не найден: {path}. "
    "Соберите его командой: music-mtg-tags --dir ~/music --out {path} --json",
    "mood_broken": "Не смог прочитать файл тегов: все {count} строк "
    "повреждены.",
    "mood_failed": "Не смог прочитать файл тегов настроений.",
    "queue_cleared": "Очередь очищена.",
    "playlists": "Плейлисты: {names}.",
    "playlists_empty": "Плейлистов нет.",
    "playlist_loaded": "Загрузил плейлист {name}, треков: {count}.",
    "playlist_saved": "Сохранил очередь как плейлист {name}.",
    "mode_on": "{what} включено.",
    "mode_off": "{what} выключено.",
    "crossfade": "Кроссфейд {value} секунд.",
    "updating": "Обновляю библиотеку.",
    "help": "Скажите: громче, тише, следующий, пауза, продолжи, "
    "что играет, включи альбом или исполнителя.",
    "bye": "Выключаюсь.",
    "unknown": "Не понял: {text}.",
    "error": "MPD вернул ошибку: {message}.",
    "offline": "Нет связи с MPD.",
}

EN = {
    "nothing": "Nothing is playing right now.",
    "now_moods": "{what} ({moods})",
    "paused_state": "Paused: {what}.",
    "stopped_state": "Playback is stopped.",
    "started": "Playing.",
    "paused": "Paused.",
    "resumed": "Resuming.",
    "stopped": "Stopped.",
    "volume": "Volume {value} percent.",
    "volume_unsupported": "This output does not support volume control.",
    "muted": "Muted.",
    "unmuted": "Volume back to {value} percent.",
    "seek_forward": "Skipped forward {seconds} seconds.",
    "seek_back": "Skipped back {seconds} seconds.",
    "seek_to": "Jumped to {position}.",
    "playing_album": "Playing album {name}, {count} tracks.",
    "playing_artist": "Playing {name}, {count} tracks.",
    "playing_track": "Playing {name}.",
    "playing_many": "Playing {count} tracks matching {name}.",
    "not_found": "Nothing found for: {name}.",
    "added": "Added {count} tracks to the queue.",
    "similar_added": "Added {count} similar tracks to the queue.",
    "similar_empty": "No similar tracks found.",
    "similar_nothing": "Nothing is playing right now.",
    "similar_no_dir": "The music directory is not set or does not exist.",
    "similar_missing": "The current track is not under the music directory.",
    "similar_failed": "The similarity helper failed.",
    "mood_added": "Added {count} {mood} tracks to the queue.",
    "mood_empty": "No tracks found with mood {mood}.",
    "mood_no_dir": "The music directory is not set or does not exist.",
    "mood_missing": "Mood tag file not found: {path}. Build it with: "
    "music-mtg-tags --dir ~/music --out {path} --json",
    "mood_broken": "Could not read the tag file: all {count} lines are "
    "broken.",
    "mood_failed": "Could not read the mood tag file.",
    "queue_cleared": "Queue cleared.",
    "playlists": "Playlists: {names}.",
    "playlists_empty": "There are no playlists.",
    "playlist_loaded": "Loaded playlist {name}, {count} tracks.",
    "playlist_saved": "Saved the queue as playlist {name}.",
    "mode_on": "{what} on.",
    "mode_off": "{what} off.",
    "crossfade": "Crossfade {value} seconds.",
    "updating": "Updating the library.",
    "help": "Try: louder, quieter, next, pause, resume, what is playing, "
    "play album or artist.",
    "bye": "Shutting down.",
    "unknown": "I did not understand: {text}.",
    "error": "MPD reported an error: {message}.",
    "offline": "MPD is unreachable.",
}

PHRASES = {"ru": RU, "en": EN}
MODE_NAMES = {
    "ru": {
        "random": "Перемешивание",
        "repeat": "Повтор",
        "single": "Повтор одного трека",
        "consume": "Удаление проигранного",
    },
    "en": {
        "random": "Shuffle",
        "repeat": "Repeat",
        "single": "Single track repeat",
        "consume": "Consume",
    },
}


@dataclass
class Reply:
    """What the client says back and how the session should continue."""

    text: str
    ok: bool = True
    should_exit: bool = False


def song_title(song: dict[str, str]) -> str:
    if song.get("title"):
        return song["title"]
    if song.get("name"):
        return song["name"]
    path = song.get("file") or song.get("playlist") or ""
    return Path(path).stem if path else "?"


def song_artist(song: dict[str, str]) -> str:
    return (
        song.get("artist")
        or song.get("albumartist")
        or song.get("performer")
        or ""
    )


def duration_to_clock(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    return f"{total // 60}:{total % 60:02d}"


def song_duration(song: dict[str, str]) -> float:
    raw = song.get("duration") or song.get("time") or "0"
    try:
        return float(raw)
    except ValueError:
        return 0.0


def describe(song: dict[str, str]) -> str:
    """Human readable "Title — Artist (Album)" line."""
    parts = [song_title(song)]
    artist = song_artist(song)
    if artist:
        parts.append(artist)
    album = song.get("album") or ""
    line = " — ".join(parts)
    if album:
        line = f"{line} ({album})"
    seconds = song_duration(song)
    if seconds:
        line = f"{line} [{duration_to_clock(seconds)}]"
    return line


class Controller:
    """Maps intents onto MPD commands; knows nothing about audio."""

    def __init__(self, client: MPDClient, cfg: Config) -> None:
        self.client = client
        self.cfg = cfg
        self._volume_before_mute: int | None = None
        # Mood labels per track path: the tag file is a few tens of MB, so a
        # lookup is one streaming pass and the answer is remembered.
        self._mood_cache: dict[str, list[str]] = {}

    # -- helpers -------------------------------------------------------
    def _t(self, key: str, lang: str = "ru", **kwargs: object) -> str:
        table = PHRASES.get(lang) or PHRASES["ru"]
        template = table.get(key) or PHRASES["en"].get(key, key)
        return template.format(**kwargs)

    def handle_text(self, text: str) -> Reply:
        intent = parse(text)
        if not intent.understood:
            shown = (intent.raw or "").strip()
            return Reply(
                text=self._t("unknown", intent.lang, text=shown), ok=False
            )
        return self.execute(intent)

    def now_playing(self, lang: str = "") -> Reply:
        """What MPD is playing (used by `mpd-voice status`)."""
        return self._now(lang or self.cfg.language)

    def execute(self, intent: Intent) -> Reply:
        handler = getattr(self, f"_do_{intent.name}", None)
        if handler is None:
            return Reply(
                text=self._t("unknown", intent.lang, text=intent.raw), ok=False
            )
        try:
            return handler(intent)
        except MPDConnectionError:
            return Reply(text=self._t("offline", intent.lang), ok=False)
        except MPDError as exc:
            return Reply(
                text=self._t("error", intent.lang, message=exc.message),
                ok=False,
            )

    def _search(self, tag: str, query: str) -> list[dict[str, str]]:
        """Search by tag, falling back to `any` (paths, mixed spellings)."""
        if query:
            if tag in SEARCH_TAGS:
                found = self.client.search(tag, query)
                if found:
                    return found
            return self.client.search_any(query)
        return []

    def _album_tracks(self, query: str) -> list[dict[str, str]]:
        found = self.client.search("album", query)
        if found:
            return found
        loose = self.client.search_any(query)
        if not loose:
            return []
        album = loose[0].get("album") or ""
        if album:
            tracks = self.client.search("album", album)
            if tracks:
                return tracks
        return loose[:1]

    def _replace_and_play(self, songs: list[dict[str, str]]) -> int:
        self.client.clear()
        self.client.add_many(
            [song["file"] for song in songs if song.get("file")]
        )
        self.client.play(0)
        return len(songs)

    def _now(self, lang: str) -> Reply:
        song = self.client.current_song()
        if not song or not song.get("file"):
            return Reply(text=self._t("nothing", lang))
        state = self.client.status().get("state", "")
        if state == "pause":
            text = self._t("paused_state", lang, what=describe(song))
        else:
            text = describe(song)
        moods = self.track_moods(str(song.get("file", "")))
        if moods:
            text = self._t(
                "now_moods", lang, what=text, moods=", ".join(moods)
            )
        return Reply(text=text)

    def track_moods(self, file_uri: str, limit: int = 3) -> list[str]:
        """Mood labels of one MPD track from the tag file (empty when unknown).

        The file holds absolute paths while MPD reports paths relative to
        music_directory, so both spellings are compared.  Records without the
        moods (or a score below ``tags_min_score``) are ignored, and the answer
        is cached per path: a repeat question costs nothing.
        """
        if not file_uri or not self.cfg.tags_file or not self.cfg.music_dir:
            return []
        music_dir = Path(self.cfg.music_dir).expanduser()
        absolute = str(music_dir / file_uri)
        cached = self._mood_cache.get(absolute)
        if cached is not None:
            return cached
        tags_file = Path(self.cfg.tags_file).expanduser()
        labels: list[str] = []
        if tags_file.is_file():
            wanted = {absolute, os.path.realpath(absolute)}
            try:
                with open(
                    tags_file, encoding="utf-8", errors="replace"
                ) as handle:
                    for line in handle:
                        if not line.strip():
                            continue
                        try:
                            record = json.loads(line)
                        except ValueError:
                            continue
                        path = str(record.get("path", ""))
                        if not path or path not in wanted:
                            continue
                        moods = (record.get("tags") or {}).get("mood") or []
                        for item in moods:
                            if not isinstance(item, dict):
                                continue
                            try:
                                score = float(item.get("score", 0.0))
                            except (TypeError, ValueError):
                                continue
                            if score < self.cfg.tags_min_score:
                                continue
                            label = item.get("label")
                            if isinstance(label, str) and label not in labels:
                                labels.append(label)
                            if len(labels) >= limit:
                                break
                        break
            except OSError:
                labels = []
        self._mood_cache[absolute] = labels
        return labels

    # -- playback ------------------------------------------------------
    def _do_play(self, intent: Intent) -> Reply:
        self.client.play()
        return Reply(text=self._t("started", intent.lang))

    def _do_pause(self, intent: Intent) -> Reply:
        self.client.pause(True)
        return Reply(text=self._t("paused", intent.lang))

    def _do_resume(self, intent: Intent) -> Reply:
        self.client.resume()
        return Reply(text=self._t("resumed", intent.lang))

    def _do_toggle(self, intent: Intent) -> Reply:
        paused = self.client.toggle_pause()
        key = "paused" if paused else "resumed"
        return Reply(text=self._t(key, intent.lang))

    def _do_stop(self, intent: Intent) -> Reply:
        self.client.stop()
        return Reply(text=self._t("stopped", intent.lang))

    def _do_next(self, intent: Intent) -> Reply:
        self.client.next()
        return self._now(intent.lang)

    def _do_previous(self, intent: Intent) -> Reply:
        self.client.previous()
        return self._now(intent.lang)

    # -- volume --------------------------------------------------------
    def _report_volume(self, lang: str) -> Reply:
        """Report the volume MPD actually ended up with.

        Outputs without a mixer (the ``null`` plugin, some DACs) report -1 for
        volume and silently ignore ``setvol``; saying "volume 30" then would be
        a lie, so the missing mixer is reported instead.
        """
        value = self.client.volume()
        if value is None:
            return Reply(text=self._t("volume_unsupported", lang), ok=False)
        return Reply(text=self._t("volume", lang, value=value))

    def _do_volume_up(self, intent: Intent) -> Reply:
        step = intent.number or self.cfg.volume_step
        self.client.adjust_volume(abs(step))
        return self._report_volume(intent.lang)

    def _do_volume_down(self, intent: Intent) -> Reply:
        step = intent.number or self.cfg.volume_step
        self.client.adjust_volume(-abs(step))
        return self._report_volume(intent.lang)

    def _do_volume_set(self, intent: Intent) -> Reply:
        self.client.set_volume(intent.number or 0)
        return self._report_volume(intent.lang)

    def _do_volume_get(self, intent: Intent) -> Reply:
        return self._report_volume(intent.lang)

    def _do_mute(self, intent: Intent) -> Reply:
        current = self.client.volume()
        if current is None:
            return Reply(
                text=self._t("volume_unsupported", intent.lang), ok=False
            )
        if current:
            self._volume_before_mute = current
        self.client.set_volume(0)
        return Reply(text=self._t("muted", intent.lang))

    def _do_unmute(self, intent: Intent) -> Reply:
        value = self._volume_before_mute or self.cfg.volume_step
        self.client.set_volume(value)
        return Reply(text=self._t("unmuted", intent.lang, value=value))

    def _do_now_playing(self, intent: Intent) -> Reply:
        return self._now(intent.lang)

    # -- seek ----------------------------------------------------------
    def _do_seek_forward(self, intent: Intent) -> Reply:
        seconds = intent.number or 10
        self.client.seek_relative(seconds)
        return Reply(
            text=self._t("seek_forward", intent.lang, seconds=seconds)
        )

    def _do_seek_back(self, intent: Intent) -> Reply:
        seconds = intent.number or 10
        self.client.seek_relative(-seconds)
        return Reply(text=self._t("seek_back", intent.lang, seconds=seconds))

    def _do_seek_to(self, intent: Intent) -> Reply:
        seconds = float(intent.number or 0)
        self.client.seek_to(seconds)
        return Reply(
            text=self._t(
                "seek_to", intent.lang, position=duration_to_clock(seconds)
            )
        )

    # -- modes ---------------------------------------------------------
    def _mode_reply(self, intent: Intent, mode: str, enabled: bool) -> Reply:
        name = MODE_NAMES.get(intent.lang, MODE_NAMES["ru"])[mode]
        key = "mode_on" if enabled else "mode_off"
        return Reply(text=self._t(key, intent.lang, what=name))

    def _do_shuffle_on(self, intent: Intent) -> Reply:
        return self._mode_reply(intent, "random", self.client.set_random(True))

    def _do_shuffle_off(self, intent: Intent) -> Reply:
        return self._mode_reply(
            intent, "random", self.client.set_random(False)
        )

    def _do_repeat_on(self, intent: Intent) -> Reply:
        return self._mode_reply(intent, "repeat", self.client.set_repeat(True))

    def _do_repeat_off(self, intent: Intent) -> Reply:
        return self._mode_reply(
            intent, "repeat", self.client.set_repeat(False)
        )

    def _do_repeat_single(self, intent: Intent) -> Reply:
        self.client.set_single(True)
        self.client.set_repeat(True)
        return self._mode_reply(intent, "single", True)

    def _do_consume_toggle(self, intent: Intent) -> Reply:
        enabled = self.client.flip_mode("consume")
        return self._mode_reply(intent, "consume", enabled)

    # -- library search ------------------------------------------------
    def _do_play_album(self, intent: Intent) -> Reply:
        found = self._album_tracks(intent.value)
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        count = self._replace_and_play(found)
        return Reply(
            text=self._t(
                "playing_album",
                intent.lang,
                name=found[0].get("album") or intent.value,
                count=count,
            )
        )

    def _do_play_artist(self, intent: Intent) -> Reply:
        found = self.client.search("artist", intent.value)
        if not found:
            found = self.client.search("albumartist", intent.value)
        if not found:
            found = self.client.search_any(intent.value)
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        count = self._replace_and_play(found)
        name = (
            found[0].get("albumartist")
            or found[0].get("artist")
            or intent.value
        )
        return Reply(
            text=self._t("playing_artist", intent.lang, name=name, count=count)
        )

    def _do_play_track(self, intent: Intent) -> Reply:
        found = self._search("title", intent.value)
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        self._replace_and_play(found)
        return Reply(
            text=self._t("playing_track", intent.lang, name=describe(found[0]))
        )

    def _do_play_genre(self, intent: Intent) -> Reply:
        found = self._search("genre", intent.value)
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        count = self._replace_and_play(found)
        return Reply(
            text=self._t(
                "playing_many", intent.lang, name=intent.value, count=count
            )
        )

    def _do_play_directory(self, intent: Intent) -> Reply:
        found = self._search("file", intent.value)
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        count = self._replace_and_play(found)
        return Reply(
            text=self._t(
                "playing_many", intent.lang, name=intent.value, count=count
            )
        )

    def _do_play_any(self, intent: Intent) -> Reply:
        return self._do_play_track(intent)

    def _do_play_playlist(self, intent: Intent) -> Reply:
        self.client.clear()
        self.client.load_playlist(intent.value)
        self.client.play(0)
        tracks = self.client.queue()
        return Reply(
            text=self._t(
                "playlist_loaded",
                intent.lang,
                name=intent.value,
                count=len(tracks),
            )
        )

    def _do_add_to_queue(self, intent: Intent) -> Reply:
        tag = intent.tag or "any"
        if tag == "playlist":
            count = len(self.client.playlist_songs(intent.value))
            self.client.load_playlist(intent.value)
            return Reply(
                text=self._t(
                    "playlist_loaded",
                    intent.lang,
                    name=intent.value,
                    count=count,
                )
            )
        found = self._search(
            tag if tag in SEARCH_TAGS else "any", intent.value
        )
        if not found:
            return Reply(
                text=self._t("not_found", intent.lang, name=intent.value),
                ok=False,
            )
        added = self.client.add_many(
            [song["file"] for song in found if song.get("file")]
        )
        return Reply(text=self._t("added", intent.lang, count=added))

    def _do_queue_similar(self, intent: Intent) -> Reply:
        """Append neighbours of the current track, asked from a helper tool."""
        song = self.client.current_song()
        if not song or not song.get("file"):
            return Reply(
                text=self._t("similar_nothing", intent.lang), ok=False
            )
        if not self.cfg.music_dir:
            return Reply(text=self._t("similar_no_dir", intent.lang), ok=False)
        music_dir = Path(self.cfg.music_dir).expanduser()
        if not music_dir.is_dir():
            return Reply(text=self._t("similar_no_dir", intent.lang), ok=False)
        # MPD reports file paths relative to music_directory; the helper
        # expects the real path of the current track.
        query = music_dir / song["file"]
        if not query.is_file():
            return Reply(
                text=self._t("similar_missing", intent.lang), ok=False
            )
        try:
            argv = shlex.split(self.cfg.similar_cmd)
        except ValueError:
            return Reply(text=self._t("similar_failed", intent.lang), ok=False)
        if not argv:
            return Reply(text=self._t("similar_failed", intent.lang), ok=False)
        try:
            result = subprocess.run(
                argv + [str(query)],
                capture_output=True,
                text=True,
                errors="replace",
                timeout=120,
            )
        except (OSError, subprocess.SubprocessError):
            return Reply(text=self._t("similar_failed", intent.lang), ok=False)
        if result.returncode != 0:
            return Reply(text=self._t("similar_failed", intent.lang), ok=False)
        try:
            payload = json.loads(result.stdout)
        except ValueError:
            return Reply(text=self._t("similar_failed", intent.lang), ok=False)
        entries = payload.get("results") if isinstance(payload, dict) else None
        uris = []
        for item in entries or []:
            path = item.get("path") if isinstance(item, dict) else ""
            if path:
                uris.append(os.path.relpath(path, music_dir))
        if not uris:
            return Reply(text=self._t("similar_empty", intent.lang), ok=False)
        added = self.client.add_many(uris)
        return Reply(text=self._t("similar_added", intent.lang, count=added))

    def _do_play_mood(self, intent: Intent) -> Reply:
        """Queue tracks tagged with a Jamendo mood label from ``tags_file``.

        The JSONL file is streamed once: only matching URIs stay in memory,
        so a 40k-line library costs one pass and a shortlist.  Broken lines
        are skipped; matching tracks are shuffled before the cap so repeated
        requests do not always queue the same first tracks.

        ``tags_exclude`` globs (relative to ``music_dir``) and the
        ``audio_seconds`` floor keep one-shot samples out of the queue; a
        record without ``audio_seconds`` cannot be judged and is kept.
        """
        mood = intent.value
        if not mood:
            return Reply(
                text=self._t("mood_empty", intent.lang, mood=mood), ok=False
            )
        if not self.cfg.music_dir:
            return Reply(text=self._t("mood_no_dir", intent.lang), ok=False)
        music_dir = Path(self.cfg.music_dir).expanduser()
        if not music_dir.is_dir():
            return Reply(text=self._t("mood_no_dir", intent.lang), ok=False)
        tags_file = Path(self.cfg.tags_file).expanduser()
        if not tags_file.is_file():
            return Reply(
                text=self._t("mood_missing", intent.lang, path=tags_file),
                ok=False,
            )
        excludes = [
            pattern.strip()
            for pattern in self.cfg.tags_exclude.split(",")
            if pattern.strip()
        ]
        matches: list[str] = []
        lines = 0
        broken = 0
        try:
            with open(tags_file, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if not line.strip():
                        continue
                    lines += 1
                    try:
                        entry = json.loads(line)
                    except ValueError:
                        broken += 1
                        continue
                    if not isinstance(entry, dict):
                        broken += 1
                        continue
                    if self._mood_too_short(entry):
                        continue
                    path = self._mood_path(entry, mood)
                    if not path:
                        continue
                    uri = self._mpd_uri(path, music_dir)
                    if not uri or self._mood_excluded(uri, excludes):
                        continue
                    matches.append(uri)
        except OSError:
            return Reply(text=self._t("mood_failed", intent.lang), ok=False)
        if not matches:
            if lines and broken == lines:
                return Reply(
                    text=self._t("mood_broken", intent.lang, count=broken),
                    ok=False,
                )
            return Reply(
                text=self._t("mood_empty", intent.lang, mood=mood), ok=False
            )
        pool = list(dict.fromkeys(matches))
        random.shuffle(pool)
        if self.cfg.tags_limit > 0:
            pool = pool[: self.cfg.tags_limit]
        added = self.client.add_many(pool)
        return Reply(
            text=self._t("mood_added", intent.lang, count=added, mood=mood)
        )

    def _mood_path(self, entry: dict[str, object], mood: str) -> str:
        """Path of an entry whose mood label clears the score floor."""
        path = entry.get("path")
        if not isinstance(path, str) or not path:
            return ""
        tags = entry.get("tags")
        if not isinstance(tags, dict):
            return ""
        moods = tags.get("mood")
        if not isinstance(moods, list):
            return ""
        for item in moods:
            if not isinstance(item, dict) or item.get("label") != mood:
                continue
            try:
                score = float(item.get("score", 0.0))
            except (TypeError, ValueError):
                continue
            if score >= self.cfg.tags_min_score:
                return path
        return ""

    def _mood_too_short(self, entry: dict[str, object]) -> bool:
        """True when the tagger measured a clip below ``tags_min_seconds``.

        ``audio_seconds`` was added to the tagger after the first tag files
        were written, so an absent field cannot be judged and must not drop
        the track; the same goes for a value that is not a number.  Setting
        ``tags_min_seconds`` to 0 disables the filter.
        """
        raw = entry.get("audio_seconds")
        if raw is None:
            return False
        try:
            seconds = float(raw)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            return False
        return seconds < self.cfg.tags_min_seconds

    @staticmethod
    def _mood_excluded(uri: str, patterns: list[str]) -> bool:
        """True when the URI matches any ``tags_exclude`` glob."""
        return any(fnmatch.fnmatch(uri, pattern) for pattern in patterns)

    @staticmethod
    def _mpd_uri(path: str, music_dir: Path) -> str:
        """Tag-file absolute path -> MPD URI, or "" when outside music_dir."""
        if not os.path.isabs(path):
            return ""
        try:
            relative = os.path.relpath(path, music_dir)
        except ValueError:
            return ""
        if relative in (os.curdir, os.pardir):
            return ""
        if relative.startswith(os.pardir + os.sep):
            return ""
        return relative

    def _do_clear_queue(self, intent: Intent) -> Reply:
        self.client.clear()
        return Reply(text=self._t("queue_cleared", intent.lang))

    def _do_list_playlists(self, intent: Intent) -> Reply:
        names = self.client.playlists()
        if not names:
            return Reply(text=self._t("playlists_empty", intent.lang))
        return Reply(
            text=self._t("playlists", intent.lang, names=", ".join(names))
        )

    def _do_save_playlist(self, intent: Intent) -> Reply:
        self.client.save_playlist(intent.value)
        return Reply(
            text=self._t("playlist_saved", intent.lang, name=intent.value)
        )

    def _do_update_library(self, intent: Intent) -> Reply:
        self.client.update()
        return Reply(text=self._t("updating", intent.lang))

    # -- meta ----------------------------------------------------------
    def _do_help(self, intent: Intent) -> Reply:
        return Reply(text=self._t("help", intent.lang))

    def _do_exit(self, intent: Intent) -> Reply:
        return Reply(text=self._t("bye", intent.lang), should_exit=True)
