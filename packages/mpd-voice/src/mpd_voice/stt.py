"""Speech-to-text backends.

Three escape hatches keep the client usable on this host, where the local
speech stack is switched off by policy:

``http``  any OpenAI-compatible ``/v1/audio/transcriptions`` endpoint (the
          repo's ``whisper-server.py`` on :8002 when it is enabled);
``cli``   ``whisper-cli`` from whisper.cpp directly (no server needed);
``cmd``   an arbitrary command template, for anything else (hyprwhspr,
          whisperx, a cloud CLI, ...).
"""

from __future__ import annotations

import json
import re
import shlex
import shutil
import subprocess
import urllib.error
import urllib.request
import uuid
from pathlib import Path

_TIMESTAMP_PREFIX = re.compile(r"^\s*\[[^\]]*\]\s*")
_WHISPER_NOISE = (
    "whisper_",
    "ggml_",
    "main:",
    "system_info",
    "load time",
    "whisper_print",
    "error:",
    "warning:",
)


class STTError(RuntimeError):
    """No usable backend, or the backend failed."""


def _multipart(
    fields: dict[str, str],
    file_field: str,
    filename: str,
    data: bytes,
    content_type: str,
) -> tuple[bytes, str]:
    """Build a multipart/form-data body without third-party libraries."""
    boundary = f"----mpdvoice{uuid.uuid4().hex}"
    body = bytearray()
    for key, value in fields.items():
        body += (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{key}"\r\n\r\n'
            f"{value}\r\n"
        ).encode()
    body += (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{file_field}"; '
        f'filename="{filename}"\r\n'
        f"Content-Type: {content_type}\r\n\r\n"
    ).encode()
    body += data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def clean_transcript(text: str) -> str:
    """Drop whisper.cpp log noise and collapse whitespace.

    Timestamped segments (``[00:00.000 --> 00:02.000] text``) keep their text:
    only the bracketed prefix is removed, so output stays usable even when the
    backend was invoked without ``-nt``.
    """
    lines = []
    for line in (text or "").splitlines():
        stripped = _TIMESTAMP_PREFIX.sub("", line).strip()
        if not stripped:
            continue
        lowered = stripped.lower()
        if any(lowered.startswith(token) for token in _WHISPER_NOISE):
            continue
        lines.append(stripped)
    return " ".join(" ".join(lines).split())


class HttpSTT:
    """OpenAI-compatible HTTP transcription client."""

    name = "http"

    def __init__(
        self,
        base_url: str,
        model: str = "whisper-1",
        language: str = "ru",
        timeout: float = 120.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model or "whisper-1"
        self.language = language
        self.timeout = timeout

    @property
    def endpoint(self) -> str:
        return f"{self.base_url}/v1/audio/transcriptions"

    @property
    def models_endpoint(self) -> str:
        return f"{self.base_url}/v1/models"

    def available(self, timeout: float = 1.5) -> bool:
        try:
            with urllib.request.urlopen(self.models_endpoint, timeout=timeout):
                return True
        except (urllib.error.URLError, OSError, ValueError):
            return False

    def transcribe(
        self, wav_path: str | Path, language: str | None = None
    ) -> str:
        source = Path(wav_path)
        fields = {"model": self.model, "response_format": "json"}
        lang = language or self.language
        if lang and lang != "auto":
            fields["language"] = lang[:2]
        body, content_type = _multipart(
            fields, "file", source.name, source.read_bytes(), "audio/wav"
        )
        request = urllib.request.Request(
            self.endpoint,
            data=body,
            headers={"Content-Type": content_type},
            method="POST",
        )
        try:
            with urllib.request.urlopen(
                request, timeout=self.timeout
            ) as answer:
                payload = answer.read()
                status = answer.status
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:200]
            raise STTError(
                f"transcription failed ({exc.code}): {detail}"
            ) from exc
        except (urllib.error.URLError, OSError) as exc:
            raise STTError(
                f"transcription endpoint unreachable: {exc}"
            ) from exc
        if status != 200:
            raise STTError(f"transcription failed with status {status}")
        return self._parse(payload)

    @staticmethod
    def _parse(payload: bytes) -> str:
        text = payload.decode("utf-8", errors="replace")
        try:
            document = json.loads(text)
        except json.JSONDecodeError:
            return clean_transcript(text)
        if isinstance(document, dict):
            value = document.get("text", "")
            if isinstance(value, str):
                return clean_transcript(value)
        return clean_transcript(text)


