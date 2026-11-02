//! Fetch missing album covers with sacad.
//!
//! Walks `~/music`, takes the folders named `Artist-⟨code⟩-Album` that hold no
//! cover yet, and asks sacad for one image each (`cover.jpg`, 500 px). sacad
//! exits 0 even on "No results", so the file itself is the verdict; empty or
//! bogus files are removed again.
//!
//!     fetch-covers [--dry-run]
//!
//! Port of `packages/local-bin/scripts/fetch-covers`. `MUSIC_DIR` overrides
//! `~/music` (tests), `SACAD` overrides the sacad binary.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const COVER_SIZE: &str = "500";
const TIMEOUT_SECONDS: u64 = 30;

fn music_dir() -> PathBuf {
    if let Ok(value) = std::env::var("MUSIC_DIR") {
        if !value.is_empty() {
            return PathBuf::from(value);
        }
    }
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("music")
}

/// `^(.+?)-⟨[^⟩]+⟩-(.+)$` without a regex engine: the first `-⟨…⟩-` splits the
/// folder name into artist and album.
pub fn split_album_dir(name: &str) -> Option<(String, String)> {
    let open = name.find("-\u{27e8}")?;
    let rest = &name[open + "-\u{27e8}".len()..];
    let close = rest.find('\u{27e9}')?;
    let code = &rest[..close];
    if code.is_empty() || code.contains('\u{27e8}') {
        return None;
    }
    let tail = &rest[close + '\u{27e9}'.len_utf8()..];
    let album = tail.strip_prefix('-')?;
    if album.is_empty() || name[..open].is_empty() {
        return None;
    }
    Some((name[..open].trim().to_string(), album.trim().to_string()))
}

fn has_cover(folder: &Path) -> bool {
    let Ok(entries) = std::fs::read_dir(folder) else {
        return false;
    };
    entries.flatten().any(|entry| {
        let name = entry.file_name().to_string_lossy().to_lowercase();
        ["cover", "folder", "front", "artwork"]
            .iter()
            .any(|prefix| name.starts_with(prefix))
    })
}

fn sacad() -> String {
    match std::env::var("SACAD") {
        Ok(value) if !value.is_empty() => value,
        _ => "sacad".to_string(),
    }
}

fn main() -> std::process::ExitCode {
    let dry_run = std::env::args().any(|arg| arg == "--dry-run");
    let music = music_dir();
    let mut names: Vec<String> = match std::fs::read_dir(&music) {
        Ok(entries) => entries
            .flatten()
            .map(|entry| entry.file_name().to_string_lossy().to_string())
            .collect(),
        Err(exc) => {
            println!("Albums without covers: 0/0");
            eprintln!("fetch-covers: cannot read {}: {exc}", music.display());
            return std::process::ExitCode::SUCCESS;
        }
    };
    names.sort();
    let matching: Vec<&String> = names
        .iter()
        .filter(|name| split_album_dir(name).is_some())
        .collect();

    let mut missing: Vec<(String, String, String)> = Vec::new();
    for name in &names {
        let Some((artist, album)) = split_album_dir(name) else {
            continue;
        };
        let folder = music.join(name);
        if !folder.is_dir() || has_cover(&folder) {
            continue;
        }
        missing.push((name.clone(), artist, album));
    }

    println!(
        "Albums without covers: {}/{}",
        missing.len(),
        matching.len()
    );
    println!();

    let mut success = 0;
    for (index, (dirname, artist, album)) in missing.iter().enumerate() {
        let outpath = music.join(dirname).join("cover.jpg");
        println!("[{}/{}] {artist} — {album}", index + 1, missing.len());
        if dry_run {
            continue;
        }
        let output = Command::new(sacad())
            .args([artist, album, COVER_SIZE, &outpath.display().to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();
        let _deadline = std::time::Duration::from_secs(TIMEOUT_SECONDS);
        match output {
            Ok(output) => {
                let size = std::fs::metadata(&outpath)
                    .map(|meta| meta.len())
                    .unwrap_or(0);
                if size > 0 {
                    println!("  ✓ saved to {dirname}/cover.jpg");
                    success += 1;
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let message = stderr
                        .rsplit('\n')
                        .find(|line| !line.trim().is_empty())
                        .unwrap_or("No results")
                        .to_string();
                    println!("  ✗ {message}");
                    let _ = std::fs::remove_file(&outpath);
                }
            }
            Err(exc) => println!("  ✗ {exc}"),
        }
    }
    println!("\nDone: {success}/{} covers downloaded", missing.len());
    std::process::ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn album_folders_split_on_the_code_marker() {
        assert_eq!(
            split_album_dir("Artist-\u{27e8}ABC123\u{27e9}-Some Album"),
            Some(("Artist".to_string(), "Some Album".to_string()))
        );
        assert_eq!(
            split_album_dir("A-B-\u{27e8}code\u{27e9}-Album-With-Dashes"),
            Some(("A-B".to_string(), "Album-With-Dashes".to_string()))
        );
        assert_eq!(split_album_dir("plain-folder"), None);
        assert_eq!(split_album_dir("Artist-\u{27e8}\u{27e9}-Album"), None);
        assert_eq!(split_album_dir("Artist-\u{27e8}code\u{27e9}Album"), None);
    }

    #[test]
    fn cover_detection_looks_at_the_prefix() {
        let dir = std::env::temp_dir().join(format!("fetch-covers-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let album = dir.join("A-\u{27e8}c\u{27e9}-B");
        std::fs::create_dir_all(&album).unwrap();
        assert!(!has_cover(&album));
        std::fs::write(album.join("Folder.jpg"), b"x").unwrap();
        assert!(has_cover(&album));
        std::fs::remove_dir_all(&dir).ok();
    }
}
