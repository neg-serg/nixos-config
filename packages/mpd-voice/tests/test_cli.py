"""CLI tests: exit codes, config wiring and the file-driven voice pipeline."""

from __future__ import annotations

import contextlib
import io
import json
import stat
import sys
import tempfile
import unittest
from pathlib import Path

from mpd_voice import cli
from mpd_voice import audio

from .fake_mpd import FakeMPD


def run_cli(args: list[str]) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = cli.main(args)
    return code, out.getvalue(), err.getvalue()


def _script(directory: str, name: str, body: str) -> str:
    path = Path(directory) / name
    path.write_text(f"#!{sys.executable}\n{body}\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeMPD().start()
        self.addCleanup(self.fake.stop)
        self.conn = ["--host", "127.0.0.1", "--port", str(self.fake.port)]
        self.tmp = tempfile.mkdtemp()

    def wav(self) -> str:
        path = Path(self.tmp) / "speech.wav"
        audio.write_wav(path, b"\x00\x00" * 8000, audio.PCM_RATE)
        return str(path)

    def test_dry_run_prints_the_intent(self) -> None:
        code, out, _ = run_cli(["say", "--dry-run", "next", "track"])
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["name"], "next")
        self.assertTrue(payload["understood"])

    def test_dry_run_unknown_phrase(self) -> None:
        code, out, _ = run_cli(["say", "--dry-run", "make me a sandwich"])
        self.assertEqual(code, cli.EXIT_UNKNOWN)
        self.assertFalse(json.loads(out)["understood"])

    def test_parse_subcommand(self) -> None:
        code, out, _ = run_cli(["parse", "volume", "40"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["number"], 40)

    def test_phrases_lists_the_corpus(self) -> None:
        code, out, _ = run_cli(["phrases"])
        self.assertEqual(code, 0)
        self.assertIn("volume_set", out)
        self.assertIn("play_album", out)

    def test_say_executes_against_mpd(self) -> None:
        code, out, _ = run_cli(["say", *self.conn, "включи альбом The Mantle"])
        self.assertEqual(code, 0)
        self.assertIn("The Mantle", out)
        self.assertEqual(len(self.fake.queue), 2)

    def test_say_unknown_phrase_exit_code(self) -> None:
        code, out, _ = run_cli(["say", *self.conn, "расскажи анекдот"])
        self.assertEqual(code, cli.EXIT_UNKNOWN)
        self.assertEqual(self.fake.commands, [])

    def test_status_json_matches_mpd(self) -> None:
        run_cli(["say", *self.conn, "включи трек Falling"]).count
        code, out, _ = run_cli(["status", "--json", *self.conn])
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["song"]["title"], "Falling Snow")
        self.assertEqual(payload["status"]["state"], "play")

    def test_status_when_stopped(self) -> None:
        code, out, _ = run_cli(["status", *self.conn])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "stopped")

    def test_doctor_reports_mpd(self) -> None:
        code, out, _ = run_cli(["doctor", *self.conn])
        self.assertEqual(code, 0)
        self.assertIn("mpd       ok", out)
        self.assertIn("capture", out)

    def test_doctor_fails_without_mpd(self) -> None:
        code, out, _ = run_cli(
            ["doctor", "--host", "127.0.0.1", "--port", "1"]
        )
        self.assertEqual(code, cli.EXIT_ERROR)
        self.assertIn("mpd       FAIL", out)

    def test_config_file_sets_the_language(self) -> None:
        path = Path(self.tmp) / "config.toml"
        path.write_text('[mpd-voice]\nlanguage = "en"\n')
        code, out, _ = run_cli(
            ["say", *self.conn, "--config", str(path), "volume 30"]
        )
        self.assertEqual(code, 0)
        self.assertIn("Volume", out)

    def test_command_line_overrides_the_config_file(self) -> None:
        path = Path(self.tmp) / "config.toml"
        path.write_text('[mpd-voice]\nlanguage = "ru"\n')
        code, out, _ = run_cli(
            [
                "say",
                *self.conn,
                "--config",
                str(path),
                "--lang",
                "en",
                "volume 30",
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("Volume", out)

    def test_once_transcribes_a_wav_and_acts(self) -> None:
        script = _script(
            self.tmp, "fake-stt", "import sys\nprint('next track')\n"
        )
        code, out, _ = run_cli(
            [
                "once",
                *self.conn,
                "--input-wav",
                self.wav(),
                "--stt",
                "cmd",
                "--stt-cmd",
                f"{sys.executable} {script} {{wav}}",
                "--tts",
                "none",
                "--verbose",
            ]
        )
        self.assertEqual(code, 0)
        self.assertIn("next track", out)
        self.assertIn("next", self.fake.commands)

    def test_listen_once_with_wake_word_ignores_other_speech(self) -> None:
        script = _script(
            self.tmp,
            "fake-stt",
            "import sys\nprint('next track')\n",
        )
        code, _, _ = run_cli(
            [
                "listen",
                "--once",
                *self.conn,
                "--input-wav",
                self.wav(),
                "--wake-word",
                "music",
                "--stt",
                "cmd",
                "--stt-cmd",
                f"{sys.executable} {script} {{wav}}",
                "--tts",
                "none",
            ]
        )
        # The transcribed phrase has no wake word, so nothing may happen and
        # the run reports "nothing executed" instead of guessing.
        self.assertEqual(code, cli.EXIT_UNKNOWN)
        self.assertEqual(self.fake.commands, [])

    def test_listen_without_stt_backend_fails_cleanly(self) -> None:
        code, _, err = run_cli(
            [
                "once",
                *self.conn,
                "--input-wav",
                self.wav(),
                "--stt",
                "cmd",
                "--stt-cmd",
                "definitely-not-a-binary-xyz {wav}",
            ]
        )
        self.assertEqual(code, cli.EXIT_ERROR)
        self.assertIn("stt", err)


if __name__ == "__main__":
    unittest.main()
