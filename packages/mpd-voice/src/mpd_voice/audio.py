"""Microphone capture with a small energy based voice activity detector.

Capture itself is delegated to whatever the host already has (PipeWire, ALSA,
FFmpeg, SoX), so the client needs no Python audio stack.  The recorder reads
raw signed 16-bit mono PCM from the child process, feeds fixed size frames to
:class:`SpeechGate` and returns only the utterance (silence trimmed).
"""

from __future__ import annotations

import array
import math
import shlex
import shutil
import subprocess
import time
import wave
from collections import deque
from pathlib import Path

PCM_RATE = 16000
PCM_WIDTH = 2
PCM_CHANNELS = 1
FRAME_MS = 30

# Backends in auto-detection order.
BACKENDS = ("pw-record", "arecord", "ffmpeg", "sox", "cmd")


class CaptureError(RuntimeError):
    """No capture backend, or the child process failed."""


def build_capture_argv(
    backend: str, device: str = "", rate: int = PCM_RATE, command: str = ""
) -> list[str]:
    """Command line that writes raw s16le mono PCM to stdout."""
    if backend == "cmd":
        if not command:
            raise CaptureError(
                "capture backend 'cmd' needs a command template"
            )
        return shlex.split(
            command.format(rate=rate, device=device or "default")
        )
    if backend == "pw-record":
        argv = [
            "pw-record",
            "--rate",
            str(rate),
            "--channels",
            str(PCM_CHANNELS),
            "--format",
            "s16",
        ]
        if device:
            argv += ["--target", device]
        return argv + ["-"]
    if backend == "arecord":
        argv = [
            "arecord",
            "-q",
            "-t",
            "raw",
            "-f",
            "S16_LE",
            "-r",
            str(rate),
            "-c",
            str(PCM_CHANNELS),
        ]
        if device:
            argv += ["-D", device]
        return argv + ["-"]
    if backend == "ffmpeg":
        return [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "pulse",
            "-i",
            device or "default",
            "-ac",
            str(PCM_CHANNELS),
            "-ar",
            str(rate),
            "-f",
            "s16le",
            "-",
        ]
    if backend == "sox":
        return [
            "sox",
            "-q",
            "-t",
            "raw",
            "-r",
            str(rate),
            "-c",
            str(PCM_CHANNELS),
            "-e",
            "signed-integer",
            "-b",
            "16",
            device or "-d",
            "-",
        ]
    raise CaptureError(f"unknown capture backend: {backend}")


def detect_backend(preferred: str = "auto", command: str = "") -> str:
    """Pick the first usable capture backend (``cmd`` wins when given)."""
    if command:
        return "cmd"
    if preferred == "cmd":
        raise CaptureError(
            "the 'cmd' capture backend needs a command template"
        )
    if preferred != "auto":
        if shutil.which(build_capture_argv(preferred)[0]):
            return preferred
        raise CaptureError(f"capture backend not found: {preferred}")
    for backend in BACKENDS:
        if backend == "cmd":
            continue
        try:
            argv = build_capture_argv(backend)
        except CaptureError:
            continue
        if shutil.which(argv[0]):
            return backend
    raise CaptureError(
        "no capture backend found (install pipewire, alsa-utils, ffmpeg or sox)"
    )


def rms(frame: bytes) -> float:
    """Root mean square of a signed 16-bit little-endian frame."""
    samples = array.array("h")
    samples.frombytes(frame[: len(frame) - (len(frame) % 2)])
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))


