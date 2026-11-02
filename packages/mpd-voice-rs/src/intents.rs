//! Rule based command parser for music control (Russian + English).
//!
//! Port of `mpd_voice/intents.py`. The phrase table is generated from the
//! Python module (same order, same patterns), so the two parsers cannot drift:
//! the most specific rules come first (`pause` before `play`, `shuffle off`
//! before `shuffle`).
//!
//! One construct lives outside the pattern table: the `mute` rule's negative
//! lookahead. The engine has no lookaround, so `parse` checks the tail
//! explicitly and resumes the search when it fails — what the Python regex
//! would do by retrying at later positions.

use crate::rex::Regex;

pub const UNKNOWN: &str = "unknown";

/// Spoken mood words -> canonical Jamendo mood/theme labels.
///
/// The tag file stores the model's own label strings verbatim, so the
/// right-hand side must stay exactly as the model emits them. Patterns are
/// matched against normalised text (lower case, "ё" already folded to "е").
pub const MOOD_WORDS: [(&str, &str); 17] = [
    ("dark", "мрачн\\w*|т[её]мн\\w*|dark"),
    ("sad", "грустн\\w*|печальн\\w*|sad"),
    ("melancholic", "меланхол\\w*|melancholy|melancholic"),
    ("calm", "спокойн\\w*|calm"),
    ("relaxing", "расслаб\\w*|relaxed|relaxing"),
    ("happy", "вес[её]л\\w*|радостн\\w*|happy"),
    ("epic", "эпичн\\w*|эпик\\w*|epic"),
    ("heavy", "агрессивн\\w*|тяж[её]л\\w*|aggressive|heavy"),
    ("space", "космич\\w*|космос\\w*|space|cosmic"),
    (
        "meditative",
        "медитативн\\w*|медитаци\\w*|meditative|meditation",
    ),
    ("romantic", "романтичн\\w*|романтик\\w*|romantic"),
    ("energetic", "энергичн\\w*|energetic"),
    ("positive", "позитивн\\w*|positive"),
    ("hopeful", "надежд\\w*|hopeful"),
    ("uplifting", "воодушевля\\w*|uplifting"),
    ("groovy", "грув\\w*|groovy"),
    ("upbeat", "upbeat"),
];

