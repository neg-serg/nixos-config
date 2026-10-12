"""Effective configuration: files, environment, then command line flags.

Config files are read from ``$XDG_CONFIG_DIRS/mpd-voice/config.toml`` and
``$XDG_CONFIG_HOME/mpd-voice/config.toml`` (user file wins).  The installer
writes the system file, so per-user tweaks stay possible without rebuilding.
"""

from __future__ import annotations

import os
import tomllib
from collections.abc import Mapping
from dataclasses import dataclass, fields
from pathlib import Path

APP = "mpd-voice"


@dataclass
class Config:
    """Configuration with defaults; every field is overridable from TOML."""

    mpd_host: str = "127.0.0.1"
    mpd_port: int = 6600
    mpd_password: str = ""

    language: str = "ru"
    wake_word: str = ""
    confirm: bool = True
    volume_step: int = 5
    max_seconds: float = 8.0
    silence_seconds: float = 0.8

    capture: str = "auto"
    capture_cmd: str = ""
    device: str = ""

    stt: str = "auto"
    stt_url: str = "http://127.0.0.1:8002"
    stt_bin: str = "whisper-cli"
    stt_model: str = ""
    stt_cmd: str = ""

    tts: str = "auto"
    tts_url: str = "http://127.0.0.1:8001"
    tts_voice: str = "default"
    tts_cmd: str = ""

    # Neighbour tracks come from an external helper.  MPD reports file paths
    # relative to music_directory, while the helper wants absolute paths, so
    # music_dir must match the MPD ``music_directory`` setting.
    similar_cmd: str = "music-similar --json -k 10"
    music_dir: str = "~/music"

    # Mood tags come from the trained MTG Jamendo head (music-mtg-tags).  The
    # cache lives outside the repo because it is derived and machine specific:
    # one tagging run writes it, `music-mtg-tags --dir ~/music --out
    # ~/.cache/music-mtg/tags.jsonl --json`.
    tags_file: str = "~/.cache/music-mtg/tags.jsonl"
    # Measured mood scores on real tracks sit in the 0.10-0.40 band (dark
    # 0.31 on a funeral-doom clip, epic 0.31, soundscape 0.21), so 0.10 keeps
    # labels that are clearly present but far from confident and still drops
    # near-zero noise.  Raise it for stricter mood playlists.
    tags_min_score: float = 0.10
    # Tracks shorter than this are treated as one-shot samples, not music.
    # ``audio_seconds`` is the decoded length the tagger analysed; records
    # from tag files produced before the field existed cannot be judged and
    # are kept, so an old cache keeps working.  45 s is a sane floor for
    # "music, not a sample": real tracks run for minutes, while instrument
    # samples (e.g. the two-second VCSL piano notes) are seconds long.
    tags_min_seconds: float = 45.0
    # Comma-separated fnmatch globs matched against the track path relative
    # to ``music_dir``; the default drops the measured offender, the
    # one-shot VCSL samples under ``~/music/samples``.  An empty string
    # means no patterns (override with MPD_VOICE_TAGS_EXCLUDE).
    tags_exclude: str = "samples/*"
    tags_limit: int = 25

    def apply_mapping(self, values: Mapping[str, object]) -> None:
        """Overlay ``values``; unknown keys and wrong shapes are ignored."""
        known = {field.name for field in fields(self)}
        for key, value in values.items():
            if key not in known or isinstance(value, (dict, list)):
                continue
            setattr(self, key, _coerce(getattr(self, key), value))


def _coerce(current: object, value: object) -> object:
    try:
        if isinstance(current, bool):
            return bool(value)
        if isinstance(current, int):
            return int(value)  # type: ignore[arg-type]
        if isinstance(current, float):
            return float(value)  # type: ignore[arg-type]
        return str(value)
    except (TypeError, ValueError):
        return current


def config_paths() -> list[Path]:
    """System directories first, user directory last (it wins)."""
    directories = os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg"
    home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    paths = [
        Path(directory) / APP / "config.toml"
        for directory in directories.split(":")
    ]
    paths.append(Path(home) / APP / "config.toml")
    return paths


def load(path: str | Path | None = None) -> tuple[Config, list[Path]]:
    """Return the effective config and the files that contributed to it."""
    config = Config()
    if path is not None:
        candidates = [Path(path)]
    else:
        candidates = config_paths()
    used: list[Path] = []
    for candidate in candidates:
        try:
            with open(candidate, "rb") as handle:
                document = tomllib.load(handle)
        except FileNotFoundError:
            continue
        except (OSError, tomllib.TOMLDecodeError):
            continue
        section = (
            document.get(APP, document) if isinstance(document, dict) else {}
        )
        if isinstance(section, dict):
            config.apply_mapping(section)
            used.append(candidate)
    config.apply_mapping(_environment())
    return config, used


def _environment() -> dict[str, object]:
    """mpc-compatible MPD variables plus a couple of MPD_VOICE_* ones."""
    mapping: dict[str, object] = {}
    if os.environ.get("MPD_HOST"):
        mapping["mpd_host"] = os.environ["MPD_HOST"]
    if os.environ.get("MPD_PORT"):
        mapping["mpd_port"] = os.environ["MPD_PORT"]
    if os.environ.get("MPD_PASSWORD"):
        mapping["mpd_password"] = os.environ["MPD_PASSWORD"]
    if os.environ.get("MPD_VOICE_LANG"):
        mapping["language"] = os.environ["MPD_VOICE_LANG"]
    if os.environ.get("MPD_VOICE_STT"):
        mapping["stt"] = os.environ["MPD_VOICE_STT"]
    if os.environ.get("MPD_VOICE_TTS"):
        mapping["tts"] = os.environ["MPD_VOICE_TTS"]
    if os.environ.get("MPD_VOICE_TAGS_FILE"):
        mapping["tags_file"] = os.environ["MPD_VOICE_TAGS_FILE"]
    # Presence, not truthiness: an empty MPD_VOICE_TAGS_EXCLUDE means "no
    # exclude patterns", which is different from leaving the default in place.
    if "MPD_VOICE_TAGS_EXCLUDE" in os.environ:
        mapping["tags_exclude"] = os.environ["MPD_VOICE_TAGS_EXCLUDE"]
    return mapping
