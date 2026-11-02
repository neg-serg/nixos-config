//! Write the ML mood (and optionally the Discogs style) into the audio files.
//!
//! Port of `scripts/dev/music-apply-tags.py`. Players, MPD's own `search` and
//! other machines only see tags that live in the files; the mood labels from
//! `music-mtg-tags` otherwise stay in a cache file. This tool copies them in —
//! dry run by default, and every change is appended to a JSONL log (old -> new
//! per file) so a run can be reviewed or reverted by hand.
//!
//!     music-apply-tags [--tags FILE] [--field mood,genre] [--min-score X]
//!                      [--top N] [--limit N] [--music-dir DIR] [--only GLOB]
//!                      [--log FILE] [--apply] [--quiet]
//!
//! MOOD is a field the files do not carry yet, so writing it is safe; GENRE
//! *replaces* whatever genre the file already has and is therefore off by
//! default.
//!
//! Writing goes through lofty: one code path for FLAC/Ogg/Opus (Vorbis
//! comments), MP3/WAV (ID3: TMOO/TCON) and M4A (the
//! `----:com.apple.iTunes:MOOD` freeform atom). Containers lofty does not
//! write (aac/wma) are reported and skipped.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::{SystemTime, UNIX_EPOCH};

use lofty::config::WriteOptions;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::tag::{ItemKey, Tag, TagType};
use serde_json::Value;

const AUDIO_SUFFIXES: &[&str] = &["flac", "mp3", "m4a", "ogg", "opus", "wav", "aac", "wma"];
const USAGE: &str = "usage: music-apply-tags [-h] [--tags TAGS] [--field FIELD]\n\
                     \x20                      [--min-score MIN_SCORE] [--top TOP]\n\
                     \x20                      [--limit LIMIT] [--music-dir MUSIC_DIR]\n\
                     \x20                      [--only GLOB] [--log LOG] [--apply]\n\
                     \x20                      [--quiet]";

#[derive(Clone, Copy, PartialEq, Eq)]
enum Writer {
    Vorbis,
    Id3,
    Mp4,
    Unsupported,
}

impl Writer {
    fn name(self) -> &'static str {
        match self {
            Self::Vorbis => "vorbis",
            Self::Id3 => "id3",
            Self::Mp4 => "mp4",
            Self::Unsupported => "unsupported",
        }
    }
}

fn writer_for(path: &Path) -> Writer {
    match path
        .extension()
        .and_then(|ext| ext.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("flac" | "ogg" | "opus") => Writer::Vorbis,
        Some("mp3" | "wav") => Writer::Id3,
        Some("m4a") => Writer::Mp4,
        _ => Writer::Unsupported,
    }
}

fn tag_type(writer: Writer) -> TagType {
    match writer {
        Writer::Vorbis => TagType::VorbisComments,
        Writer::Id3 => TagType::Id3v2,
        _ => TagType::Mp4Ilst,
    }
}

fn item_key(field: &str) -> ItemKey {
    if field == "mood" {
        ItemKey::Mood
    } else {
        ItemKey::Genre
    }
}

fn expand_home(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        Path::new(&home).join(rest)
    } else {
        PathBuf::from(path)
    }
}

fn dotted_suffix(path: &Path) -> String {
    path.extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| format!(".{ext}"))
        .unwrap_or_default()
}

fn file_name(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("?")
        .to_string()
}

/// Python `str()` of a JSON label: strings stay as they are, `None` is "None".
fn label_text(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Null => "None".to_string(),
        other => other.to_string(),
    }
}

fn pick_labels(tags: &Value, field: &str, min_score: f64, top: i64) -> String {
    let Some(items) = tags.get(field).and_then(Value::as_array) else {
        return String::new();
    };
    let mut picked = Vec::new();
    for item in items {
        let score = item.get("score").and_then(Value::as_f64).unwrap_or(0.0);
        if score < min_score {
            continue;
        }
        let label = item
            .get("label")
            .map(label_text)
            .unwrap_or_else(|| "None".to_string());
        // Discogs labels are "Parent---Style"; the file field wants the style.
        let style = label.rsplit("---").next().unwrap_or(&label).to_string();
        picked.push(style);
        if picked.len() as i64 >= top {
            break;
        }
    }
    picked.join(";")
}

fn read_tag(writer: Writer, path: &Path, field: &str) -> Result<String, String> {
    if writer == Writer::Unsupported {
        return Ok(String::new());
    }
    let file = lofty::read_from_path(path).map_err(|error| error.to_string())?;
    Ok(file
        .primary_tag()
        .and_then(|tag| tag.get_string(item_key(field)))
        .unwrap_or("")
        .to_string())
}

