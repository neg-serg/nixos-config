"""Rule based command parser for music control (Russian + English).

The parser is intentionally a plain function: ``parse(text) -> Intent``.  It
is the piece of the voice client that can be exercised without any audio at
all, so the whole phrase corpus lives in one ordered table where the most
specific patterns come first ("pause" before "play", "shuffle off" before
"shuffle").
"""

from __future__ import annotations

import re
from dataclasses import dataclass

UNKNOWN = "unknown"

_CYRILLIC = re.compile(r"[а-яё]")
_SPACES = re.compile(r"\s+")
_MINUTES = re.compile(r"мин\w*|minutes?")
# Keep characters that occur in track/album names; everything else becomes a
# space so that "включи альбом «The Mantle»!" normalises cleanly.
_KEEP = re.compile(r"[^\w\s+&./:’'-]", re.UNICODE)
_EDGE = " .-'"
_QUOTES = str.maketrans({"«": " ", "»": " ", "“": " ", "”": " ", "„": " "})

_RU_NUMBERS = {
    "ноль": 0,
    "один": 1,
    "одну": 1,
    "два": 2,
    "две": 2,
    "три": 3,
    "четыре": 4,
    "пять": 5,
    "шесть": 6,
    "семь": 7,
    "восемь": 8,
    "девять": 9,
    "десять": 10,
    "одиннадцать": 11,
    "двенадцать": 12,
    "тринадцать": 13,
    "четырнадцать": 14,
    "пятнадцать": 15,
    "шестнадцать": 16,
    "семнадцать": 17,
    "восемнадцать": 18,
    "девятнадцать": 19,
    "двадцать": 20,
    "двадцать пять": 25,
    "тридцать": 30,
    "сорок": 40,
    "пятьдесят": 50,
    "шестьдесят": 60,
    "семьдесят": 70,
    "восемьдесят": 80,
    "девяносто": 90,
    "сто": 100,
}

_NUMBER_WORDS = "|".join(sorted(_RU_NUMBERS, key=len, reverse=True))

# Word groups shared by several rules.  Every group is wrapped in its own
# non-capturing parentheses so that interpolating one into a larger pattern
# cannot leak a top-level alternation.
_PLAY = r"(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)"
_ADD = r"(?:добавь|add)"
_ALBUM = r"(?:альбом\w*|пластинк\w*|album)"
_ARTIST = r"(?:исполнител\w*|артист\w*|групп\w*|artist|band)"
_TRACK = r"(?:трек\w*|песн\w*|композици\w*|song|track)"
_GENRE = r"(?:жанр\w*|genre)"
_DIR = r"(?:папк\w*|директори\w*|folder|directory)"
_PLAYLIST = r"(?:плейлист\w*|playlist)"
_MUSIC = r"(?:музык\w*|music|треки|tracks|песни|songs)"

# `play_any` with nothing but filler means "just play".
_FILLER = frozenset(
    {
        "музыку",
        "музыка",
        "music",
        "треки",
        "песни",
        "songs",
        "tracks",
        "что-нибудь",
        "что нибудь",
        "какую-нибудь",
        "какую нибудь",
        "что-то",
        "something",
        "anything",
    }
)


@dataclass(frozen=True)
class Intent:
    """One recognised command."""

    name: str
    value: str = ""
    tag: str = ""
    number: int | None = None
    lang: str = "en"
    raw: str = ""

    @property
    def understood(self) -> bool:
        return self.name != UNKNOWN


def normalize(text: str) -> str:
    """Lower-case, drop punctuation and collapse whitespace."""
    text = (text or "").translate(_QUOTES).lower().replace("ё", "е")
    text = _KEEP.sub(" ", text)
    return _SPACES.sub(" ", text).strip()


def language_of(text: str) -> str:
    return "ru" if _CYRILLIC.search(text or "") else "en"


def strip_wake_word(text: str, wake_word: str) -> str:
    """Drop the wake word (and everything before it) from a transcript.

    Returns an empty string when the wake word is required but absent, which
    is how the listener loop ignores background chatter.
    """
    if not wake_word:
        return (text or "").strip()
    pattern = re.compile(
        rf"(?:hey\s+)?{re.escape(wake_word)}[\s,.:;!?-]*",
        re.IGNORECASE,
    )
    match = pattern.search(text or "")
    if match is None:
        return ""
    return (text[: match.start()] + " " + text[match.end() :]).strip()


def _number(token: str | None) -> int | None:
    """Parse digits or a Russian number word ("громкость на двадцать")."""
    if not token:
        return None
    token = _SPACES.sub(" ", token.strip().lower())
    if token.isdigit():
        return int(token)
    if token in _RU_NUMBERS:
        return _RU_NUMBERS[token]
    match = re.fullmatch(r"(\d+)\s+(\d+)", token)
    if match:
        return int(match.group(1)) * 10 + int(match.group(2))
    return None


