"""Text-to-speech backends for spoken confirmations.

``http`` posts to any OpenAI-compatible ``/v1/audio/speech`` endpoint (the
repo's ``piper-server.py`` on :8001) and pipes the returned WAV into the
default sink.  ``cmd`` runs a local command such as ``espeak-ng`` or
``spd-say``.  ``none`` keeps the client silent — replies are still printed.
"""

from __future__ import annotations

import json
import shlex
import shutil
import subprocess
import urllib.error
import urllib.request

_CANDIDATES = ("spd-say", "espeak-ng", "espeak", "say", "festival")
_PLAYERS = ("pw-play", "paplay", "aplay", "ffplay")


class TTSError(RuntimeError):
    """No usable TTS backend, or the backend failed."""


def detect_player() -> list[str]:
    """Command that plays a WAV file from stdin (``-`` means stdin)."""
    for player in _PLAYERS:
        path = shutil.which(player)
        if not path:
            continue
        if player == "ffplay":
            return [
                path,
                "-hide_banner",
                "-loglevel",
                "error",
                "-nodisp",
                "-autoexit",
                "-",
            ]
        if player == "pw-play":
            return [path, "--volume=1.0", "-"]
        return [path, "-q", "-"]
    raise TTSError(
        "no audio player found for HTTP speech output "
        "(install pipewire, pulseaudio-utils, alsa-utils or ffmpeg)"
    )


def play_bytes(data: bytes, player: list[str] | None = None) -> None:
    argv = player or detect_player()
    try:
        process = subprocess.run(argv, input=data, check=False)
    except OSError as exc:
        raise TTSError(f"cannot play audio with {argv[0]}: {exc}") from exc
    if process.returncode != 0:
        raise TTSError(f"{argv[0]} exited with {process.returncode}")


class HttpTTS:
    """OpenAI-compatible speech endpoint, played on the local sink."""

    name = "http"

    def __init__(
        self,
        base_url: str,
        voice: str = "default",
        model: str = "piper",
        timeout: float = 60.0,
        player: list[str] | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.voice = voice
        self.model = model
        self.timeout = timeout
        self.player = player

    @property
    def endpoint(self) -> str:
        return f"{self.base_url}/v1/audio/speech"

    @property
    def models_endpoint(self) -> str:
        return f"{self.base_url}/v1/models"

    def available(self, timeout: float = 1.5) -> bool:
        try:
            with urllib.request.urlopen(self.models_endpoint, timeout=timeout):
                return True
        except (urllib.error.URLError, OSError, ValueError):
            return False

    def speak(self, text: str) -> None:
        if not text.strip():
            return
        payload = json.dumps(
            {
                "model": self.model,
                "input": text,
                "voice": self.voice,
                "response_format": "wav",
            }
        ).encode()
        request = urllib.request.Request(
            self.endpoint,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(
                request, timeout=self.timeout
            ) as answer:
                audio = answer.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:200]
            raise TTSError(
                f"speech synthesis failed ({exc.code}): {detail}"
            ) from exc
        except (urllib.error.URLError, OSError) as exc:
            raise TTSError(f"speech endpoint unreachable: {exc}") from exc
        if not audio:
            raise TTSError("speech endpoint returned empty audio")
        play_bytes(audio, self.player)


class CmdTTS:
    """Speak by running a local command; ``{text}`` becomes one argv element."""

    name = "cmd"
    # Placeholder that survives shlex parsing, so a phrase containing spaces
    # (or quotes) is still passed as exactly one argument.
    _TOKEN = "\x00mpd-voice-text\x00"

    def __init__(self, command: str, timeout: float = 60.0) -> None:
        if not command:
            raise TTSError("the 'cmd' backend needs --tts-cmd")
        self.command = command
        self.timeout = timeout

    def available(self) -> bool:
        try:
            argv = self._argv("probe")
        except (KeyError, ValueError, TTSError):
            return False
        return bool(argv) and shutil.which(argv[0]) is not None

    def _argv(self, text: str) -> list[str]:
        if "{text}" not in self.command:
            raise TTSError("the --tts-cmd template must contain {text}")
        template = shlex.split(self.command.replace("{text}", self._TOKEN))
        return [argument.replace(self._TOKEN, text) for argument in template]

    def speak(self, text: str) -> None:
        if not text.strip():
            return
        argv = self._argv(text)
        try:
            process = subprocess.run(
                argv, capture_output=True, timeout=self.timeout, check=False
            )
        except OSError as exc:
            raise TTSError(f"cannot run {argv[0]}: {exc}") from exc
        except subprocess.TimeoutExpired as exc:
            raise TTSError(f"{argv[0]} timed out") from exc
        if process.returncode != 0:
            tail = process.stderr.decode(errors="replace").strip().splitlines()
            raise TTSError(f"TTS command failed: {tail[-1] if tail else ''}")


class NullTTS:
    """Stay silent."""

    name = "none"

    def available(self) -> bool:
        return False

    def speak(self, text: str) -> None:
        return None


def default_command(binary: str) -> str:
    """Sensible argv template for the detected local speech tool."""
    if binary == "spd-say":
        return "spd-say -w -e {text}"
    if binary in ("espeak-ng", "espeak"):
        return f"{binary} -s 165 -v ru {{text}}"
    if binary == "say":
        return "say {text}"
    return "festival --tts {text}"


def detect_tts() -> object:
    """First available local tool, else the null backend."""
    for binary in _CANDIDATES:
        path = shutil.which(binary)
        if path:
            return CmdTTS(default_command(binary))
    return NullTTS()


def build_tts(
    kind: str = "auto",
    *,
    base_url: str = "http://127.0.0.1:8001",
    voice: str = "default",
    command: str = "",
    timeout: float = 60.0,
) -> object:
    """Construct the requested backend; ``auto`` prefers HTTP, then local."""
    if kind == "none":
        return NullTTS()
    if kind == "cmd":
        return CmdTTS(command, timeout=timeout)
    if kind == "http":
        return HttpTTS(base_url, voice=voice, timeout=timeout)
    http = HttpTTS(base_url, voice=voice, timeout=timeout)
    if http.available():
        return http
    return detect_tts()