class CliSTT:
    """whisper.cpp's ``whisper-cli`` driven directly."""

    name = "cli"

    def __init__(
        self,
        binary: str = "whisper-cli",
        model: str = "",
        language: str = "ru",
        extra_args: tuple[str, ...] = (),
        timeout: float = 300.0,
    ) -> None:
        self.binary = binary
        self.model = model
        self.language = language
        self.extra_args = tuple(extra_args)
        self.timeout = timeout

    def available(self) -> bool:
        if shutil.which(self.binary) is None:
            return False
        return not self.model or Path(self.model).exists()

    def _argv(self, wav_path: str, language: str, quiet: bool) -> list[str]:
        argv = [self.binary, "-nt"]
        if quiet:
            argv.append("-np")
        if self.model:
            argv += ["-m", self.model]
        argv += ["-f", str(wav_path)]
        if language and language != "auto":
            argv += ["-l", language[:2]]
        return argv + list(self.extra_args)

    def transcribe(
        self, wav_path: str | Path, language: str | None = None
    ) -> str:
        if shutil.which(self.binary) is None:
            raise STTError(f"'{self.binary}' is not in PATH")
        lang = language or self.language
        result = self._run(self._argv(str(wav_path), lang, quiet=True))
        if (
            result.returncode != 0
            and "unknown argument" in result.stderr.lower()
        ):
            # Older whisper.cpp builds have no -np flag.
            result = self._run(self._argv(str(wav_path), lang, quiet=False))
        if result.returncode != 0:
            tail = result.stderr.strip().splitlines()[-1:] or [""]
            raise STTError(f"{self.binary} failed: {tail[0]}")
        return clean_transcript(result.stdout)

    def _run(self, argv: list[str]) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                check=False,
            )
        except OSError as exc:
            raise STTError(f"cannot run {argv[0]}: {exc}") from exc
        except subprocess.TimeoutExpired as exc:
            raise STTError(
                f"{argv[0]} timed out after {self.timeout:g}s"
            ) from exc


class CmdSTT:
    """Transcribe by running a user supplied command.

    The template may use ``{wav}`` and ``{lang}``; each placeholder becomes a
    single argv element, and the command must print the transcript to stdout.
    """

    name = "cmd"
    _WAV_TOKEN = "\x00mpd-voice-wav\x00"
    _LANG_TOKEN = "\x00mpd-voice-lang\x00"

    def __init__(
        self, command: str, language: str = "ru", timeout: float = 300.0
    ):
        if not command:
            raise STTError("the 'cmd' backend needs --stt-cmd")
        self.command = command
        self.language = language
        self.timeout = timeout

    def available(self) -> bool:
        try:
            argv = self._argv("probe.wav", self.language)
        except (KeyError, ValueError, STTError):
            return False
        return bool(argv) and shutil.which(argv[0]) is not None

    def _argv(self, wav_path: str, language: str) -> list[str]:
        if "{wav}" not in self.command:
            raise STTError("the --stt-cmd template must contain {wav}")
        template = self.command.replace("{wav}", self._WAV_TOKEN).replace(
            "{lang}", self._LANG_TOKEN
        )
        return [
            argument.replace(self._WAV_TOKEN, wav_path).replace(
                self._LANG_TOKEN, language
            )
            for argument in shlex.split(template)
        ]

    def transcribe(
        self, wav_path: str | Path, language: str | None = None
    ) -> str:
        argv = self._argv(str(wav_path), language or self.language)
        try:
            result = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                check=False,
            )
        except OSError as exc:
            raise STTError(f"cannot run {argv[0]}: {exc}") from exc
        except subprocess.TimeoutExpired as exc:
            raise STTError(f"{argv[0]} timed out") from exc
        if result.returncode != 0:
            tail = result.stderr.strip().splitlines()[-1:] or [""]
            raise STTError(f"STT command failed: {tail[0]}")
        return clean_transcript(result.stdout)


class NullSTT:
    """Placeholder for text-only operation."""

    name = "none"

    def available(self) -> bool:
        return False

    def transcribe(
        self, wav_path: str | Path, language: str | None = None
    ) -> str:
        raise STTError("speech recognition is disabled (--stt none)")


def build_stt(
    kind: str = "auto",
    *,
    base_url: str = "http://127.0.0.1:8002",
    model: str = "",
    binary: str = "whisper-cli",
    command: str = "",
    language: str = "ru",
    timeout: float = 300.0,
) -> object:
    """Construct the requested backend; ``auto`` probes HTTP, then the CLI."""
    if kind == "none":
        return NullSTT()
    if kind == "cmd":
        return CmdSTT(command, language=language, timeout=timeout)
    if kind == "cli":
        return CliSTT(binary, model, language, timeout=timeout)
    if kind == "http":
        return HttpSTT(base_url, language=language, timeout=timeout)
    http = HttpSTT(base_url, language=language, timeout=timeout)
    if http.available():
        return http
    cli = CliSTT(binary, model, language, timeout=timeout)
    if cli.available():
        return cli
    raise STTError(
        "no speech recognition backend available: enable the local speech "
        "stack, point --stt-url at an OpenAI-compatible server, pass "
        "--stt cli with --stt-model, or use --stt-cmd"
    )
