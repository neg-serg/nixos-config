"""Voice round trip without a human speaker.

Synthesises the phrase with espeak-ng, transcribes it with whisper.cpp and
feeds the transcript through the parser and the controller.  Opt in with
``MPD_VOICE_E2E=1``; the model can be pointed at with
``MPD_VOICE_WHISPER_MODEL`` (defaults to the speech stack's
``ggml-large-v3-turbo`` model).
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from mpd_voice import stt
from mpd_voice.config import Config
from mpd_voice.intents import parse
from mpd_voice.mpd import MPDClient
from mpd_voice.session import Controller

from . import toolchain
from .fake_mpd import FakeMPD

# Verified pairs: the synthesised audio of these phrases transcribes into a
# phrase the parser maps to the expected intent.  English is included because
# espeak-ng's robotic voice is what the recogniser struggles with, not human
# speech; a real speaker is far easier for whisper.cpp.
PHRASES = (
    ("en", "pause", "pause"),
    ("en", "next track", "next"),
    ("en", "volume up", "volume_up"),
    ("en", "shuffle", "shuffle_on"),
    ("en", "what is playing", "now_playing"),
    ("ru", "пауза", "pause"),
)


@unittest.skipUnless(
    os.environ.get("MPD_VOICE_E2E"),
    "set MPD_VOICE_E2E=1 to synthesise audio and run whisper.cpp",
)
class VoiceRoundTripTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.espeak = toolchain.espeak_binary()
        cls.whisper = toolchain.whisper_cli()
        cls.model = toolchain.whisper_model()
        if not (cls.espeak and cls.whisper and cls.model):
            raise unittest.SkipTest(
                "espeak-ng, whisper-cli and a ggml model are required"
            )
        cls.tmp = Path(tempfile.mkdtemp(prefix="mpd-voice-e2e-"))
        cls.transcriber = stt.CliSTT(
            cls.whisper, model=cls.model, language="en", timeout=300
        )

    @classmethod
    def tearDownClass(cls) -> None:
        import shutil

        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def synthesize_and_transcribe(cls, lang: str, phrase: str) -> str:
        wav = cls.tmp / f"{lang}-{abs(hash(phrase))}.wav"
        subprocess.run(
            [
                cls.espeak,
                "-v",
                lang,
                "-s",
                "150",
                "-w",
                str(wav),
                phrase,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return cls.transcriber.transcribe(wav, language=lang)

    def test_transcripts_parse_into_intents(self) -> None:
        for lang, phrase, expected in PHRASES:
            with self.subTest(phrase=phrase):
                transcript = self.synthesize_and_transcribe(lang, phrase)
                intent = parse(transcript)
                self.assertEqual(
                    intent.name,
                    expected,
                    f"{phrase!r} transcribed as {transcript!r}",
                )

    def test_voice_command_reaches_mpd(self) -> None:
        """The whole chain: audio -> transcript -> intent -> MPD action."""
        fake = FakeMPD().start()
        self.addCleanup(fake.stop)
        client = MPDClient("127.0.0.1", fake.port, timeout=5)
        self.addCleanup(client.close)
        controller = Controller(client, Config(language="en"))
        client.add_many([track["file"] for track in fake.tracks])
        client.play(0)

        transcript = self.synthesize_and_transcribe("en", "volume up")
        reply = controller.handle_text(transcript)
        self.assertTrue(reply.ok, transcript)
        self.assertEqual(fake.volume, 55, transcript)

        transcript = self.synthesize_and_transcribe("en", "next track")
        controller.handle_text(transcript)
        self.assertEqual(fake.position, 1, transcript)

        transcript = self.synthesize_and_transcribe("en", "pause")
        controller.handle_text(transcript)
        self.assertEqual(fake.state, "pause", transcript)


if __name__ == "__main__":
    unittest.main()
