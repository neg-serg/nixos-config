//! Song metadata helpers shared by the CLI and the session.

use std::path::Path;

use crate::mpd::Meta;

/// `title`, else `name`, else the file stem, else `?`.
pub fn song_title(song: &Meta) -> String {
    if let Some(title) = song.get("title").filter(|t| !t.is_empty()) {
        return title.to_string();
    }
    if let Some(name) = song.get("name").filter(|t| !t.is_empty()) {
        return name.to_string();
    }
    let path = song
        .get("file")
        .filter(|t| !t.is_empty())
        .or_else(|| song.get("playlist").filter(|t| !t.is_empty()))
        .unwrap_or("");
    if path.is_empty() {
        return "?".to_string();
    }
    Path::new(path)
        .file_stem()
        .map(|stem| stem.to_string_lossy().to_string())
        .unwrap_or_else(|| "?".to_string())
}

pub fn song_artist(song: &Meta) -> String {
    ["artist", "albumartist", "performer"]
        .iter()
        .find_map(|key| song.get(key).filter(|value| !value.is_empty()))
        .unwrap_or("")
        .to_string()
}

pub fn duration_to_clock(seconds: f64) -> String {
    let total = seconds.round().max(0.0) as i64;
    format!("{}:{:02}", total / 60, total % 60)
}

pub fn song_duration(song: &Meta) -> f64 {
    for key in ["duration", "time"] {
        if let Some(raw) = song.get(key) {
            if let Ok(value) = raw.trim().parse::<f64>() {
                return value;
            }
        }
    }
    0.0
}

/// Human readable "Title — Artist (Album) [m:ss]" line.
pub fn describe(song: &Meta) -> String {
    let mut parts = vec![song_title(song)];
    let artist = song_artist(song);
    if !artist.is_empty() {
        parts.push(artist);
    }
    let mut line = parts.join(" — ");
    if let Some(album) = song.get("album").filter(|album| !album.is_empty()) {
        line = format!("{line} ({album})");
    }
    let seconds = song_duration(song);
    if seconds != 0.0 {
        line = format!("{line} [{}]", duration_to_clock(seconds));
    }
    line
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(pairs: &[(&str, &str)]) -> Meta {
        Meta(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        )
    }

    #[test]
    fn title_falls_back_to_name_then_file_stem() {
        assert_eq!(song_title(&meta(&[("title", "T")])), "T");
        assert_eq!(song_title(&meta(&[("name", "N")])), "N");
        assert_eq!(
            song_title(&meta(&[("file", "Artist/Album/08 Song.flac")])),
            "08 Song"
        );
        assert_eq!(song_title(&meta(&[])), "?");
    }

    #[test]
    fn artist_falls_back_through_albumartist_and_performer() {
        assert_eq!(song_artist(&meta(&[("artist", "A")])), "A");
        assert_eq!(song_artist(&meta(&[("albumartist", "AA")])), "AA");
        assert_eq!(song_artist(&meta(&[("performer", "P")])), "P");
        assert_eq!(song_artist(&meta(&[])), "");
    }

    #[test]
    fn clock_rounds_like_python() {
        assert_eq!(duration_to_clock(0.0), "0:00");
        assert_eq!(duration_to_clock(59.6), "1:00");
        assert_eq!(duration_to_clock(-3.0), "0:00");
        assert_eq!(duration_to_clock(3725.0), "62:05");
    }

    #[test]
    fn describe_matches_the_python_format() {
        let song = meta(&[
            ("file", "a.flac"),
            ("title", "Falling Snow"),
            ("artist", "Agalloch"),
            ("album", "The Mantle"),
            ("duration", "551.2"),
        ]);
        assert_eq!(
            describe(&song),
            "Falling Snow — Agalloch (The Mantle) [9:11]"
        );
        let bare = meta(&[("file", "a.flac")]);
        assert_eq!(describe(&bare), "a");
    }
}
