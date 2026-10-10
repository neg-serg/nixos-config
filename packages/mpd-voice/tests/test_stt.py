"""Speech recognition backend tests against local stubs."""

from __future__ import annotations

import stat
import sys
import tempfile
import unittest
from pathlib import Path

from mpd_voice import stt

from .stub_servers import StubServer


def _script(directory: str, name: str, body: str) -> str:
    path = Path(directory) / name
    path.write_text(f"#!{sys.executable}\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


class CleanTranscriptTests(unittest.TestCase):
    def test_whisper_log_noise_is_dropped(self) -> None:
        raw = (
            "whisper_init_from_file_with_params_no_state: loading\n"
            "ggml_backend_cuda_init: found 1 device\n"
            "[00:00:00.000 --> 00:00:02.000]   hello\n"
            "main: processing audio\n"
            "  next   track\n"
        )
        self.assertEqual(stt.clean_transcript(raw), "hello next track")


class HttpSttTests(unittest.TestCase):
    def setUp(self) -> None:
        self.stub = StubServer()
        self.addCleanup(self.stub.stop)
        self.wav = Path(tempfile.mkdtemp()) / "sample.wav"
        self.wav.write_bytes(b"RIFFfakewav")

    def test_transcribe_posts_multipart(self) -> None:
        backend = stt.HttpSTT(self.stub.base_url, language="ru")
        self.assertEqual(backend.transcribe(self.wav), "next track")
        path, content_type, body = self.stub.requests[0]
        self.assertEqual(path, "/v1/audio/transcriptions")
        self.assertTrue(
            content_type.startswith("multipart/form-data; boundary=")
        )
        self.assertIn(b'name="file"', body)
        self.assertIn(b'filename="sample.wav"', body)
        self.assertIn(b'name="model"', body)
        self.assertIn(b'name="language"', body)
        self.assertIn(b"RIFFfakewav", body)

    def test_language_can_be_forced_per_call(self) -> None:
        backend = stt.HttpSTT(self.stub.base_url, language="ru")
        backend.transcribe(self.wav, language="en")
        self.assertIn(b"\r\n\r\nen\r\n", self.stub.requests[0][2])

    def test_available_probes_models_endpoint(self) -> None:
        self.assertTrue(stt.HttpSTT(self.stub.base_url).available())

    def test_unavailable_when_nothing_listens(self) -> None:
        self.assertFalse(
            stt.HttpSTT("http://127.0.0.1:1", timeout=0.5).available()
        )

    def test_http_error_becomes_stt_error(self) -> None:
        stub = StubServer(status=500, payload=b'{"detail": "no model loaded"}')
        self.addCleanup(stub.stop)
        with self.assertRaises(stt.STTError) as caught:
            stt.HttpSTT(stub.base_url).transcribe(self.wav)
        self.assertIn("500", str(caught.exception))

    def test_plain_text_response_is_accepted(self) -> None:
        stub = StubServer(status=200, payload=b"  stop  ")
        self.addCleanup(stub.stop)
        self.assertEqual(
            stt.HttpSTT(stub.base_url).transcribe(self.wav), "stop"
        )


class CliSttTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.wav = Path(self.tmp) / "in.wav"
        self.wav.write_bytes(b"RIFF")
        self.argv_log = Path(self.tmp) / "argv.txt"

    def test_output_is_cleaned_and_flags_are_passed(self) -> None:
        binary = _script(
            self.tmp,
            "whisper-cli",
            "import sys, pathlib\n"
            f"pathlib.Path({str(self.argv_log)!r}).write_text(' '.join(sys.argv[1:]))\n"
            "print('whisper_init_from_file_with_params_no_state: x')\n"
            "print('  volume   up  ')\n",
        )
        backend = stt.CliSTT(binary, model=str(self.wav), language="en")
        self.assertTrue(backend.available())
        self.assertEqual(backend.transcribe(self.wav), "volume up")
        logged = self.argv_log.read_text()
        self.assertIn("-nt", logged)
        self.assertIn("-np", logged)
        self.assertIn(f"-f {self.wav}", logged)
        self.assertIn("-l en", logged)

    def test_old_whisper_without_np_is_retried(self) -> None:
        binary = _script(
            self.tmp,
            "whisper-cli-old",
            "import sys\n"
            "if '-np' in sys.argv:\n"
            "    print('error: unknown argument: -np', file=sys.stderr)\n"
            "    raise SystemExit(1)\n"
            "print('pause')\n",
        )
        backend = stt.CliSTT(binary, model=str(self.wav), language="en")
        self.assertEqual(backend.transcribe(self.wav), "pause")

    def test_failure_raises(self) -> None:
        binary = _script(
            self.tmp,
            "whisper-cli-broken",
            "import sys\nprint('boom', file=sys.stderr)\nraise SystemExit(2)\n",
        )
        backend = stt.CliSTT(binary, model=str(self.wav))
        with self.assertRaises(stt.STTError):
            backend.transcribe(self.wav)

    def test_missing_binary_is_not_available(self) -> None:
        backend = stt.CliSTT("whisper-cli-not-installed", model=str(self.wav))
        self.assertFalse(backend.available())
        with self.assertRaises(stt.STTError):
            backend.transcribe(self.wav)

    def test_missing_model_is_not_available(self) -> None:
        binary = _script(self.tmp, "whisper-cli", "print('x')\n")
        backend = stt.CliSTT(binary, model="/nope/absent.bin")
        self.assertFalse(backend.available())


class CmdSttTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp()
        self.wav = Path(self.tmp) / "in.wav"
        self.wav.write_bytes(b"RIFF")

    def test_template_gets_wav_and_lang(self) -> None:
        script = _script(
            self.tmp,
            "fake-stt",
            "import sys\nprint('wav=' + sys.argv[1] + ' lang=' + sys.argv[2])\n",
        )
        backend = stt.CmdSTT(
            f"{sys.executable} {script} {{wav}} {{lang}}", "ru"
        )
        text = backend.transcribe(self.wav)
        self.assertEqual(text, f"wav={self.wav} lang=ru")

    def test_missing_template(self) -> None:
        with self.assertRaises(stt.STTError):
            stt.CmdSTT("")

    def test_command_failure_raises(self) -> None:
        script = _script(
            self.tmp, "fake-stt", "import sys\nraise SystemExit(3)\n"
        )
        backend = stt.CmdSTT(f"{sys.executable} {script}")
        with self.assertRaises(stt.STTError):
            backend.transcribe(self.wav)


class FactoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.stub = StubServer()
        self.addCleanup(self.stub.stop)
        self.tmp = tempfile.mkdtemp()
        self.wav = Path(self.tmp) / "in.wav"
        self.wav.write_bytes(b"RIFF")

    def test_none_backend_refuses_to_transcribe(self) -> None:
        backend = stt.build_stt("none")
        self.assertIsInstance(backend, stt.NullSTT)
        with self.assertRaises(stt.STTError):
            backend.transcribe(self.wav)

    def test_explicit_cmd_without_template(self) -> None:
        with self.assertRaises(stt.STTError):
            stt.build_stt("cmd", command="")

    def test_auto_prefers_http(self) -> None:
        backend = stt.build_stt("auto", base_url=self.stub.base_url)
        self.assertIsInstance(backend, stt.HttpSTT)

    def test_auto_falls_back_to_cli(self) -> None:
        binary = _script(self.tmp, "whisper-cli", "print('ok')\n")
        model = Path(self.tmp) / "model.bin"
        model.write_bytes(b"x")
        backend = stt.build_stt(
            "auto",
            base_url="http://127.0.0.1:1",
            binary=binary,
            model=str(model),
        )
        self.assertIsInstance(backend, stt.CliSTT)

    def test_auto_without_any_backend(self) -> None:
        with self.assertRaises(stt.STTError):
            stt.build_stt(
                "auto",
                base_url="http://127.0.0.1:1",
                binary="whisper-cli-absent",
            )


if __name__ == "__main__":
    unittest.main()