/// Ordered rule table: intent name plus pattern (`mute` without its lookahead).
pub const RULES: [(&str, &str); 43] = [
    ("exit", "(?:выключись|замолчи|хватит слушать|стоп слушай|отключись|выйди из режима|stop listening|exit|quit|shut up|goodbye)"),
    ("help", "(?:помощь|подсказк\\w*|что ты умеешь|какие команды|что можно сказать|help|what can you do|commands)"),
    ("describe_track", "(?:что (?:это|там) за (?:трек|песн\\w*|композици\\w*)|опиши (?:этот |текущ\\w+ )?(?:трек|песн\\w*|композици\\w*|музыку)|расскажи (?:про|о) (?:этот |текущ\\w+ )?(?:трек|песн\\w*|композици\\w*)|describe (?:this |the )?(?:track|song)|tell me about (?:this|the) (?:track|song))"),
    ("now_playing", "(?:что (?:сейчас )?играет|что за (?:трек|песн\\w*|композици\\w*)|какой (?:трек|альбом|исполнител\\w*) (?:сейчас )?играет|текущ\\w+ (?:трек|песн\\w*|альбом)|what(?:'s| is)? playing|what song is this|now playing|current (?:song|track))"),
    ("volume_get", "(?:какая (?:сейчас )?громкость|сколько (?:сейчас )?громкости|какой уровень громкости|what(?:'s| is) the volume|current volume)"),
    ("volume_set", "(?:громкость|звук|volume)\\s*(?:на|=|:)?\\s*(?P<number>\\d{1,3}|двадцать пять|четырнадцать|восемнадцать|девятнадцать|одиннадцать|шестнадцать|восемьдесят|двенадцать|тринадцать|пятнадцать|семнадцать|шестьдесят|пятьдесят|семьдесят|девяносто|двадцать|тридцать|четыре|восемь|девять|десять|шесть|сорок|ноль|один|одну|пять|семь|два|две|три|сто)\\s*(?:%|процент\\w*|percent)?\\b"),
    ("volume_set", "(?:(?:поставь|сделай|установи|set)\\s+)?(?P<number>\\d{1,3})\\s*(?:%|процент\\w*|percent)\\b"),
    ("volume_set", "(?:(?:set|change|turn)\\s+(?:the\\s+)?)?volume\\s*(?:to|=)?\\s*(?P<number>\\d{1,3})\\b"),
    ("volume_up", "(?:погромче|громче|прибавь(?:\\s+(?:громкость|звук|звука))?|увеличь (?:громкость|звук)|сделай громче|volume up|turn (?:it )?up|louder|increase volume)(?:\\s+(?:на\\s+)?(?P<number>\\d{1,3}|двадцать пять|четырнадцать|восемнадцать|девятнадцать|одиннадцать|шестнадцать|восемьдесят|двенадцать|тринадцать|пятнадцать|семнадцать|шестьдесят|пятьдесят|семьдесят|девяносто|двадцать|тридцать|четыре|восемь|девять|десять|шесть|сорок|ноль|один|одну|пять|семь|два|две|три|сто))?"),
    ("volume_down", "(?:потише|тише|убавь(?:\\s+(?:громкость|звук|звука))?|уменьши (?:громкость|звук)|сделай тише|volume down|turn (?:it )?down|quieter|lower volume)(?:\\s+(?:на\\s+)?(?P<number>\\d{1,3}|двадцать пять|четырнадцать|восемнадцать|девятнадцать|одиннадцать|шестнадцать|восемьдесят|двенадцать|тринадцать|пятнадцать|семнадцать|шестьдесят|пятьдесят|семьдесят|девяносто|двадцать|тридцать|четыре|восемь|девять|десять|шесть|сорок|ноль|один|одну|пять|семь|два|две|три|сто))?"),
    ("unmute", "(?:включи звук|верни звук|сними мут|отключи мут|unmute)"),
    ("mute", "(?:выключи (?:звук|звука)|без звука|мут|mute)"),
    ("seek_to", "(?:перемотай|промотай|перейти|seek|jump)\\s*(?:на\\s+|to\\s+)?(?P<number>\\d{1,2}):(?P<number2>\\d{1,2})"),
    ("seek_to", "(?:перемотай|промотай|seek|jump)\\s+(?:в|на)?\\s*начало|(?:start|beginning)\\s+of\\s+(?:the\\s+)?(?:song|track)"),
    ("seek_forward", "(?:перемотай|промотай|мотай|seek|skip)\\s*(?:впер[её]д|forward)?\\s*(?:на\\s+)?(?:(?P<number>\\d{1,4}|двадцать пять|четырнадцать|восемнадцать|девятнадцать|одиннадцать|шестнадцать|восемьдесят|двенадцать|тринадцать|пятнадцать|семнадцать|шестьдесят|пятьдесят|семьдесят|девяносто|двадцать|тридцать|четыре|восемь|девять|десять|шесть|сорок|ноль|один|одну|пять|семь|два|две|три|сто)\\s*)?(?:сек\\w*|seconds?|мин\\w*|minutes?)"),
    ("seek_back", "(?:отмотай|перемотай|промотай|seek)\\s*(?:назад|back)\\s*(?:на\\s+)?(?:(?P<number>\\d{1,4}|двадцать пять|четырнадцать|восемнадцать|девятнадцать|одиннадцать|шестнадцать|восемьдесят|двенадцать|тринадцать|пятнадцать|семнадцать|шестьдесят|пятьдесят|семьдесят|девяносто|двадцать|тридцать|четыре|восемь|девять|десять|шесть|сорок|ноль|один|одну|пять|семь|два|две|три|сто)\\s*)?(?:сек\\w*|seconds?|мин\\w*|minutes?)"),
    ("next", "(?:следующ\\w*|дальше|некс\\w*|пропусти\\w*|смени трек|next|skip(?: this)?)"),
    ("previous", "(?:предыдущ\\w*|верни(?:сь)?(?: назад)?|назад трек|пред\\w*|previous|prev|go back)"),
    ("shuffle_off", "(?:выключи шаффл|выключи перемешивание|не перемешивай|убери шаффл|shuffle off|random off|stop shuffling)"),
    ("shuffle_on", "(?:перемешай|включи шаффл|включи перемешивание|перемешать|случайный порядок|шаффл|shuffle(?: on)?|random(?: on)?|play randomly)"),
    ("repeat_single", "(?:повторяй (?:один|этот) трек|повтор одного трека|повтор трека|repeat one|single track repeat)"),
    ("repeat_off", "(?:не повторяй|выключи повтор|останови повтор|repeat off|stop repeating|no repeat)"),
    ("repeat_on", "(?:повторяй(?: всё| все| альбом)?|включи повтор|повтор|repeat(?: all)?(?: on)?|loop(?: on)?)"),
    ("consume_toggle", "(?:удаляй (?:проигранное|сыгранное|прослушанное)|включи consume|выключи consume|consume)"),
    ("list_playlists", "(?:какие (?:есть )?(?:плейлист\\w*|playlist)|покажи (?:плейлист\\w*|playlist)|список (?:плейлист\\w*|playlist)|list (?:плейлист\\w*|playlist))"),
    ("save_playlist", "(?:сохрани|запиши|save)\\s+(?:это\\s+|текущ\\w+\\s+|очередь\\s+|queue\\s+|as\\s+)?(?:плейлист\\w*|playlist)\\s+(?P<value>.+)"),
    ("play_playlist", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:плейлист\\w*|playlist)\\s+(?P<value>.+)"),
    ("queue_similar", "(?:похож\\w*|similar|more like this)"),
    ("play_mood", "^(?:(?:(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)|(?:добавь|add))\\s+)?(?:мне\\s+|please\\s+)?(?:(?:что-нибудь|что нибудь|какую-нибудь|какую нибудь|some|something|any)\\s+)?(?P<value>(?:мрачн\\w*|т[её]мн\\w*|dark)|(?:грустн\\w*|печальн\\w*|sad)|(?:меланхол\\w*|melancholy|melancholic)|(?:спокойн\\w*|calm)|(?:расслаб\\w*|relaxed|relaxing)|(?:вес[её]л\\w*|радостн\\w*|happy)|(?:эпичн\\w*|эпик\\w*|epic)|(?:агрессивн\\w*|тяж[её]л\\w*|aggressive|heavy)|(?:космич\\w*|космос\\w*|space|cosmic)|(?:медитативн\\w*|медитаци\\w*|meditative|meditation)|(?:романтичн\\w*|романтик\\w*|romantic)|(?:энергичн\\w*|energetic)|(?:позитивн\\w*|positive)|(?:надежд\\w*|hopeful)|(?:воодушевля\\w*|uplifting)|(?:грув\\w*|groovy)|(?:upbeat))(?:\\s+(?:(?:музык\\w*|music|треки|tracks|песни|songs)|(?:трек\\w*|песн\\w*|композици\\w*|song|track)))?$"),
    ("add_to_queue", "(?:добавь|add)\\s+(?:в очередь\\s+|to (?:the )?queue\\s+)?(?:(?P<tag>(?:альбом\\w*|пластинк\\w*|album)|(?:исполнител\\w*|артист\\w*|групп\\w*|artist|band)|(?:трек\\w*|песн\\w*|композици\\w*|song|track)|(?:жанр\\w*|genre)|(?:плейлист\\w*|playlist))\\s+)?(?P<value>.+)"),
    ("play_album", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:весь\\s+|целиком\\s+|the whole\\s+|entire\\s+)?(?:(?:альбом\\w*|пластинк\\w*|album))\\s+(?P<value>.+)"),
    ("play_artist", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:(?:музык\\w*|music|треки|tracks|песни|songs)\\s+)?(?:(?:исполнител\\w*|артист\\w*|групп\\w*|artist|band))\\s+(?P<value>.+)"),
    ("play_genre", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:(?:музык\\w*|music|треки|tracks|песни|songs)\\s+)?(?:(?:жанр\\w*|genre))\\s+(?P<value>.+)"),
    ("play_track", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:(?:трек\\w*|песн\\w*|композици\\w*|song|track))\\s+(?P<value>.+)"),
    ("play_directory", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?:(?:папк\\w*|директори\\w*|folder|directory))\\s+(?P<value>.+)"),
    ("clear_queue", "(?:очисти (?:очередь|плейлист|список)|убери всё из очереди|удали всё из очереди|clear (?:the )?queue)"),
    ("update_library", "(?:обнови (?:базу|библиотеку|медиатеку|коллекцию)|пересканируй|rescan|update (?:the )?library|refresh library)"),
    ("resume", "(?:сними с паузы|продолж(?:и|ай)|возобнови\\w*|resume|continue|unpause)"),
    ("toggle", "(?:плей пауза|плей или пауза|пауза или плей|toggle(?: pause)?)"),
    ("pause", "(?:поставь на паузу|сделай паузу|приостанови\\w*|\\bпауза\\b|pause)"),
    ("stop", "(?:стоп|останови\\w*|выключи музыку|хватит|stop|halt|be quiet)"),
    ("play", "^(?:включи|играй|запусти|плей|play|вруби)(?:\\s+(?:(?:музык\\w*|music|треки|tracks|песни|songs)))?$"),
    ("play_any", "(?:включи|включай|вруби|запусти|поставь|играй|плей|play|put on)\\s+(?:мне\\s+)?(?P<value>.+)"),
];