fn write_tag(writer: Writer, path: &Path, field: &str, value: &str) -> Result<bool, String> {
    if writer == Writer::Unsupported {
        eprintln!(
            "[music-apply-tags] {} cannot be written (unsupported)",
            dotted_suffix(path)
        );
        return Ok(false);
    }
    let mut file = lofty::read_from_path(path).map_err(|error| error.to_string())?;
    if file.primary_tag_mut().is_none() {
        file.insert_tag(Tag::new(tag_type(writer)));
    }
    let tag = file
        .primary_tag_mut()
        .ok_or_else(|| "no writable tag".to_string())?;
    let key = item_key(field);
    tag.remove_key(key.clone());
    tag.insert_text(key, value.to_string());
    file.save_to_path(path, WriteOptions::default())
        .map_err(|error| error.to_string())?;
    Ok(true)
}

/// Python's `fnmatch.fnmatch`: `*`, `?`, `[seq]` and `[!seq]`, no separator
/// special case.
fn fnmatch(pattern: &str, text: &str) -> bool {
    fn matches(pattern: &[char], text: &[char]) -> bool {
        let mut p = 0;
        let mut t = 0;
        let mut star: Option<(usize, usize)> = None;
        while t < text.len() {
            if p < pattern.len() {
                match pattern[p] {
                    '?' => {
                        p += 1;
                        t += 1;
                        continue;
                    }
                    '*' => {
                        star = Some((p, t));
                        p += 1;
                        continue;
                    }
                    '[' => {
                        if let Some((end, ok)) = bracket_match(&pattern[p..], text[t]) {
                            if ok {
                                p += end;
                                t += 1;
                                continue;
                            }
                        }
                    }
                    literal if literal == text[t] => {
                        p += 1;
                        t += 1;
                        continue;
                    }
                    _ => {}
                }
            }
            match star {
                Some((sp, st)) => {
                    p = sp + 1;
                    t = st + 1;
                    star = Some((sp, st + 1));
                }
                None => return false,
            }
        }
        while p < pattern.len() && pattern[p] == '*' {
            p += 1;
        }
        p == pattern.len()
    }

    /// Length of a bracket expression and whether `ch` is inside it.
    fn bracket_match(pattern: &[char], ch: char) -> Option<(usize, bool)> {
        let mut i = 1;
        let negate = pattern.get(1) == Some(&'!');
        if negate {
            i += 1;
        }
        let mut found = false;
        let mut first = true;
        while i < pattern.len() {
            if pattern[i] == ']' && !first {
                return Some((i + 1, found != negate));
            }
            first = false;
            if i + 2 < pattern.len() && pattern[i + 1] == '-' && pattern[i + 2] != ']' {
                if pattern[i] <= ch && ch <= pattern[i + 2] {
                    found = true;
                }
                i += 3;
            } else {
                if pattern[i] == ch {
                    found = true;
                }
                i += 1;
            }
        }
        None
    }

    let pattern: Vec<char> = pattern.chars().collect();
    let text: Vec<char> = text.chars().collect();
    matches(&pattern, &text)
}

#[repr(C)]
struct Tm {
    tm_sec: i32,
    tm_min: i32,
    tm_hour: i32,
    tm_mday: i32,
    tm_mon: i32,
    tm_year: i32,
    tm_wday: i32,
    tm_yday: i32,
    tm_isdst: i32,
    tm_gmtoff: i64,
    tm_zone: *const i8,
}

extern "C" {
    fn localtime_r(timep: *const i64, result: *mut Tm) -> *mut Tm;
}

fn now_stamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0);
    let mut tm: Tm = unsafe { std::mem::zeroed() };
    let ok = unsafe { !localtime_r(&seconds, &mut tm).is_null() };
    if !ok {
        return "1970-01-01T00:00:00".to_string();
    }
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec
    )
}

struct Args {
    tags: String,
    fields: Vec<String>,
    min_score: f64,
    top: i64,
    limit: usize,
    music_dir: String,
    only: Vec<String>,
    log: String,
    apply: bool,
    quiet: bool,
}

fn env_or(name: &str, fallback: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| fallback.to_string())
}