def _clean_query(value: str) -> str:
    value = re.sub(r"\b(?:мне|пожалуйста|плиз|please|for me)\b", " ", value)
    value = re.sub(r"\b(?:to|in)\s+the\s+queue\b|\bв\s+очередь\b", " ", value)
    value = re.sub(r"^(?:как(?:ую|ой)[- ]нибудь|the|some)\s+", "", value)
    value = re.sub(r"\b(?:музык\w*|music)$", " ", value)
    return value.strip(_EDGE)


RuleSpec = tuple[str, str]

# Ordered rule table.  Named groups `value`, `tag`, `number` and `number2`
# are read out generically in `parse`.
_RULES: list[RuleSpec] = [
    (
        "exit",
        r"(?:выключись|замолчи|хватит слушать|стоп слушай|отключись|"
        r"выйди из режима|stop listening|exit|quit|shut up|goodbye)",
    ),
    (
        "help",
        r"(?:помощь|подсказк\w*|что ты умеешь|какие команды|что можно сказать|"
        r"help|what can you do|commands)",
    ),
    (
        "now_playing",
        r"(?:что (?:сейчас )?играет|что за (?:трек|песн\w*|композици\w*)|"
        r"какой (?:трек|альбом|исполнител\w*) (?:сейчас )?играет|"
        r"текущ\w+ (?:трек|песн\w*|альбом)|what(?:'s| is)? playing|"
        r"what song is this|now playing|current (?:song|track))",
    ),
    (
        "volume_get",
        r"(?:какая (?:сейчас )?громкость|сколько (?:сейчас )?громкости|"
        r"какой уровень громкости|what(?:'s| is) the volume|current volume)",
    ),
    (
        "volume_set",
        rf"(?:громкость|звук|volume)\s*(?:на|=|:)?\s*"
        rf"(?P<number>\d{{1,3}}|{_NUMBER_WORDS})"
        r"\s*(?:%|процент\w*|percent)?\b",
    ),
    (
        "volume_set",
        r"(?:(?:поставь|сделай|установи|set)\s+)?"
        r"(?P<number>\d{1,3})\s*(?:%|процент\w*|percent)\b",
    ),
    (
        "volume_set",
        r"(?:(?:set|change|turn)\s+(?:the\s+)?)?volume\s*(?:to|=)?\s*"
        r"(?P<number>\d{1,3})\b",
    ),
    (
        "volume_up",
        rf"(?:погромче|громче|прибавь(?:\s+(?:громкость|звук|звука))?|"
        rf"увеличь (?:громкость|звук)|сделай громче|"
        rf"volume up|turn (?:it )?up|louder|increase volume)"
        rf"(?:\s+(?:на\s+)?(?P<number>\d{{1,3}}|{_NUMBER_WORDS}))?",
    ),
    (
        "volume_down",
        rf"(?:потише|тише|убавь(?:\s+(?:громкость|звук|звука))?|"
        rf"уменьши (?:громкость|звук)|сделай тише|"
        rf"volume down|turn (?:it )?down|quieter|lower volume)"
        rf"(?:\s+(?:на\s+)?(?P<number>\d{{1,3}}|{_NUMBER_WORDS}))?",
    ),
    (
        "unmute",
        r"(?:включи звук|верни звук|сними мут|отключи мут|unmute)",
    ),
    (
        "mute",
        r"(?:выключи (?:звук|звука)|без звука|мут|mute)"
        r"(?!\s*(?:музык\w*|трек\w*|песн\w*))",
    ),
    (
        "seek_to",
        r"(?:перемотай|промотай|перейти|seek|jump)\s*(?:на\s+|to\s+)?"
        r"(?P<number>\d{1,2}):(?P<number2>\d{1,2})",
    ),
    (
        "seek_to",
        r"(?:перемотай|промотай|seek|jump)\s+(?:в|на)?\s*начало"
        r"|(?:start|beginning)\s+of\s+(?:the\s+)?(?:song|track)",
    ),
    (
        "seek_forward",
        rf"(?:перемотай|промотай|мотай|seek|skip)\s*(?:впер[её]д|forward)?\s*"
        rf"(?:на\s+)?(?:(?P<number>\d{{1,4}}|{_NUMBER_WORDS})\s*)?"
        rf"(?:сек\w*|seconds?|мин\w*|minutes?)",
    ),
    (
        "seek_back",
        rf"(?:отмотай|перемотай|промотай|seek)\s*(?:назад|back)\s*"
        rf"(?:на\s+)?(?:(?P<number>\d{{1,4}}|{_NUMBER_WORDS})\s*)?"
        rf"(?:сек\w*|seconds?|мин\w*|minutes?)",
    ),
    (
        "next",
        r"(?:следующ\w*|дальше|некс\w*|пропусти\w*|смени трек|"
        r"next|skip(?: this)?)",
    ),
    (
        "previous",
        r"(?:предыдущ\w*|верни(?:сь)?(?: назад)?|назад трек|пред\w*|"
        r"previous|prev|go back)",
    ),
    (
        "shuffle_off",
        r"(?:выключи шаффл|выключи перемешивание|не перемешивай|"
        r"убери шаффл|shuffle off|random off|stop shuffling)",
    ),
    (
        "shuffle_on",
        r"(?:перемешай|включи шаффл|включи перемешивание|перемешать|"
        r"случайный порядок|шаффл|shuffle(?: on)?|random(?: on)?|"
        r"play randomly)",
    ),
    (
        "repeat_single",
        r"(?:повторяй (?:один|этот) трек|повтор одного трека|повтор трека|"
        r"repeat one|single track repeat)",
    ),
    (
        "repeat_off",
        r"(?:не повторяй|выключи повтор|останови повтор|"
        r"repeat off|stop repeating|no repeat)",
    ),
    (
        "repeat_on",
        r"(?:повторяй(?: всё| все| альбом)?|включи повтор|повтор|"
        r"repeat(?: all)?(?: on)?|loop(?: on)?)",
    ),
    (
        "consume_toggle",
        r"(?:удаляй (?:проигранное|сыгранное|прослушанное)|"
        r"включи consume|выключи consume|consume)",
    ),
    (
        "list_playlists",
        rf"(?:какие (?:есть )?{_PLAYLIST}|покажи {_PLAYLIST}|"
        rf"список {_PLAYLIST}|list {_PLAYLIST})",
    ),
    (
        "save_playlist",
        rf"(?:сохрани|запиши|save)\s+(?:это\s+|текущ\w+\s+|очередь\s+|"
        rf"queue\s+|as\s+)?{_PLAYLIST}\s+(?P<value>.+)",
    ),
    (
        "play_playlist",
        rf"{_PLAY}\s+(?:мне\s+)?{_PLAYLIST}\s+(?P<value>.+)",
    ),
    (
        # Before add_to_queue/play_any on purpose: "добавь похожие треки"
        # and "включи похожие" would otherwise look like a search query.
        "queue_similar",
        r"(?:похож\w*|similar|more like this)",
    ),
    (
        "add_to_queue",
        rf"{_ADD}\s+(?:в очередь\s+|to (?:the )?queue\s+)?"
        rf"(?:(?P<tag>{_ALBUM}|{_ARTIST}|{_TRACK}|{_GENRE}|{_PLAYLIST})\s+)?"
        rf"(?P<value>.+)",
    ),
    (
        "play_album",
        rf"{_PLAY}\s+(?:мне\s+)?(?:весь\s+|целиком\s+|the whole\s+|entire\s+)?"
        rf"(?:{_ALBUM})\s+(?P<value>.+)",
    ),
    (
        "play_artist",
        rf"{_PLAY}\s+(?:мне\s+)?(?:{_MUSIC}\s+)?(?:{_ARTIST})\s+(?P<value>.+)",
    ),
    (
        "play_genre",
        rf"{_PLAY}\s+(?:мне\s+)?(?:{_MUSIC}\s+)?(?:{_GENRE})\s+(?P<value>.+)",
    ),
    (
        "play_track",
        rf"{_PLAY}\s+(?:мне\s+)?(?:{_TRACK})\s+(?P<value>.+)",
    ),
    (
        "play_directory",
        rf"{_PLAY}\s+(?:мне\s+)?(?:{_DIR})\s+(?P<value>.+)",
    ),
    (
        "clear_queue",
        r"(?:очисти (?:очередь|плейлист|список)|убери всё из очереди|"
        r"удали всё из очереди|clear (?:the )?queue)",
    ),
    (
        "update_library",
        r"(?:обнови (?:базу|библиотеку|медиатеку|коллекцию)|"
        r"пересканируй|rescan|update (?:the )?library|refresh library)",
    ),
    (
        "resume",
        r"(?:сними с паузы|продолж(?:и|ай)|возобнови\w*|"
        r"resume|continue|unpause)",
    ),
    (
        "toggle",
        r"(?:плей пауза|плей или пауза|пауза или плей|toggle(?: pause)?)",
    ),
    (
        "pause",
        r"(?:поставь на паузу|сделай паузу|приостанови\w*|\bпауза\b|pause)",
    ),
    (
        "stop",
        r"(?:стоп|останови\w*|выключи музыку|хватит|stop|halt|be quiet)",
    ),
    (
        "play",
        rf"^(?:включи|играй|запусти|плей|play|вруби)(?:\s+(?:{_MUSIC}))?$",
    ),
    (
        "play_any",
        rf"{_PLAY}\s+(?:мне\s+)?(?P<value>.+)",
    ),
]

