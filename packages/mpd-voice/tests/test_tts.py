"""Text-to-speech backend tests (local command and HTTP + fake player)."""

from __future__ import annotations

import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path

from mpd_voice import tts

from .stub_servers import StubServer

RIFF = b"RIFF\x24\x00\x00\x00WAVEfmt "


def _script(directory: str, name: str, body: str) -> str:
    path = Path(directory) / name
    path.write_text(f"#!{sys.executable}\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


class CmdTtsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.log = Path(self.tmp) / "spoken.txt"

    def _speaker(self) -> str:
        # The fake tool takes the destination from the script itself (never
        # from argv), so a phrase that leaks into the command line cannot
        # create stray files in the working directory.
        script = _script(
            self.tmp,
            "fake-tts",
            "import sys, pathlib\n"
            f"pathlib.Path({str(self.log)!r}).write_text("
            "chr(10).join(sys.argv[1:]))\n",
        )
        return f"{sys.executable} {script} {{text}}"

    def test_text_is_one_argument(self) -> None:
        backend = tts.CmdTTS(self._speaker())
        backend.speak("next track — Falling Snow")
        self.assertEqual(self.log.read_text(), "next track — Falling Snow")
        self.assertEqual(len(self.log.read_text().split("\n")), 1)

    def test_braces_and_quotes_survive(self) -> None:
        backend = tts.CmdTTS(self._speaker())
        backend.speak('volume {value} "40%"')
        self.assertEqual(self.log.read_text(), 'volume {value} "40%"')

    def test_empty_text_does_not_run_anything(self) -> None:
        backend = tts.CmdTTS(self._speaker())
        backend.speak("   ")
        self.assertFalse(self.log.exists())

    def test_failure_raises(self) -> None:
        script = _script(
            self.tmp,
            "broken-tts",
            "import sys\nprint('boom', file=sys.stderr)\nraise SystemExit(1)\n",
        )
        backend = tts.CmdTTS(f"{sys.executable} {script} {{text}}")
        with self.assertRaises(tts.TTSError):
            backend.speak("hello")

    def test_missing_template(self) -> None:
        with self.assertRaises(tts.TTSError):
            tts.CmdTTS("")


class HttpTtsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.stub = StubServer(payload=RIFF)
        self.addCleanup(self.stub.stop)
        self.tmp = tempfile.mkdtemp()
        self.played = Path(self.tmp) / "played.wav"
        self.player = [
            sys.executable,
            _script(
                self.tmp,
                "fake-player",
                "import sys, pathlib\n"
                "pathlib.Path(sys.argv[1]).write_bytes(sys.stdin.buffer.read())\n",
            ),
            str(self.played),
        ]

    def test_speak_posts_json_and_plays_the_audio(self) -> None:
        backend = tts.HttpTTS(
            self.stub.base_url, voice="ru_RU-irina", player=self.player
        )
        backend.speak("следующий трек")
        path, content_type, body = self.stub.requests[0]
        self.assertEqual(path, "/v1/audio/speech")
        self.assertEqual(content_type, "application/json")
        payload = json.loads(body)
        self.assertEqual(payload["input"], "следующий трек")
        self.assertEqual(payload["voice"], "ru_RU-irina")
        self.assertEqual(payload["response_format"], "wav")
        self.assertEqual(self.played.read_bytes(), RIFF)

    def test_available_probes_models(self) -> None:
        self.assertTrue(tts.HttpTTS(self.stub.base_url).available())

    def test_unreachable_endpoint(self) -> None:
        backend = tts.HttpTTS("http://127.0.0.1:1", timeout=0.5)
        self.assertFalse(backend.available())
        with self.assertRaises(tts.TTSError):
            backend.speak("hello")

    def test_http_error_raises(self) -> None:
        stub = StubServer(status=503, payload=b'{"detail": "no voice"}')
        self.addCleanup(stub.stop)
        backend = tts.HttpTTS(stub.base_url, player=self.player)
        with self.assertRaises(tts.TTSError) as caught:
            backend.speak("hello")
        self.assertIn("503", str(caught.exception))

    def test_empty_audio_raises(self) -> None:
        stub = StubServer(payload=b"")
        self.addCleanup(stub.stop)
        backend = tts.HttpTTS(stub.base_url, player=self.player)
        with self.assertRaises(tts.TTSError):
            backend.speak("hello")

    def test_empty_text_makes_no_request(self) -> None:
        backend = tts.HttpTTS(self.stub.base_url, player=self.player)
        backend.speak("")
        self.assertEqual(self.stub.requests, [])


class HelperTests(unittest.TestCase):
    def test_null_backend_is_silent(self) -> None:
        backend = tts.NullTTS()
        self.assertFalse(backend.available())
        self.assertIsNone(backend.speak("anything"))

    def test_default_commands(self) -> None:
        self.assertIn("spd-say", tts.default_command("spd-say"))
        self.assertIn("-v ru", tts.default_command("espeak-ng"))
        self.assertTrue(tts.default_command("say").startswith("say"))

    def test_build_cmd_without_template(self) -> None:
        with self.assertRaises(tts.TTSError):
            tts.build_tts("cmd", command="")

    def test_build_none(self) -> None:
        self.assertIsInstance(tts.build_tts("none"), tts.NullTTS)

    def test_auto_never_raises(self) -> None:
        backend = tts.build_tts("auto", base_url="http://127.0.0.1:1")
        self.assertTrue(hasattr(backend, "speak"))

    def test_local_detection_picks_a_known_tool(self) -> None:
        backend = tts.detect_tts()
        self.assertIn(backend.name, ("cmd", "none"))
        if backend.name == "cmd":
            self.assertTrue(backend.available())


if __name__ == "__main__":
    unittest.main()