fn parse_args(argv: &[String]) -> Result<Args, String> {
    let mut args = Args {
        tags: env_or("MUSIC_MTG_TAGS", "~/.cache/music-mtg/tags.jsonl"),
        fields: vec!["mood".to_string()],
        min_score: 0.15,
        top: 3,
        limit: 0,
        music_dir: env_or("MUSIC_DIR", "~/music"),
        only: Vec::new(),
        log: env_or("MUSIC_TAG_LOG", "~/.cache/music-mtg/tag-changes.jsonl"),
        apply: false,
        quiet: false,
    };
    let mut field_spec = "mood".to_string();
    let mut index = 0;
    while index < argv.len() {
        let arg = argv[index].as_str();
        if arg == "-h" || arg == "--help" {
            println!("{USAGE}");
            std::process::exit(0);
        }
        let (option, inline) = match arg.split_once('=') {
            Some((option, value)) => (option, Some(value.to_string())),
            None => (arg, None),
        };
        let value = |name: &str, index: &mut usize| -> Result<String, String> {
            if let Some(inline) = &inline {
                return Ok(inline.clone());
            }
            *index += 1;
            argv.get(*index)
                .cloned()
                .ok_or_else(|| format!("argument {name}: expected one argument"))
        };
        match option {
            "--tags" => args.tags = value("--tags", &mut index)?,
            "--field" => field_spec = value("--field", &mut index)?,
            "--min-score" => {
                let raw = value("--min-score", &mut index)?;
                args.min_score = raw
                    .parse()
                    .map_err(|_| format!("argument --min-score: invalid float value: '{raw}'"))?;
            }
            "--top" => {
                let raw = value("--top", &mut index)?;
                args.top = raw
                    .parse()
                    .map_err(|_| format!("argument --top: invalid int value: '{raw}'"))?;
            }
            "--limit" => {
                let raw = value("--limit", &mut index)?;
                args.limit = raw
                    .parse()
                    .map_err(|_| format!("argument --limit: invalid int value: '{raw}'"))?;
            }
            "--music-dir" => args.music_dir = value("--music-dir", &mut index)?,
            "--only" => args.only.push(value("--only", &mut index)?),
            "--log" => args.log = value("--log", &mut index)?,
            "--apply" => args.apply = true,
            "--quiet" => args.quiet = true,
            other => return Err(format!("unrecognized arguments: {other}")),
        }
        index += 1;
    }
    args.fields = field_spec
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_string)
        .collect();
    if args.fields.is_empty()
        || args
            .fields
            .iter()
            .any(|field| field != "mood" && field != "genre")
    {
        return Err("--field must be mood and/or genre".to_string());
    }
    Ok(args)
}

