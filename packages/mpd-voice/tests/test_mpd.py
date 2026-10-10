"""MPD protocol client tests against the in-process fake daemon."""

from __future__ import annotations

import unittest

from mpd_voice.mpd import (
    MPDClient,
    MPDConnectionError,
    MPDError,
    quote,
    song_dict,
)

from .fake_mpd import FakeMPD


class QuoteTests(unittest.TestCase):
    def test_plain_argument_is_untouched(self) -> None:
        self.assertEqual(quote("Agalloch"), "Agalloch")

    def test_spaces_and_quotes_are_escaped(self) -> None:
        self.assertEqual(quote("The Mantle"), '"The Mantle"')
        self.assertEqual(quote('say "hi"'), '"say \\"hi\\""')
        self.assertEqual(quote(""), '""')


class SongDictTests(unittest.TestCase):
    def test_keys_are_lowercased_and_duplicates_joined(self) -> None:
        song = song_dict([("file", "a.flac"), ("Title", "T"), ("Artist", "A")])
        self.assertEqual(song["title"], "T")
        song = song_dict(
            [("file", "a.flac"), ("Artist", "A"), ("Artist", "B")]
        )
        self.assertEqual(song["artist"], "A, B")


class ClientTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeMPD().start()
        self.addCleanup(self.fake.stop)
        self.client = MPDClient("127.0.0.1", self.fake.port, timeout=5)
        self.addCleanup(self.client.close)

    def test_greeting_and_version(self) -> None:
        self.client.connect()
        self.assertTrue(self.client.version.startswith("0.24"))

    def test_status_and_current_song(self) -> None:
        self.client.add(self.fake.tracks[0]["file"])
        self.client.play(0)
        status = self.client.status()
        self.assertEqual(status["state"], "play")
        self.assertEqual(status["playlistlength"], "1")
        song = self.client.current_song()
        self.assertEqual(song["title"], "Falling Snow")
        self.assertEqual(song["album"], "The Mantle")

    def test_volume_is_clamped(self) -> None:
        self.assertEqual(self.client.set_volume(150), 100)
        self.assertEqual(self.client.volume(), 100)
        self.assertEqual(self.client.adjust_volume(-30), 70)

    def test_playback_transport(self) -> None:
        self.client.add_many([track["file"] for track in self.fake.tracks])
        self.client.play(0)
        self.client.next()
        self.assertEqual(self.client.status()["song"], "1")
        self.client.previous()
        self.assertEqual(self.client.status()["song"], "0")
        self.assertTrue(self.client.toggle_pause())
        self.assertEqual(self.client.status()["state"], "pause")
        self.assertFalse(self.client.toggle_pause())
        self.assertEqual(self.client.status()["state"], "play")
        self.client.stop()
        self.assertEqual(self.client.status()["state"], "stop")

    def test_queue_and_clear(self) -> None:
        self.assertEqual(self.client.queue(), [])
        self.client.clear()
        self.assertEqual(self.client.queue(), [])

    def test_add_many_uses_the_command_list(self) -> None:
        files = [track["file"] for track in self.fake.tracks]
        self.assertEqual(self.client.add_many(files), len(files))
        self.assertEqual(len(self.client.queue()), len(files))
        self.assertEqual(self.fake.command_lists, 1)

    def test_search_and_fallback(self) -> None:
        found = self.client.search("album", "the mantle")
        self.assertEqual(len(found), 2)
        self.assertEqual(found[0]["album"], "The Mantle")
        any_hit = self.client.search_any("antithesis")
        self.assertEqual(len(any_hit), 1)
        self.assertEqual(self.client.search("album", "nope"), [])

    def test_search_rejects_unknown_tags(self) -> None:
        with self.assertRaises(ValueError):
            self.client.search("podcast", "x")

    def test_search_with_quotes_in_needle(self) -> None:
        self.assertEqual(self.client.search("album", 'the "mantle"'), [])

    def test_modes(self) -> None:
        self.assertFalse(self.client.mode("random"))
        self.assertTrue(self.client.flip_mode("random"))
        self.assertTrue(self.client.mode("random"))
        self.assertFalse(self.client.flip_mode("random"))
        self.assertTrue(self.client.set_repeat(True))
        self.assertEqual(self.client.set_crossfade(7), 7)

    def test_playlists(self) -> None:
        self.client.add_many([track["file"] for track in self.fake.tracks[:2]])
        self.client.save_playlist("two")
        self.assertEqual(self.client.playlists(), ["two"])
        self.assertEqual(len(self.client.playlist_songs("two")), 2)
        self.client.clear()
        self.client.load_playlist("two")
        self.assertEqual(len(self.client.queue()), 2)
        self.client.delete_playlist("two")
        self.assertEqual(self.client.playlists(), [])

    def test_update(self) -> None:
        self.client.update()
        self.assertEqual(self.fake.updated, [""])

    def test_ack_becomes_mpd_error(self) -> None:
        with self.assertRaises(MPDError) as caught:
            self.client.play(5)
        self.assertEqual(caught.exception.code, 52)
        self.assertIn("No song loaded", str(caught.exception))

    def test_unreachable_daemon(self) -> None:
        client = MPDClient("127.0.0.1", 1, timeout=0.5)
        with self.assertRaises(MPDConnectionError):
            client.status()

    def test_context_manager_closes(self) -> None:
        client = MPDClient("127.0.0.1", self.fake.port, timeout=5)
        with client:
            self.assertTrue(client.status())
        self.assertIsNone(client._sock)


if __name__ == "__main__":
    unittest.main()