/// The tail the `mute` rule must not see: `(?!\s*(?:музык\w*|трек\w*|песн\w*))`.
pub const MUTE_TAIL: &str = "(?:\\s*(?:музык\\w*|трек\\w*|песн\\w*))";

/// Tag word -> MPD search tag (used by add_to_queue).
pub const TAG_WORDS: [(&str, &str); 21] = [
    ("album", "album"),
    ("артист", "artist"),
    ("artist", "artist"),
    ("band", "artist"),
    ("song", "title"),
    ("track", "title"),
    ("genre", "genre"),
    ("playlist", "playlist"),
    ("folder", "file"),
    ("directory", "file"),
    ("альбом", "album"),
    ("исполнитель", "artist"),
    ("артистка", "artist"),
    ("группа", "artist"),
    ("песня", "title"),
    ("песню", "title"),
    ("трек", "title"),
    ("композиция", "title"),
    ("жанр", "genre"),
    ("папка", "file"),
    ("плейлист", "playlist"),
];

/// Example phrases for `mpd-voice phrases` and the docs. The Russian strings
/// are command data (the client speaks both languages), not documentation.
pub const EXAMPLES: [(&str, &[&str]); 39] = [
    (
        "add_to_queue",
        &["добавь в очередь Agalloch", "add Agalloch to the queue"],
    ),
    ("clear_queue", &["очисти очередь", "clear the queue"]),
    ("consume_toggle", &["включи consume", "consume"]),
    (
        "describe_track",
        &["что это за трек", "describe this track"],
    ),
    ("exit", &["хватит слушать", "stop listening"]),
    ("help", &["помощь", "help"]),
    ("list_playlists", &["покажи плейлисты", "list playlists"]),
    ("mute", &["выключи звук", "mute"]),
    ("next", &["следующий трек", "next track"]),
    ("now_playing", &["что играет", "what is playing"]),
    ("pause", &["пауза", "pause"]),
    ("play", &["включи музыку", "play"]),
    (
        "play_album",
        &["включи альбом The Mantle", "play album The Mantle"],
    ),
    (
        "play_artist",
        &["включи исполнителя Agalloch", "play artist Agalloch"],
    ),
    (
        "play_directory",
        &["включи папку Agalloch", "play folder Agalloch"],
    ),
    (
        "play_genre",
        &["включи жанр doom metal", "play genre doom metal"],
    ),
    (
        "play_mood",
        &[
            "включи мрачное",
            "включи грустные песни",
            "включи спокойную музыку",
            "включи что-нибудь весёлое",
            "включи эпичное",
            "включи агрессивное",
            "включи космическое",
            "включи медитативное",
            "включи романтичное",
            "play dark music",
            "play something sad",
            "play relaxing music",
            "play happy music",
            "play epic music",
            "play aggressive music",
            "play space music",
            "play meditative music",
            "play romantic music",
        ],
    ),
    (
        "play_playlist",
        &["включи плейлист evening", "play playlist evening"],
    ),
    (
        "play_track",
        &["включи трек Falling Snow", "play song Falling Snow"],
    ),
    ("previous", &["предыдущий", "previous"]),
    ("queue_similar", &["добавь похожие треки", "more like this"]),
    ("repeat_off", &["не повторяй", "repeat off"]),
    ("repeat_on", &["повторяй", "repeat"]),
    ("repeat_single", &["повторяй один трек", "repeat one"]),
    ("resume", &["продолжи", "resume"]),
    (
        "save_playlist",
        &["сохрани плейлист evening", "save playlist evening"],
    ),
    (
        "seek_back",
        &["отмотай назад на минуту", "seek back 1 minute"],
    ),
    (
        "seek_forward",
        &["перемотай вперёд на 30 секунд", "skip forward 30 seconds"],
    ),
    ("seek_to", &["перемотай на 1:30", "seek to 1:30"]),
    ("shuffle_off", &["выключи шаффл", "shuffle off"]),
    ("shuffle_on", &["перемешай", "shuffle"]),
    ("stop", &["стоп", "stop"]),
    ("toggle", &["плей пауза", "toggle"]),
    ("unmute", &["верни звук", "unmute"]),
    (
        "update_library",
        &["обнови библиотеку", "update the library"],
    ),
    ("volume_down", &["тише на 10", "turn it down"]),
    ("volume_get", &["какая громкость", "what is the volume"]),
    (
        "volume_set",
        &["громкость на 40 процентов", "set volume to 40"],
    ),
    ("volume_up", &["громче", "louder"]),
];