fn absolute(path: &Path) -> PathBuf {
    std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf())
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&argv) {
        Ok(args) => args,
        Err(message) => {
            eprintln!("{USAGE}");
            eprintln!("music-apply-tags: error: {message}");
            return ExitCode::from(2);
        }
    };

    let tags_file = expand_home(&args.tags);
    if !tags_file.is_file() {
        eprintln!("[music-apply-tags] no tag file: {}", tags_file.display());
        return ExitCode::from(2);
    }
    let music_dir_expanded = expand_home(&args.music_dir);
    let music_dir = match std::fs::canonicalize(&music_dir_expanded) {
        Ok(path) => path,
        Err(_) => absolute(&music_dir_expanded),
    };
    if !music_dir.is_dir() {
        eprintln!(
            "[music-apply-tags] no music directory: {}",
            music_dir.display()
        );
        return ExitCode::from(2);
    }
    let log_path = expand_home(&args.log);
    if args.apply {
        if let Some(parent) = log_path.parent() {
            if let Err(error) = std::fs::create_dir_all(parent) {
                eprintln!(
                    "[music-apply-tags] cannot create {}: {error}",
                    parent.display()
                );
                return ExitCode::from(2);
            }
        }
        println!(
            "[music-apply-tags] applying to {}, log -> {}",
            music_dir.display(),
            log_path.display()
        );
    } else {
        println!(
            "[music-apply-tags] dry run (add --apply to write), tags={}",
            tags_file.display()
        );
    }

    let mut files = 0usize;
    let mut changed = 0usize;
    let mut empty = 0usize;
    let mut failed = 0usize;
    let mut log = if args.apply {
        match std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
        {
            Ok(file) => Some(file),
            Err(error) => {
                eprintln!(
                    "[music-apply-tags] cannot open {}: {error}",
                    log_path.display()
                );
                return ExitCode::from(2);
            }
        }
    } else {
        None
    };

    let text = std::fs::read_to_string(&tags_file).unwrap_or_else(|_| {
        String::from_utf8_lossy(&std::fs::read(&tags_file).unwrap_or_default()).into_owned()
    });
    for line in text.split('\n') {
        if line.trim().is_empty() {
            continue;
        }
        let Ok(record) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(raw) = record.get("path").and_then(Value::as_str) else {
            continue;
        };
        let path = Path::new(raw);
        if !path.is_file() {
            continue;
        }
        let Some(suffix) = path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(str::to_ascii_lowercase)
        else {
            continue;
        };
        if !AUDIO_SUFFIXES.contains(&suffix.as_str()) {
            continue;
        }
        if !args.only.is_empty() && !args.only.iter().any(|pattern| fnmatch(pattern, raw)) {
            continue;
        }
        let resolved = match std::fs::canonicalize(path) {
            Ok(resolved) => resolved,
            Err(_) => absolute(path),
        };
        if !resolved.starts_with(&music_dir) {
            eprintln!(
                "[music-apply-tags] outside {}, skipped: {}",
                music_dir.display(),
                path.display()
            );
            failed += 1;
            continue;
        }
        files += 1;
        if args.limit > 0 && files > args.limit {
            break;
        }
        let tags = record
            .get("tags")
            .cloned()
            .unwrap_or_else(|| Value::Object(Default::default()));
        let writer = writer_for(path);
        let relative = path
            .strip_prefix(&music_dir)
            .unwrap_or(path)
            .display()
            .to_string();
        for field in &args.fields {
            let value = pick_labels(&tags, field, args.min_score, args.top);
            if value.is_empty() {
                empty += 1;
                continue;
            }
            let current = match read_tag(writer, path, field) {
                Ok(current) => current,
                Err(error) => {
                    eprintln!(
                        "[music-apply-tags] {} failed on {}: {error}",
                        field.to_uppercase(),
                        file_name(path)
                    );
                    failed += 1;
                    continue;
                }
            };
            if current == value {
                continue;
            }
            if !args.apply {
                if !args.quiet {
                    println!(
                        "would set {}={} (was {}) in {} [{}]",
                        field.to_uppercase(),
                        value,
                        if current.is_empty() { "none" } else { &current },
                        relative,
                        writer.name()
                    );
                }
                changed += 1;
                continue;
            }
            match write_tag(writer, path, field, &value) {
                Ok(true) => {
                    changed += 1;
                    if let Some(log) = log.as_mut() {
                        let row = serde_json::json!({
                            "path": raw,
                            "field": field,
                            "old": current,
                            "new": value,
                            "writer": writer.name(),
                            "at": now_stamp(),
                        });
                        let _ = writeln!(log, "{row}");
                        let _ = log.flush();
                    }
                }
                Ok(false) => failed += 1,
                Err(error) => {
                    eprintln!(
                        "[music-apply-tags] {} failed on {}: {error}",
                        field.to_uppercase(),
                        file_name(path)
                    );
                    failed += 1;
                }
            }
        }
    }

    let verb = if args.apply {
        "written"
    } else {
        "would change"
    };
    println!(
        "[music-apply-tags] {changed} {verb}, {empty} without labels, {failed} failed (of {files} files)"
    );
    if failed == 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_keep_the_style_and_respect_the_floor() {
        let tags = serde_json::json!({
            "mood": [
                {"label": "Aggressive", "score": 0.9},
                {"label": "Parent---Dark Ambient", "score": 0.4},
                {"label": "Low", "score": 0.1},
                {"label": "Extra", "score": 0.5},
            ]
        });
        assert_eq!(
            pick_labels(&tags, "mood", 0.15, 3),
            "Aggressive;Dark Ambient;Extra"
        );
        assert_eq!(pick_labels(&tags, "genre", 0.15, 3), "");
        assert_eq!(pick_labels(&tags, "mood", 0.15, 1), "Aggressive");
    }

    #[test]
    fn fnmatch_matches_python_semantics() {
        assert!(fnmatch("*.flac", "/m/a.flac"));
        assert!(fnmatch("/m/*.flac", "/m/a.flac"));
        assert!(!fnmatch("*.flac", "/m/a.mp3"));
        assert!(fnmatch("a?c", "abc"));
        assert!(fnmatch("[ab]x", "bx"));
        assert!(!fnmatch("[!ab]x", "bx"));
        assert!(fnmatch("[a-c]x", "bx"));
    }

    #[test]
    fn writer_selection_follows_the_suffix() {
        assert!(matches!(writer_for(Path::new("a.FLAC")), Writer::Vorbis));
        assert!(matches!(writer_for(Path::new("a.wav")), Writer::Id3));
        assert!(matches!(writer_for(Path::new("a.m4a")), Writer::Mp4));
        assert!(matches!(
            writer_for(Path::new("a.aac")),
            Writer::Unsupported
        ));
    }
}
