"""Parser tests: the phrase corpus in both languages."""

from __future__ import annotations

import unittest

from mpd_voice import intents


class ParseTests(unittest.TestCase):
    CASES: tuple[tuple[str, str, str, int | None], ...] = (
        # phrase, intent, value, number
        ("поставь на паузу", "pause", "", None),
        ("pause", "pause", "", None),
        ("продолжи", "resume", "", None),
        ("resume", "resume", "", None),
        ("плей пауза", "toggle", "", None),
        ("стоп", "stop", "", None),
        ("выключи музыку", "stop", "", None),
        ("следующий трек", "next", "", None),
        ("next track", "next", "", None),
        ("предыдущий", "previous", "", None),
        ("previous", "previous", "", None),
        ("громче", "volume_up", "", None),
        ("громче на 15", "volume_up", "", 15),
        ("погромче", "volume_up", "", None),
        ("тише на двадцать", "volume_down", "", 20),
        ("turn it down", "volume_down", "", None),
        ("громкость на 40 процентов", "volume_set", "", 40),
        ("set volume to 35", "volume_set", "", 35),
        ("volume 70", "volume_set", "", 70),
        ("какая громкость", "volume_get", "", None),
        ("what is the volume", "volume_get", "", None),
        ("выключи звук", "mute", "", None),
        ("верни звук", "unmute", "", None),
        ("что играет", "now_playing", "", None),
        ("what is playing", "now_playing", "", None),
        ("перемотай вперёд на 30 секунд", "seek_forward", "", 30),
        ("skip forward 45 seconds", "seek_forward", "", 45),
        ("отмотай назад на 2 минуты", "seek_back", "", 120),
        ("seek back 1 minute", "seek_back", "", 60),
        ("перемотай на 1:30", "seek_to", "", 90),
        ("перемотай в начало", "seek_to", "", None),
        ("включи альбом The Mantle", "play_album", "mantle", None),
        ("play album The Mantle", "play_album", "mantle", None),
        ("включи исполнителя Agalloch", "play_artist", "agalloch", None),
        ("play artist Agalloch", "play_artist", "agalloch", None),
        ("включи трек Falling Snow", "play_track", "falling snow", None),
        ("включи песню Falling Snow", "play_track", "falling snow", None),
        ("включи жанр doom metal", "play_genre", "doom metal", None),
        ("включи папку Agalloch", "play_directory", "agalloch", None),
        ("включи плейлист evening", "play_playlist", "evening", None),
        ("play playlist evening", "play_playlist", "evening", None),
        ("включи музыку", "play", "", None),
        ("включи", "play", "", None),
        ("play", "play", "", None),
        ("включи какую-нибудь музыку", "play", "", None),
        ("добавь в очередь Agalloch", "add_to_queue", "agalloch", None),
        ("добавь альбом The Mantle", "add_to_queue", "mantle", None),
        ("похожие", "queue_similar", "", None),
        ("включи похожие", "queue_similar", "", None),
        ("добавь похожие треки", "queue_similar", "", None),
        ("найди похожие", "queue_similar", "", None),
        ("similar tracks", "queue_similar", "", None),
        ("queue similar", "queue_similar", "", None),
        ("more like this", "queue_similar", "", None),
        ("find similar", "queue_similar", "", None),
        ("очисти очередь", "clear_queue", "", None),
        ("сохрани плейлист evening", "save_playlist", "evening", None),
        ("покажи плейлисты", "list_playlists", "", None),
        ("list playlists", "list_playlists", "", None),
        ("перемешай", "shuffle_on", "", None),
        ("shuffle", "shuffle_on", "", None),
        ("выключи шаффл", "shuffle_off", "", None),
        ("shuffle off", "shuffle_off", "", None),
        ("повторяй", "repeat_on", "", None),
        ("не повторяй", "repeat_off", "", None),
        ("повторяй один трек", "repeat_single", "", None),
        ("repeat one", "repeat_single", "", None),
        ("включи consume", "consume_toggle", "", None),
        ("обнови библиотеку", "update_library", "", None),
        ("help", "help", "", None),
        ("хватит слушать", "exit", "", None),
    )

    def test_phrase_table(self) -> None:
        for phrase, name, value, number in self.CASES:
            with self.subTest(phrase=phrase):
                intent = intents.parse(phrase)
                self.assertEqual(intent.name, name)
                self.assertEqual(intent.value, value)
                self.assertEqual(intent.number, number)

    def test_language_detection(self) -> None:
        self.assertEqual(intents.parse("громче").lang, "ru")
        self.assertEqual(intents.parse("louder").lang, "en")

    def test_unknown_is_not_guessed(self) -> None:
        for phrase in ("расскажи анекдот", "make me a sandwich", ""):
            with self.subTest(phrase=phrase):
                intent = intents.parse(phrase)
                self.assertFalse(intent.understood)
                self.assertEqual(intent.name, intents.UNKNOWN)

    def test_normalisation_strips_case_and_punctuation(self) -> None:
        intent = intents.parse("  Включи альбом «The Mantle»!  ")
        self.assertEqual(intent.name, "play_album")
        self.assertEqual(intent.value, "mantle")

    def test_examples_are_parsed_as_advertised(self) -> None:
        """Every documented example must parse to its own intent name."""
        for name, examples in intents.EXAMPLES.items():
            for phrase in examples:
                with self.subTest(name=name, phrase=phrase):
                    self.assertEqual(intents.parse(phrase).name, name)

    def test_strip_wake_word(self) -> None:
        self.assertEqual(
            intents.strip_wake_word("музыка, следующий трек", "музыка"),
            "следующий трек",
        )
        self.assertEqual(
            intents.strip_wake_word("Hey Music next track", "music"),
            "next track",
        )
        # Without the keyword the utterance is ignored entirely.
        self.assertEqual(
            intents.strip_wake_word("следующий трек", "музыка"), ""
        )

    def test_no_wake_word_keeps_everything(self) -> None:
        self.assertEqual(
            intents.strip_wake_word("  next track  ", ""), "next track"
        )