/// Words that carry no query on their own: `play_any` with only filler means
/// "just play".
const FILLER: [&str; 14] = [
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
];

/// Russian number words ("громкость на двадцать").
///
/// Same keys as the Python table; the rule patterns expand this
/// alternation too, so keep the two in step.
const RU_NUMBERS: [(&str, i64); 32] = [
    ("два", 2),
    ("две", 2),
    ("сто", 100),
    ("три", 3),
    ("ноль", 0),
    ("один", 1),
    ("одну", 1),
    ("пять", 5),
    ("семь", 7),
    ("сорок", 40),
    ("шесть", 6),
    ("восемь", 8),
    ("девять", 9),
    ("десять", 10),
    ("четыре", 4),
    ("двадцать", 20),
    ("тридцать", 30),
    ("девяносто", 90),
    ("пятьдесят", 50),
    ("семьдесят", 70),
    ("двенадцать", 12),
    ("пятнадцать", 15),
    ("семнадцать", 17),
    ("тринадцать", 13),
    ("шестьдесят", 60),
    ("восемьдесят", 80),
    ("одиннадцать", 11),
    ("шестнадцать", 16),
    ("восемнадцать", 18),
    ("девятнадцать", 19),
    ("четырнадцать", 14),
    ("двадцать пять", 25),
];