# Map a matched tag word to the MPD search tag (used by add_to_queue).
TAG_WORDS: dict[str, str] = {
    "album": "album",
    "артист": "artist",
    "artist": "artist",
    "band": "artist",
    "song": "title",
    "track": "title",
    "genre": "genre",
    "playlist": "playlist",
    "folder": "file",
    "directory": "file",
    "альбом": "album",
    "исполнитель": "artist",
    "артистка": "artist",
    "группа": "artist",
    "песня": "title",
    "песню": "title",
    "трек": "title",
    "композиция": "title",
    "жанр": "genre",
    "папка": "file",
    "плейлист": "playlist",
}


def tag_for_word(word: str) -> str:
    """Resolve a tag word ("album", "артиста") to an MPD tag."""
    word = normalize(word).split(" ")[0] if word else ""
    if not word:
        return ""
    return TAG_WORDS.get(word, "")


# Example phrases for `mpd-voice phrases` and the docs.  The Russian strings
# are command data (the client speaks both languages), not documentation.
EXAMPLES: dict[str, tuple[str, ...]] = {
    "play": ("включи музыку", "play"),
    "pause": ("пауза", "pause"),
    "resume": ("продолжи", "resume"),
    "toggle": ("плей пауза", "toggle"),
    "stop": ("стоп", "stop"),
    "next": ("следующий трек", "next track"),
    "previous": ("предыдущий", "previous"),
    "now_playing": ("что играет", "what is playing"),
    "volume_up": ("громче", "louder"),
    "volume_down": ("тише на 10", "turn it down"),
    "volume_set": ("громкость на 40 процентов", "set volume to 40"),
    "volume_get": ("какая громкость", "what is the volume"),
    "mute": ("выключи звук", "mute"),
    "unmute": ("верни звук", "unmute"),
    "seek_forward": (
        "перемотай вперёд на 30 секунд",
        "skip forward 30 seconds",
    ),
    "seek_back": ("отмотай назад на минуту", "seek back 1 minute"),
    "seek_to": ("перемотай на 1:30", "seek to 1:30"),
    "play_album": ("включи альбом The Mantle", "play album The Mantle"),
    "play_artist": ("включи исполнителя Agalloch", "play artist Agalloch"),
    "play_track": ("включи трек Falling Snow", "play song Falling Snow"),
    "play_genre": ("включи жанр doom metal", "play genre doom metal"),
    "play_directory": ("включи папку Agalloch", "play folder Agalloch"),
    "play_playlist": ("включи плейлист evening", "play playlist evening"),
    "add_to_queue": ("добавь в очередь Agalloch", "add Agalloch to the queue"),
    "queue_similar": ("добавь похожие треки", "more like this"),
    "clear_queue": ("очисти очередь", "clear the queue"),
    "save_playlist": ("сохрани плейлист evening", "save playlist evening"),
    "list_playlists": ("покажи плейлисты", "list playlists"),
    "shuffle_on": ("перемешай", "shuffle"),
    "shuffle_off": ("выключи шаффл", "shuffle off"),
    "repeat_on": ("повторяй", "repeat"),
    "repeat_single": ("повторяй один трек", "repeat one"),
    "repeat_off": ("не повторяй", "repeat off"),
    "consume_toggle": ("включи consume", "consume"),
    "update_library": ("обнови библиотеку", "update the library"),
    "help": ("помощь", "help"),
    "exit": ("хватит слушать", "stop listening"),
}


def parse(text: str) -> Intent:
    """Parse one utterance into an :class:`Intent` (``unknown`` if no match)."""
    raw = text or ""
    normalized = normalize(raw)
    lang = language_of(normalized)
    if not normalized:
        return Intent(name=UNKNOWN, lang=lang, raw=raw)
    for name, pattern in _RULES:
        match = re.search(pattern, normalized)
        if match is None:
            continue
        groups = match.groupdict()
        number = _number(groups.get("number"))
        matched_text = normalized[match.start() : match.end()]
        if name == "seek_to" and groups.get("number2"):
            number = (number or 0) * 60 + int(groups["number2"])
        elif _MINUTES.search(matched_text):
            # "на минуту" -> 60s, "на 2 минуты" -> 120s
            number = (number or 1) * 60
        tag = tag_for_word(groups.get("tag") or "")
        value = _clean_query(groups.get("value") or "")
        if name == "play_any" and (not value or normalize(value) in _FILLER):
            name, value = "play", ""
        return Intent(
            name=name,
            value=value,
            tag=tag,
            number=number,
            lang=lang,
            raw=raw,
        )
    return Intent(name=UNKNOWN, lang=lang, raw=raw)
