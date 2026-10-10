"""End-to-end tests against a private mpd(1) with a generated library.

Opt in with ``MPD_VOICE_TEST_MPD=1``.  The daemon runs on a spare port with its
own music, database and state directory, so the user's own MPD (and queue) is
never touched.  Skipped when mpd or ffmpeg is unavailable.
"""

from __future__ import annotations

import os
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from mpd_voice.config import Config
from mpd_voice.mpd import MPDClient, MPDConnectionError
from mpd_voice.session import Controller

from . import toolchain

LIBRARY = (
    ("Test Album", "Test Artist", "Doom Metal", ("Track One", "Track Two")),
    ("Other Album", "Other Artist", "Ambient", ("Track Three",)),
)


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@unittest.skipUnless(
    os.environ.get("MPD_VOICE_TEST_MPD"),
    "set MPD_VOICE_TEST_MPD=1 to run against a private mpd instance",
)
class PrivateMpdTests(unittest.TestCase):
    client: MPDClient
    controller: Controller

    @classmethod
    def setUpClass(cls) -> None:
        cls.mpd = toolchain.mpd_binary()
        if not cls.mpd:
            raise unittest.SkipTest("mpd binary not found")
        cls.ffmpeg = toolchain.ffmpeg_binary()
        if not cls.ffmpeg:
            raise unittest.SkipTest("ffmpeg not found")

        cls.root = Path(tempfile.mkdtemp(prefix="mpd-voice-it-"))
        cls.music = cls.root / "music"
        cls.music.mkdir()
        for album, artist, genre, titles in LIBRARY:
            folder = cls.music / album
            folder.mkdir()
            for index, title in enumerate(titles, start=1):
                target = folder / f"{index:02d} {title}.flac"
                subprocess.run(
                    [
                        cls.ffmpeg,
                        "-hide_banner",
                        "-loglevel",
                        "error",
                        "-y",
                        "-f",
                        "lavfi",
                        "-i",
                        "sine=frequency=440:duration=3",
                        "-metadata",
                        f"title={title}",
                        "-metadata",
                        f"artist={artist}",
                        "-metadata",
                        f"album={album}",
                        "-metadata",
                        f"genre={genre}",
                        str(target),
                    ],
                    check=True,
                )

        cls.port = _free_port()
        config = cls.root / "mpd.conf"
        # MPD's config parser wants every value quoted (0.23 and newer).
        config.write_text(
            "\n".join(
                [
                    f'music_directory "{cls.music}"',
                    f'playlist_directory "{cls.root / "playlists"}"',
                    f'db_file "{cls.root / "db"}"',
                    f'state_file "{cls.root / "state"}"',
                    f'log_file "{cls.root / "log"}"',
                    f'pid_file "{cls.root / "pid"}"',
                    'bind_to_address "127.0.0.1"',
                    f'port "{cls.port}"',
                    "audio_output {",
                    '  type "null"',
                    '  name "null"',
                    '  mixer_type "software"',
                    "}",
                    "",
                ]
            )
        )
        (cls.root / "playlists").mkdir()
        cls.process = subprocess.Popen(
            [cls.mpd, "--no-daemon", str(config)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        cls.client = MPDClient("127.0.0.1", cls.port, timeout=5)
        deadline = time.monotonic() + 20
        while True:
            try:
                cls.client.connect()
                break
            except MPDConnectionError:
                if time.monotonic() > deadline:
                    cls._stop_daemon()
                    raise unittest.SkipTest("private mpd did not start")
                time.sleep(0.2)
        cls.client.update()
        while time.monotonic() < deadline:
            if cls.client.search("album", "Test Album"):
                break
            time.sleep(0.3)
        else:
            cls._stop_daemon()
            raise unittest.SkipTest("private mpd did not index the library")
        cls.controller = Controller(cls.client, Config(language="ru"))

    @classmethod
    def _stop_daemon(cls) -> None:
        process = getattr(cls, "process", None)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()

    @classmethod
    def tearDownClass(cls) -> None:
        cls._stop_daemon()
        editor = getattr(cls, "client", None)
        if editor is not None:
            editor.close()
        import shutil

        shutil.rmtree(cls.root, ignore_errors=True)

    def setUp(self) -> None:
        self.controller.client.clear()
        self.client.set_random(False)
        self.client.set_repeat(False)
        self.client.set_single(False)
        self.client.stop()

    # -- library -------------------------------------------------------
    def test_library_is_searchable(self) -> None:
        self.assertEqual(len(self.client.search("album", "Test Album")), 2)
        self.assertEqual(len(self.client.search("artist", "Test Artist")), 2)
        self.assertEqual(len(self.client.search("genre", "Ambient")), 1)
        self.assertTrue(self.client.search_any("Track Three"))

    def test_play_album_through_the_controller(self) -> None:
        reply = self.controller.handle_text("включи альбом Test Album")
        self.assertTrue(reply.ok, reply.text)
        queue = self.client.queue()
        self.assertEqual(len(queue), 2)
        self.assertEqual(self.client.status()["state"], "play")
        self.assertEqual(queue[0]["title"], "Track One")

    def test_transport_through_the_controller(self) -> None:
        self.controller.handle_text("включи альбом Test Album")
        self.assertIn(
            "Track Two", self.controller.handle_text("следующий").text
        )
        self.assertIn(
            "Track One", self.controller.handle_text("предыдущий").text
        )
        self.controller.handle_text("пауза")
        self.assertEqual(self.client.status()["state"], "pause")
        self.controller.handle_text("продолжи")
        self.assertEqual(self.client.status()["state"], "play")
        self.controller.handle_text("стоп")
        self.assertEqual(self.client.status()["state"], "stop")

    def test_volume_through_the_controller(self) -> None:
        self.controller.handle_text("громкость на 30")
        self.assertEqual(self.client.volume(), 30)
        self.controller.handle_text("громче")
        self.assertEqual(self.client.volume(), 35)
        self.controller.handle_text("выключи звук")
        self.assertEqual(self.client.volume(), 0)
        self.controller.handle_text("верни звук")
        self.assertEqual(self.client.volume(), 35)

    def test_modes_through_the_controller(self) -> None:
        self.controller.handle_text("перемешай")
        self.assertEqual(self.client.status()["random"], "1")
        self.controller.handle_text("выключи шаффл")
        self.assertEqual(self.client.status()["random"], "0")
        self.controller.handle_text("повторяй один трек")
        status = self.client.status()
        self.assertEqual(status["single"], "1")
        self.assertEqual(status["repeat"], "1")

    def test_queue_edits_through_the_controller(self) -> None:
        self.controller.handle_text("включи альбом Test Album")
        self.controller.handle_text("добавь в очередь Other Album")
        self.assertEqual(len(self.client.queue()), 3)
        self.controller.handle_text("очисти очередь")
        self.assertEqual(self.client.queue(), [])

    def test_playlist_round_trip(self) -> None:
        self.controller.handle_text("включи альбом Test Album")
        self.controller.handle_text("сохрани плейлист smoke")
        self.assertIn("smoke", self.client.playlists())
        self.controller.handle_text("очисти очередь")
        self.controller.handle_text("включи плейлист smoke")
        self.assertEqual(len(self.client.queue()), 2)
        self.client.delete_playlist("smoke")

    def test_unknown_phrase_changes_nothing(self) -> None:
        self.controller.handle_text("включи альбом Test Album")
        before = self.client.status()
        reply = self.controller.handle_text("расскажи анекдот")
        self.assertFalse(reply.ok)
        self.assertEqual(self.client.status()["state"], before["state"])
        self.assertEqual(len(self.client.queue()), 2)

    def test_now_playing_reports_real_metadata(self) -> None:
        self.controller.handle_text("включи альбом Test Album")
        reply = self.controller.handle_text("что играет")
        self.assertIn("Track One", reply.text)
        self.assertIn("Test Artist", reply.text)
        self.assertIn("Test Album", reply.text)

    def test_missing_album_is_reported(self) -> None:
        reply = self.controller.handle_text(
            "включи альбом Absolutely Not Here"
        )
        self.assertFalse(reply.ok)
        self.assertEqual(self.client.queue(), [])


if __name__ == "__main__":
    unittest.main()