/// `re.compile(r"мин\w*|minutes?")`: a duration in minutes, not seconds.
const MINUTES: &str = r"мин\w*|minutes?";

/// One recognised command.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Intent {
    pub name: String,
    pub value: String,
    pub tag: String,
    pub number: Option<i64>,
    pub lang: String,
    pub raw: String,
}

impl Intent {
    pub fn understood(&self) -> bool {
        self.name != UNKNOWN
    }
}

fn keep(ch: char) -> bool {
    // `[^\w\s+&./:’'-]` from the Python normaliser: word characters,
    // whitespace and the punctuation that occurs in track/album names.
    ch.is_alphanumeric() || ch == '_' || ch.is_whitespace() || "+&./:’'-".contains(ch)
}

/// Lower-case, drop punctuation and collapse whitespace.
pub fn normalize(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        // Guillemets and typographic quotes become spaces, so
        // "включи альбом «The Mantle»!" normalises cleanly.
        let ch = match ch {
            '«' | '»' | '“' | '”' | '„' => ' ',
            other => other,
        };
        for lower in ch.to_lowercase() {
            let lower = if lower == 'ё' { 'е' } else { lower };
            out.push(if keep(lower) { lower } else { ' ' });
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Cyrillic anywhere in the text means Russian, otherwise English.
pub fn language_of(text: &str) -> &'static str {
    if text.chars().any(|ch| matches!(ch, 'а'..='я') || ch == 'ё') {
        "ru"
    } else {
        "en"
    }
}

/// Drop the wake word (and everything around it) from a transcript.
///
/// Returns an empty string when the wake word is required but absent, which is
/// how the listener loop ignores background chatter.
pub fn strip_wake_word(text: &str, wake_word: &str) -> String {
    if wake_word.is_empty() {
        return text.trim().to_string();
    }
    // The engine has no case-insensitive mode: search a lowered copy and slice
    // the original with the same character offsets (lower-casing keeps the
    // character count for the scripts we accept).
    let lowered_text = text.to_lowercase();
    let pattern = format!(
        "(?:hey\\s+)?{}[\\s,.:;!?-]*",
        crate::rex::escape(&wake_word.to_lowercase())
    );
    let Some(regex) = Regex::new(&pattern) else {
        return String::new();
    };
    let Some(matched) = regex.search(&lowered_text) else {
        return String::new();
    };
    let chars: Vec<char> = text.chars().collect();
    let mut joined: String = chars[..matched.start.min(chars.len())].iter().collect();
    joined.push(' ');
    joined.extend(&chars[matched.end.min(chars.len())..]);
    joined.trim().to_string()
}

/// Digits or a Russian number word ("громкость на двадцать", "на двадцать пять").
fn number_of(token: Option<&str>) -> Option<i64> {
    let token = token?;
    let collapsed = token
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if collapsed.is_empty() {
        return None;
    }
    if collapsed.chars().all(|ch| ch.is_ascii_digit()) {
        return collapsed.parse().ok();
    }
    if let Some((_, value)) = RU_NUMBERS.iter().find(|(word, _)| *word == collapsed) {
        return Some(*value);
    }
    let parts: Vec<&str> = collapsed.split(' ').collect();
    if parts.len() == 2
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.chars().all(|ch| ch.is_ascii_digit()))
    {
        let tens: i64 = parts[0].parse().ok()?;
        let ones: i64 = parts[1].parse().ok()?;
        return Some(tens * 10 + ones);
    }
    None
}

