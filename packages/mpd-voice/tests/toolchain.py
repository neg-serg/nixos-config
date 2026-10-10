"""Locate external tools for the opt-in test tiers.

On NixOS the daemons and speech tools often live in the store without being on
``PATH``; the tests accept an explicit environment variable first and fall
back to a store glob, which keeps them portable enough for a repo-local suite.
"""

from __future__ import annotations

import glob
import os
import shutil
from pathlib import Path


def _find(env_var: str, name: str, store_glob: str) -> str | None:
    explicit = os.environ.get(env_var)
    if explicit:
        return explicit if Path(explicit).exists() else None
    found = shutil.which(name)
    if found:
        return found
    matches = sorted(glob.glob(store_glob))
    return matches[-1] if matches else None


def mpd_binary() -> str | None:
    return _find("MPD_VOICE_TEST_MPD_BIN", "mpd", "/nix/store/*-mpd-*/bin/mpd")


def ffmpeg_binary() -> str | None:
    return _find(
        "MPD_VOICE_FFMPEG_BIN", "ffmpeg", "/nix/store/*-ffmpeg-*/bin/ffmpeg"
    )


def espeak_binary() -> str | None:
    return _find(
        "MPD_VOICE_ESPEAK_BIN",
        "espeak-ng",
        "/nix/store/*-espeak-ng-*/bin/espeak-ng",
    )


def whisper_cli() -> str | None:
    return _find(
        "MPD_VOICE_WHISPER_BIN",
        "whisper-cli",
        "/nix/store/*-whisper-cpp-*/bin/whisper-cli",
    )


def whisper_model() -> str | None:
    explicit = os.environ.get("MPD_VOICE_WHISPER_MODEL")
    if explicit:
        return explicit if Path(explicit).exists() else None
    candidates = [
        "/zero/ai/speech/engines/voices/ggml-large-v3-turbo.bin",
        "/zero/ai/speech/engines/voices/ggml-small.bin",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    engines = sorted(
        glob.glob("/zero/ai/speech/engines/**/ggml-*.bin", recursive=True)
    )
    return engines[0] if engines else None