class PlayMoodTests(unittest.TestCase):
    """Every mood phrase resolves to the canonical Jamendo label."""

    PHRASES: tuple[tuple[str, str], ...] = (
        ("включи мрачное", "dark"),
        ("включи тёмную музыку", "dark"),
        ("тёмное", "dark"),
        ("play dark music", "dark"),
        ("dark", "dark"),
        ("включи грустные песни", "sad"),
        ("включи печальное", "sad"),
        ("play something sad", "sad"),
        ("включи меланхоличное", "melancholic"),
        ("play melancholy", "melancholic"),
        ("включи спокойную музыку", "calm"),
        ("play calm", "calm"),
        ("включи расслабленное", "relaxing"),
        ("play relaxed", "relaxing"),
        ("play relaxing music", "relaxing"),
        ("включи весёлое", "happy"),
        ("включи радостные песни", "happy"),
        ("play happy music", "happy"),
        ("включи эпичное", "epic"),
        ("play epic", "epic"),
        ("включи агрессивное", "heavy"),
        ("включи тяжёлое", "heavy"),
        ("play aggressive music", "heavy"),
        ("play heavy", "heavy"),
        ("включи космическое", "space"),
        ("включи космос", "space"),
        ("play space music", "space"),
        ("play cosmic", "space"),
        ("включи медитативное", "meditative"),
        ("play meditative music", "meditative"),
        ("включи романтичное", "romantic"),
        ("включи романтику", "romantic"),
        ("play romantic music", "romantic"),
        ("добавь грустное", "sad"),
        ("включи что-нибудь мрачное", "dark"),
    )
    LABELS = frozenset(label for _phrase, label in PHRASES)

    def test_phrases_resolve_to_canonical_labels(self) -> None:
        for phrase, label in self.PHRASES:
            with self.subTest(phrase=phrase):
                intent = intents.parse(phrase)
                self.assertEqual(intent.name, "play_mood")
                self.assertEqual(intent.value, label)

    def test_labels_are_jamendo_moodtheme_classes(self) -> None:
        """The tag file stores the model's own label strings verbatim."""
        classes = {
            "action",
            "adventure",
            "advertising",
            "background",
            "ballad",
            "calm",
            "children",
            "christmas",
            "commercial",
            "cool",
            "corporate",
            "dark",
            "deep",
            "documentary",
            "drama",
            "dramatic",
            "dream",
            "emotional",
            "energetic",
            "epic",
            "fast",
            "film",
            "fun",
            "funny",
            "game",
            "groovy",
            "happy",
            "heavy",
            "holiday",
            "hopeful",
            "inspiring",
            "love",
            "meditative",
            "melancholic",
            "melodic",
            "motivational",
            "movie",
            "nature",
            "party",
            "positive",
            "powerful",
            "relaxing",
            "retro",
            "romantic",
            "sad",
            "sexy",
            "slow",
            "soft",
            "soundscape",
            "space",
            "sport",
            "summer",
            "trailer",
            "travel",
            "upbeat",
            "uplifting",
        }
        self.assertEqual(len(classes), 56)
        self.assertTrue(self.LABELS <= classes)

    def test_mood_examples_use_the_labels(self) -> None:
        for phrase in intents.EXAMPLES["play_mood"]:
            with self.subTest(phrase=phrase):
                intent = intents.parse(phrase)
                self.assertEqual(intent.name, "play_mood")
                self.assertIn(intent.value, self.LABELS)

    def test_mood_words_do_not_steal_library_queries(self) -> None:
        cases = (
            ("включи альбом Dark Side of the Moon", "play_album"),
            ("включи трек Dark", "play_track"),
            ("включи папку Space", "play_directory"),
            ("включи исполнителя Happy", "play_artist"),
            ("play album Epic", "play_album"),
            ("включи похожие", "queue_similar"),
            ("добавь в очередь Agalloch", "add_to_queue"),
        )
        for phrase, name in cases:
            with self.subTest(phrase=phrase):
                self.assertEqual(intents.parse(phrase).name, name)


if __name__ == "__main__":
    unittest.main()
