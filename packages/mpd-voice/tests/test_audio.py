"""Capture, VAD and WAV helper tests (no microphone required)."""

from __future__ import annotations

import array
import math
import stat
import sys
import tempfile
import unittest
from pathlib import Path

from mpd_voice import audio


def tone(seconds: float, freq: int = 440, amplitude: int = 8000) -> bytes:
    frames = int(seconds * audio.PCM_RATE)
    samples = array.array(
        "h",
        (
            int(amplitude * math.sin(2 * math.pi * freq * i / audio.PCM_RATE))
            for i in range(frames)
        ),
    )
    return samples.tobytes()


def silence(seconds: float) -> bytes:
    return b"\x00\x00" * int(seconds * audio.PCM_RATE)


def _script(directory: str, name: str, body: str) -> str:
    path = Path(directory) / name
    path.write_text(f"#!{sys.executable}\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


class RmsTests(unittest.TestCase):
    def test_silence_is_zero(self) -> None:
        self.assertEqual(audio.rms(silence(0.03)), 0.0)

    def test_tone_is_loud(self) -> None:
        self.assertGreater(audio.rms(tone(0.03)), 5000)

    def test_odd_frames_do_not_crash(self) -> None:
        self.assertEqual(audio.rms(b"\x01"), 0.0)


class SpeechGateTests(unittest.TestCase):
    def _frames(self, pcm: bytes) -> list[bytes]:
        gate = audio.SpeechGate(silence_seconds=0.6)
        return [
            pcm[offset : offset + gate.frame_bytes]
            for offset in range(0, len(pcm), gate.frame_bytes)
        ]

    def test_events_follow_speech_then_silence(self) -> None:
        gate = audio.SpeechGate(silence_seconds=0.6)
        events = []
        for frame in self._frames(silence(0.3) + tone(0.6) + silence(1.2)):
            events.append(gate.push(frame))
        self.assertEqual(events[0], "idle")
        self.assertIn("speech_start", events)
        self.assertIn("speech_end", events)
        # After the utterance ends the gate returns to idle for the tail.
        self.assertEqual(events[-1], "idle")
        self.assertTrue(gate.has_speech)
        self.assertGreaterEqual(gate.speech_seconds, 0.3)

    def test_utterance_is_shorter_than_the_recording(self) -> None:
        gate = audio.SpeechGate(silence_seconds=0.6)
        pcm = silence(1.0) + tone(0.5) + silence(1.5)
        for frame in self._frames(pcm):
            gate.push(frame)
        self.assertGreater(len(gate.utterance), 0)
        self.assertLess(len(gate.utterance), len(pcm))

    def test_pure_silence_never_triggers(self) -> None:
        gate = audio.SpeechGate(silence_seconds=0.6)
        for frame in self._frames(silence(1.5)):
            self.assertEqual(gate.push(frame), "idle")
        self.assertFalse(gate.has_speech)


class WavTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        pcm = tone(0.2)
        with tempfile.TemporaryDirectory() as tmp:
            path = audio.write_wav(Path(tmp) / "a.wav", pcm)
            data, rate = audio.read_wav(path)
        self.assertEqual(rate, audio.PCM_RATE)
        self.assertEqual(data, pcm)

    def test_duration(self) -> None:
        self.assertAlmostEqual(
            audio.duration_seconds(tone(0.5)), 0.5, places=2
        )

    def test_stereo_is_rejected(self) -> None:
        import wave

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "stereo.wav"
            with wave.open(str(path), "wb") as handle:
                handle.setnchannels(2)
                handle.setsampwidth(2)
                handle.setframerate(audio.PCM_RATE)
                handle.writeframes(tone(0.1))
            with self.assertRaises(ValueError):
                audio.read_wav(path)


class BackendTests(unittest.TestCase):
    def test_argv_layouts(self) -> None:
        self.assertEqual(build_first("pw-record"), "pw-record")
        self.assertEqual(build_first("arecord"), "arecord")
        self.assertEqual(build_first("ffmpeg"), "ffmpeg")
        self.assertEqual(build_first("sox"), "sox")

    def test_device_is_passed_through(self) -> None:
        argv = audio.build_capture_argv("arecord", device="hw:1,0")
        self.assertIn("hw:1,0", argv)
        argv = audio.build_capture_argv("pw-record", device="mic")
        self.assertIn("mic", argv)

    def test_cmd_backend_requires_a_template(self) -> None:
        with self.assertRaises(audio.CaptureError):
            audio.build_capture_argv("cmd")
        argv = audio.build_capture_argv(
            "cmd", command=f"{sys.executable} -c pass"
        )
        self.assertEqual(argv, [sys.executable, "-c", "pass"])

    def test_unknown_backend(self) -> None:
        with self.assertRaises(audio.CaptureError):
            audio.build_capture_argv("nope")

    def test_detect_preferred_missing(self) -> None:
        with self.assertRaises(audio.CaptureError):
            audio.detect_backend("nope")

    def test_detect_cmd_without_command(self) -> None:
        with self.assertRaises(audio.CaptureError):
            audio.detect_backend("cmd")


def build_first(backend: str) -> str:
    return audio.build_capture_argv(backend)[0]


class RecorderTests(unittest.TestCase):
    def test_recorder_trims_silence(self) -> None:
        full = silence(0.5) + tone(0.6) + silence(1.5)
        with tempfile.TemporaryDirectory() as tmp:
            script = _script(
                tmp,
                "fake-capture",
                "import sys\n"
                "sys.stdout.buffer.write(bytes.fromhex('{hex}'))\n"
                "sys.stdout.flush()\n".format(hex=full.hex()),
            )
            recorder = audio.Recorder(
                "cmd", command=f"{sys.executable} {script}"
            )
            captured = recorder.capture(max_seconds=10, silence_seconds=0.6)
        self.assertGreater(len(captured), 0)
        self.assertLess(len(captured), len(full))
        self.assertGreater(audio.rms(captured), 1000)

    def test_recorder_without_vad_returns_everything(self) -> None:
        full = silence(0.2) + tone(0.2)
        with tempfile.TemporaryDirectory() as tmp:
            script = _script(
                tmp,
                "fake-capture",
                "import sys\n"
                "sys.stdout.buffer.write(bytes.fromhex('{hex}'))\n"
                "sys.stdout.flush()\n".format(hex=full.hex()),
            )
            recorder = audio.Recorder(
                "cmd", command=f"{sys.executable} {script}"
            )
            captured = recorder.capture(max_seconds=5, vad=False)
        self.assertEqual(captured, full)

    def test_recorder_reports_failure(self) -> None:
        recorder = audio.Recorder(
            "cmd", command=f"{sys.executable} -c 'raise SystemExit(1)'"
        )
        with self.assertRaises(audio.CaptureError):
            recorder.capture(max_seconds=1)

    def test_recorder_reports_missing_binary(self) -> None:
        recorder = audio.Recorder("cmd", command="definitely-not-a-binary-xyz")
        with self.assertRaises(audio.CaptureError):
            recorder.capture(max_seconds=1)


if __name__ == "__main__":
    unittest.main()