class SpeechGate:
    """Energy gate with an adaptive noise floor.

    ``push`` consumes one frame and returns ``idle``, ``speech_start``,
    ``speech`` or ``speech_end``; the accepted utterance is available as
    ``utterance`` (pre-roll included, trailing silence trimmed).
    """

    def __init__(
        self,
        rate: int = PCM_RATE,
        frame_ms: int = FRAME_MS,
        silence_seconds: float = 0.8,
        min_speech_seconds: float = 0.3,
        threshold_ratio: float = 3.0,
        absolute_floor: float = 120.0,
        pre_roll_seconds: float = 0.24,
    ) -> None:
        self.frame_bytes = int(rate * frame_ms / 1000) * PCM_WIDTH
        self.silence_frames = max(1, int(silence_seconds * 1000 / frame_ms))
        self.min_speech_frames = max(
            1, int(min_speech_seconds * 1000 / frame_ms)
        )
        self.threshold_ratio = threshold_ratio
        self.absolute_floor = absolute_floor
        self.noise_floor = absolute_floor
        self._pre_roll: deque[bytes] = deque(
            maxlen=max(1, int(pre_roll_seconds * 1000 / frame_ms))
        )
        self.state = "idle"
        self.utterance = bytearray()
        self._speech_frames = 0
        self._silent_frames = 0

    @property
    def threshold(self) -> float:
        return max(
            self.noise_floor * self.threshold_ratio, self.absolute_floor
        )

    @property
    def speech_seconds(self) -> float:
        return self._speech_frames * self.frame_bytes / (PCM_RATE * PCM_WIDTH)

    def push(self, frame: bytes) -> str:
        level = rms(frame)
        if self.state == "idle":
            if level >= self.threshold:
                self.state = "speech"
                self._speech_frames = 1
                self._silent_frames = 0
                self.utterance = bytearray().join(self._pre_roll)
                self.utterance += frame
                self._pre_roll.clear()
                return "speech_start"
            # Track the room: quiet frames define the noise floor.
            self.noise_floor = 0.9 * self.noise_floor + 0.1 * level
            self._pre_roll.append(frame)
            return "idle"
        if level >= self.threshold:
            self._speech_frames += 1
            self._silent_frames = 0
            self.utterance += frame
            return "speech"
        self._silent_frames += 1
        self.utterance += frame
        if self._silent_frames >= self.silence_frames:
            self.state = "idle"
            # Drop the trailing pause but keep the final 150 ms of it.
            keep = 5 * self.frame_bytes
            excess = (self._silent_frames - 1) * self.frame_bytes - keep
            if excess > 0:
                del self.utterance[len(self.utterance) - excess :]
            return "speech_end"
        return "speech"

    @property
    def has_speech(self) -> bool:
        return self._speech_frames >= self.min_speech_frames


def write_wav(
    path: str | Path,
    pcm: bytes,
    rate: int = PCM_RATE,
    channels: int = PCM_CHANNELS,
) -> Path:
    target = Path(path)
    with wave.open(str(target), "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(PCM_WIDTH)
        handle.setframerate(rate)
        handle.writeframes(pcm)
    return target


def read_wav(path: str | Path) -> tuple[bytes, int]:
    """Return ``(pcm, rate)`` for a mono 16-bit WAV file."""
    with wave.open(str(path), "rb") as handle:
        if handle.getsampwidth() != PCM_WIDTH:
            raise ValueError(f"{path}: only 16-bit WAV is supported")
        if handle.getnchannels() != 1:
            raise ValueError(f"{path}: only mono WAV is supported")
        return handle.readframes(handle.getnframes()), handle.getframerate()


def duration_seconds(pcm: bytes, rate: int = PCM_RATE) -> float:
    return len(pcm) / float(rate * PCM_WIDTH)


class Recorder:
    """Records one utterance from the microphone."""

    def __init__(
        self,
        backend: str = "auto",
        device: str = "",
        rate: int = PCM_RATE,
        command: str = "",
    ) -> None:
        self.rate = rate
        self.device = device
        self.command = command
        self.backend = detect_backend(backend, command)

    def capture(
        self,
        max_seconds: float = 8.0,
        silence_seconds: float = 0.8,
        vad: bool = True,
    ) -> bytes:
        """Record until the speaker stops, or until ``max_seconds``."""
        argv = build_capture_argv(
            self.backend, self.device, self.rate, self.command
        )
        gate = SpeechGate(rate=self.rate, silence_seconds=silence_seconds)
        collected = bytearray()
        deadline = time.monotonic() + max_seconds
        try:
            process = subprocess.Popen(
                argv,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            raise CaptureError(f"cannot start {argv[0]}: {exc}") from exc
        try:
            assert process.stdout is not None
            while True:
                frame = process.stdout.read(gate.frame_bytes)
                if not frame:
                    break
                if not vad:
                    collected += frame
                else:
                    event = gate.push(frame)
                    if event == "speech_end" and gate.has_speech:
                        break
                if time.monotonic() >= deadline:
                    break
        finally:
            process.terminate()
            try:
                code = process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                code = process.wait()
            if process.stdout is not None:
                process.stdout.close()
        # A positive exit code means the backend failed (busy device, missing
        # permission, bad arguments); the SIGTERM we send ourselves is -15.
        if code > 0:
            raise CaptureError(f"{argv[0]} exited with status {code}")
        if not vad:
            return bytes(collected)
        return bytes(gate.utterance)