fn strip_edge(value: &str) -> String {
    value
        .trim_matches(|ch| matches!(ch, ' ' | '.' | '-' | '\''))
        .to_string()
}

/// Trim the filler a tag word leaves behind ("мне", "пожалуйста", "в очередь").
fn clean_query(value: &str) -> String {
    let mut value = value.to_string();
    for (pattern, replacement) in [
        (r"\b(?:мне|пожалуйста|плиз|please|for me)\b", " "),
        (r"\b(?:to|in)\s+the\s+queue\b|\bв\s+очередь\b", " "),
        (r"^(?:как(?:ую|ой)[- ]нибудь|the|some)\s+", ""),
        (r"\b(?:музык\w*|music)$", " "),
    ] {
        if let Some(regex) = Regex::new(pattern) {
            value = regex.replace_all(&value, replacement);
        }
    }
    strip_edge(&value)
}

/// Canonical Jamendo label for a mood word matched by the parser.
pub fn mood_label(surface: &str) -> String {
    for (label, words) in MOOD_WORDS {
        if let Some(regex) = Regex::new(words) {
            if regex.fullmatch(surface).is_some() {
                return label.to_string();
            }
        }
    }
    surface.to_string()
}

/// Resolve a tag word ("album", "артиста") to an MPD tag.
pub fn tag_for_word(word: &str) -> String {
    let normalized = normalize(word);
    let Some(first) = normalized.split(' ').next().filter(|word| !word.is_empty()) else {
        return String::new();
    };
    TAG_WORDS
        .iter()
        .find(|(key, _)| *key == first)
        .map(|(_, tag)| tag.to_string())
        .unwrap_or_default()
}

/// Leftmost match of a rule, honouring the `mute` lookahead by resuming the
/// search after a rejected position (what the Python regex would do).
fn rule_match(name: &str, regex: &Regex, text: &str) -> Option<crate::rex::Match> {
    let mut start = 0;
    loop {
        let matched = regex.search_from(text, start)?;
        if name != "mute" {
            return Some(matched);
        }
        let tail_rejected = Regex::new(MUTE_TAIL)
            .and_then(|tail| tail.search_from(text, matched.end))
            .is_some_and(|tail| tail.start == matched.end);
        if !tail_rejected {
            return Some(matched);
        }
        start = matched.start + 1;
    }
}

