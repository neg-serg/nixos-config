"""Intent execution tests: phrases become MPD actions and spoken replies."""

from __future__ import annotations

import unittest

from mpd_voice.config import Config
from mpd_voice.mpd import MPDClient
from mpd_voice.session import Controller, describe

from .fake_mpd import FakeMPD


class DescribeTests(unittest.TestCase):
    def test_full_metadata(self) -> None:
        song = {
            "file": "a.flac",
            "title": "Falling Snow",
            "artist": "Agalloch",
            "album": "The Mantle",
            "duration": 545.4,
        }
        self.assertEqual(
            describe(song), "Falling Snow — Agalloch (The Mantle) [9:05]"
        )

    def test_albumartist_and_file_fallback(self) -> None:
        song = {"file": "Evoken/02 - Quietus.flac", "albumartist": "Evoken"}
        self.assertEqual(describe(song), "02 - Quietus — Evoken")

    def test_duration_is_optional(self) -> None:
        self.assertEqual(describe({"title": "X", "file": "x"}), "X")


class ControllerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeMPD().start()
        self.addCleanup(self.fake.stop)
        self.client = MPDClient("127.0.0.1", self.fake.port, timeout=5)
        self.addCleanup(self.client.close)
        self.controller = Controller(self.client, Config(language="ru"))

    def say(self, phrase: str):
        reply = self.controller.handle_text(phrase)
        return reply

    # -- library -------------------------------------------------------
    def test_play_album_replaces_the_queue(self) -> None:
        reply = self.say("включи альбом The Mantle")
        self.assertTrue(reply.ok)
        self.assertIn("The Mantle", reply.text)
        self.assertEqual(len(self.fake.queue), 2)
        self.assertEqual(self.fake.state, "play")
        self.assertEqual(self.fake.position, 0)

    def test_play_artist_and_genre(self) -> None:
        self.assertTrue(self.say("включи исполнителя Evoken").ok)
        self.assertEqual(len(self.fake.queue), 1)
        self.assertTrue(self.say("включи жанр ambient").ok)
        self.assertEqual(len(self.fake.queue), 1)
        self.assertEqual(self.fake.queue[0]["Title"], "Drone One")

    def test_play_track_matches_partial_title(self) -> None:
        reply = self.say("включи трек Falling")
        self.assertTrue(reply.ok)
        self.assertIn("Falling Snow", reply.text)
        self.assertEqual(len(self.fake.queue), 1)

    def test_play_folder(self) -> None:
        self.assertTrue(self.say("включи папку Agalloch").ok)
        self.assertEqual(len(self.fake.queue), 2)

    def test_add_appends_without_starting_playback(self) -> None:
        self.say("включи альбом The Mantle")
        before = len(self.fake.queue)
        reply = self.say("добавь в очередь Evoken")
        self.assertTrue(reply.ok)
        self.assertEqual(len(self.fake.queue), before + 1)
        self.assertEqual(self.fake.state, "play")

    def test_unknown_library_item(self) -> None:
        reply = self.say("включи альбом Nonexistent Album")
        self.assertFalse(reply.ok)
        # The echo is the normalised query (MPD search is case-insensitive).
        self.assertIn("nonexistent album", reply.text.lower())
        self.assertEqual(self.fake.queue, [])

    # -- transport -----------------------------------------------------
    def test_transport_chain(self) -> None:
        self.say("включи альбом The Mantle")
        self.say("пауза")
        self.assertEqual(self.fake.state, "pause")
        self.say("продолжи")
        self.assertEqual(self.fake.state, "play")
        self.say("следующий")
        self.assertEqual(self.fake.position, 1)
        self.say("предыдущий")
        self.assertEqual(self.fake.position, 0)
        self.say("стоп")
        self.assertEqual(self.fake.state, "stop")

    def test_now_playing_mentions_track_and_album(self) -> None:
        self.say("включи альбом The Mantle")
        reply = self.say("что играет")
        self.assertTrue(reply.ok)
        self.assertIn("Falling Snow", reply.text)
        self.assertIn("The Mantle", reply.text)

    def test_now_playing_when_paused(self) -> None:
        self.say("включи альбом The Mantle")
        self.say("пауза")
        self.assertIn("паузе", self.say("что играет").text)

    def test_now_playing_with_empty_queue(self) -> None:
        self.assertIn("ничего", self.say("что играет").text)

    # -- volume --------------------------------------------------------
    def test_volume_steps_and_absolute_values(self) -> None:
        self.assertEqual(self.fake.volume, 50)
        self.assertIn("55", self.say("громче").text)
        self.assertIn("40", self.say("тише на 15").text)
        self.assertIn("80", self.say("громкость на 80 процентов").text)
        self.assertEqual(self.fake.volume, 80)
        self.assertIn("80", self.say("какая громкость").text)

    def test_volume_is_clamped(self) -> None:
        self.say("громкость на 100")
        self.assertIn("100", self.say("громче").text)
        self.assertEqual(self.fake.volume, 100)
        self.say("тише на 200")
        self.assertEqual(self.fake.volume, 0)

    def test_mute_and_unmute_restore_the_level(self) -> None:
        self.say("громкость на 35")
        self.say("выключи звук")
        self.assertEqual(self.fake.volume, 0)
        self.assertIn("35", self.say("верни звук").text)
        self.assertEqual(self.fake.volume, 35)

    def test_volume_without_a_mixer_is_reported(self) -> None:
        self.fake.volume_supported = False
        reply = self.say("громче")
        self.assertFalse(reply.ok)
        self.assertIn("не поддерживает", reply.text)
        self.assertFalse(self.say("какая громкость").ok)
        self.assertFalse(self.say("выключи звук").ok)

    # -- modes ---------------------------------------------------------
    def test_modes(self) -> None:
        self.say("перемешай")
        self.assertEqual(self.fake.modes["random"], 1)
        self.say("выключи шаффл")
        self.assertEqual(self.fake.modes["random"], 0)
        self.say("повторяй")
        self.assertEqual(self.fake.modes["repeat"], 1)
        self.say("не повторяй")
        self.assertEqual(self.fake.modes["repeat"], 0)
        self.say("повторяй один трек")
        self.assertEqual(self.fake.modes["single"], 1)
        self.say("включи consume")
        self.assertEqual(self.fake.modes["consume"], 1)

    def test_seek_translates_to_seconds(self) -> None:
        reply = self.say("перемотай вперёд на 30 секунд")
        self.assertIn("30", reply.text)
        self.assertIn("seekcur +30", self.fake.commands)
        self.say("отмотай назад на 2 минуты")
        self.assertIn("seekcur -120", self.fake.commands)

    # -- queue and playlists -------------------------------------------
    def test_clear_queue(self) -> None:
        self.say("включи альбом The Mantle")
        self.assertTrue(self.say("очисти очередь").ok)
        self.assertEqual(self.fake.queue, [])

    def test_playlist_round_trip(self) -> None:
        self.say("включи альбом The Mantle")
        self.assertTrue(self.say("сохрани плейлист evening").ok)
        self.assertIn("evening", self.say("покажи плейлисты").text)
        self.say("очисти очередь")
        reply = self.say("включи плейлист evening")
        self.assertTrue(reply.ok)
        self.assertEqual(len(self.fake.queue), 2)
        self.assertEqual(self.fake.state, "play")

    def test_missing_playlist_reports_mpd_error(self) -> None:
        reply = self.say("включи плейлист nope")
        self.assertFalse(reply.ok)
        self.assertIn("No such playlist", reply.text)

    def test_empty_playlist_list(self) -> None:
        self.assertIn("Плейлистов нет", self.say("покажи плейлисты").text)

    def test_update_library(self) -> None:
        self.assertTrue(self.say("обнови библиотеку").ok)
        self.assertEqual(self.fake.updated, [""])

    # -- meta ----------------------------------------------------------
    def test_help_and_exit(self) -> None:
        self.assertTrue(self.say("помощь").ok)
        reply = self.say("хватит слушать")
        self.assertTrue(reply.should_exit)

    def test_unknown_command_leaves_mpd_alone(self) -> None:
        before = list(self.fake.commands)
        reply = self.say("расскажи анекдот")
        self.assertFalse(reply.ok)
        self.assertIn("Не понял", reply.text)
        self.assertEqual(self.fake.commands, before)

    def test_language_of_reply_follows_the_phrase(self) -> None:
        self.assertIn("Volume", self.say("volume 30").text)

    def test_offline_daemon_is_reported(self) -> None:
        controller = Controller(
            MPDClient("127.0.0.1", 1, timeout=0.5), Config(language="ru")
        )
        reply = controller.handle_text("что играет")
        self.assertFalse(reply.ok)
        self.assertIn("MPD", reply.text)

    def test_execute_accepts_a_parsed_intent(self) -> None:
        from mpd_voice.intents import parse

        self.assertTrue(self.controller.execute(parse("пауза")).ok)
        self.assertEqual(self.fake.state, "pause")


if __name__ == "__main__":
    unittest.main()