/// Parse one utterance into an [`Intent`] (`unknown` if nothing matches).
pub fn parse(text: &str) -> Intent {
    let normalized = normalize(text);
    let lang = language_of(&normalized).to_string();
    let mut intent = Intent {
        name: UNKNOWN.to_string(),
        lang,
        raw: text.to_string(),
        ..Intent::default()
    };
    if normalized.is_empty() {
        return intent;
    }
    let chars: Vec<char> = normalized.chars().collect();
    for (name, pattern) in RULES {
        let Some(regex) = Regex::new(pattern) else {
            continue;
        };
        let Some(matched) = rule_match(name, &regex, &normalized) else {
            continue;
        };
        let matched_text: String = chars[matched.start..matched.end].iter().collect();
        let mut number = number_of(regex.group(&matched, "number"));
        let number2 = regex.group(&matched, "number2");
        if name == "seek_to" && number2.is_some() {
            let seconds: i64 = number2.unwrap_or("0").trim().parse().unwrap_or(0);
            number = Some(number.unwrap_or(0) * 60 + seconds);
        } else if Regex::new(MINUTES).is_some_and(|minutes| minutes.is_match(&matched_text)) {
            // "на минуту" -> 60s, "на 2 минуты" -> 120s
            number = Some(number.unwrap_or(1) * 60);
        }
        let tag = tag_for_word(regex.group(&matched, "tag").unwrap_or(""));
        let mut value = clean_query(regex.group(&matched, "value").unwrap_or(""));
        let mut name = name.to_string();
        if name == "play_mood" && !value.is_empty() {
            value = mood_label(&value);
        }
        if name == "play_any" && (value.is_empty() || FILLER.contains(&normalize(&value).as_str()))
        {
            name = "play".to_string();
            value.clear();
        }
        return Intent {
            name,
            value,
            tag,
            number,
            lang: intent.lang,
            raw: intent.raw,
        };
    }
    intent
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every phrase from the Python parser suite: phrase, intent, value, number.
    const CASES: [(&str, &str, &str, Option<i64>); 77] = [
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
        ("громче на 15", "volume_up", "", Some(15)),
        ("погромче", "volume_up", "", None),
        ("тише на двадцать", "volume_down", "", Some(20)),
        ("turn it down", "volume_down", "", None),
        ("громкость на 40 процентов", "volume_set", "", Some(40)),
        ("set volume to 35", "volume_set", "", Some(35)),
        ("volume 70", "volume_set", "", Some(70)),
        ("какая громкость", "volume_get", "", None),
        ("what is the volume", "volume_get", "", None),
        ("выключи звук", "mute", "", None),
        ("верни звук", "unmute", "", None),
        ("что это за трек", "describe_track", "", None),
        ("что там за песня", "describe_track", "", None),
        ("опиши этот трек", "describe_track", "", None),
        ("расскажи про песню", "describe_track", "", None),
        ("describe this track", "describe_track", "", None),
        ("что за трек", "now_playing", "", None),
        ("что играет", "now_playing", "", None),
        ("what is playing", "now_playing", "", None),
        (
            "перемотай вперёд на 30 секунд",
            "seek_forward",
            "",
            Some(30),
        ),
        ("skip forward 45 seconds", "seek_forward", "", Some(45)),
        ("отмотай назад на 2 минуты", "seek_back", "", Some(120)),
        ("seek back 1 minute", "seek_back", "", Some(60)),
        ("перемотай на 1:30", "seek_to", "", Some(90)),
        ("перемотай в начало", "seek_to", "", None),
        ("включи альбом The Mantle", "play_album", "mantle", None),
        ("play album The Mantle", "play_album", "mantle", None),
        (
            "включи исполнителя Agalloch",
            "play_artist",
            "agalloch",
            None,
        ),
        ("play artist Agalloch", "play_artist", "agalloch", None),
        (
            "включи трек Falling Snow",
            "play_track",
            "falling snow",
            None,
        ),
        (
            "включи песню Falling Snow",
            "play_track",
            "falling snow",
            None,
        ),
        ("включи жанр doom metal", "play_genre", "doom metal", None),
        ("включи папку Agalloch", "play_directory", "agalloch", None),
        ("включи плейлист evening", "play_playlist", "evening", None),
        ("play playlist evening", "play_playlist", "evening", None),
        ("включи музыку", "play", "", None),
        ("включи", "play", "", None),
        ("play", "play", "", None),
        ("включи какую-нибудь музыку", "play", "", None),
        (
            "добавь в очередь Agalloch",
            "add_to_queue",
            "agalloch",
            None,
        ),
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
    ];

    /// Every mood phrase and the canonical Jamendo label it must resolve to.
    const MOOD_PHRASES: [(&str, &str); 35] = [
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
    ];

    #[test]
    fn phrase_table_matches_the_python_suite() {
        for (phrase, name, value, number) in CASES {
            let intent = parse(phrase);
            assert_eq!(intent.name, name, "phrase {phrase:?}");
            assert_eq!(intent.value, value, "phrase {phrase:?}");
            assert_eq!(intent.number, number, "phrase {phrase:?}");
        }
    }

    #[test]
    fn language_detection() {
        assert_eq!(parse("громче").lang, "ru");
        assert_eq!(parse("louder").lang, "en");
    }

    #[test]
    fn unknown_is_not_guessed() {
        for phrase in ["расскажи анекдот", "make me a sandwich", ""] {
            let intent = parse(phrase);
            assert!(!intent.understood(), "phrase {phrase:?}");
            assert_eq!(intent.name, UNKNOWN);
        }
    }

    #[test]
    fn punctuation_and_case_are_normalised() {
        let intent = parse("  Включи альбом «The Mantle»!  ");
        assert_eq!(intent.name, "play_album");
        assert_eq!(intent.value, "mantle");
    }

    #[test]
    fn examples_parse_as_advertised() {
        for (name, examples) in EXAMPLES {
            for phrase in examples {
                assert_eq!(parse(phrase).name, name, "phrase {phrase:?}");
            }
        }
    }

    #[test]
    fn wake_word_is_stripped() {
        assert_eq!(
            strip_wake_word("музыка, следующий трек", "музыка"),
            "следующий трек"
        );
        assert_eq!(
            strip_wake_word("Hey Music next track", "music"),
            "next track"
        );
        // Without the keyword the utterance is ignored entirely.
        assert_eq!(strip_wake_word("следующий трек", "музыка"), "");
        assert_eq!(strip_wake_word("  next track  ", ""), "next track");
    }

    #[test]
    fn mood_phrases_resolve_to_canonical_labels() {
        for (phrase, label) in MOOD_PHRASES {
            let intent = parse(phrase);
            assert_eq!(intent.name, "play_mood", "phrase {phrase:?}");
            assert_eq!(intent.value, label, "phrase {phrase:?}");
        }
    }

    #[test]
    fn mood_labels_are_jamendo_classes() {
        let classes = [
            "calm",
            "dark",
            "epic",
            "energetic",
            "groovy",
            "happy",
            "heavy",
            "hopeful",
            "meditative",
            "melancholic",
            "positive",
            "relaxing",
            "romantic",
            "sad",
            "space",
            "upbeat",
            "uplifting",
        ];
        for (_, label) in MOOD_PHRASES {
            assert!(
                classes.contains(&label),
                "label {label:?} is not a Jamendo class"
            );
        }
    }

    #[test]
    fn moods_do_not_swallow_library_queries() {
        for (phrase, name) in [
            ("включи альбом Dark Side of the Moon", "play_album"),
            ("включи трек Dark", "play_track"),
            ("включи папку Space", "play_directory"),
            ("включи исполнителя Happy", "play_artist"),
            ("play album Epic", "play_album"),
            ("включи похожие", "queue_similar"),
            ("добавь в очередь Agalloch", "add_to_queue"),
        ] {
            assert_eq!(parse(phrase).name, name, "phrase {phrase:?}");
        }
    }

    #[test]
    fn mute_guard_rejects_music_requests() {
        // The lookahead the engine does not implement, checked explicitly.
        assert_eq!(parse("выключи звук").name, "mute");
        assert_eq!(parse("без звука").name, "mute");
        assert_ne!(parse("выключи звук музыки").name, "mute");
        assert_ne!(parse("мут музыка").name, "mute");
    }

    #[test]
    fn numbers_word_and_digit_forms() {
        assert_eq!(parse("громче на 15").number, Some(15));
        assert_eq!(parse("тише на двадцать").number, Some(20));
        assert_eq!(parse("громкость на двадцать пять").number, Some(25));
        assert_eq!(parse("перемотай на 1:30").number, Some(90));
        assert_eq!(parse("отмотай назад на 2 минуты").number, Some(120));
        assert_eq!(parse("отмотай назад на минуту").number, Some(60));
    }

    #[test]
    fn filler_play_any_becomes_play() {
        for phrase in [
            "включи музыку",
            "включи какую-нибудь музыку",
            "play something",
        ] {
            let intent = parse(phrase);
            assert_eq!(intent.name, "play", "phrase {phrase:?}");
            assert_eq!(intent.value, "", "phrase {phrase:?}");
        }
    }

    #[test]
    fn tag_words_resolve_to_mpd_tags() {
        // Only the exact keys of the table resolve: an inflected form matched by
        // the rule pattern ("альбома") stays unresolved, like the Python parser.
        assert_eq!(tag_for_word("альбом"), "album");
        assert_eq!(tag_for_word("альбома"), "");
        assert_eq!(tag_for_word("Artist"), "artist");
        assert_eq!(tag_for_word("песню"), "title");
        assert_eq!(tag_for_word(""), "");
    }
}
