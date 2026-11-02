//! Scene discovery, ported from the three scripts' identical `resolve_scene`
//! and `is_part_file` blocks.

use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use crate::ctx::Ctx;

#[derive(Clone, Debug)]
pub struct Scene {
    pub name: String,
    pub file: PathBuf,
}

fn sorted_entries(directory: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = match fs::read_dir(directory) {
        Ok(entries) => entries
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .collect(),
        Err(_) => Vec::new(),
    };
    entries.sort_by(|left, right| {
        left.as_os_str()
            .as_bytes()
            .cmp(right.as_os_str().as_bytes())
    });
    entries
}

/// Scene directories under `<project>/shells/*/`, sorted the way bash globs
/// sort (bracket expansion is byte-ordered under `LC_ALL=C`; the harness sets
/// its own order rather than depending on the caller's locale).
pub fn scene_dirs(project: &Path) -> Vec<PathBuf> {
    sorted_entries(&project.join("shells"))
        .into_iter()
        .filter(|path| path.is_dir())
        .collect()
}

/// `shells/*/*.plm`, files only, in glob order.
pub fn scene_files(project: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    for directory in scene_dirs(project) {
        for entry in sorted_entries(&directory) {
            if entry.is_file()
                && entry
                    .file_name()
                    .map(|name| name.as_bytes().ends_with(b".plm"))
                    .unwrap_or(false)
            {
                files.push(entry);
            }
        }
    }
    files
}

/// `head -n 5 file | grep -qE '^[[:space:]]*part[[:space:]]+[A-Za-z_]'`.
/// A read error is a non-match, exactly like the failed pipeline.
pub fn is_part_file(file: &Path) -> bool {
    let bytes = match fs::read(file) {
        Ok(bytes) => bytes,
        Err(_) => return false,
    };
    let mut lines = 0usize;
    let mut start = 0usize;
    while lines < 5 && start <= bytes.len() {
        let end = bytes[start..]
            .iter()
            .position(|byte| *byte == b'\n')
            .map(|offset| start + offset)
            .unwrap_or(bytes.len());
        if is_part_line(&bytes[start..end]) {
            return true;
        }
        lines += 1;
        start = end + 1;
    }
    false
}

fn posix_space(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

fn is_part_line(line: &[u8]) -> bool {
    let mut index = 0usize;
    while index < line.len() && posix_space(line[index]) {
        index += 1;
    }
    if !line[index..].starts_with(b"part") {
        return false;
    }
    index += 4;
    let spaces = line[index..]
        .iter()
        .take_while(|byte| posix_space(**byte))
        .count();
    if spaces == 0 {
        return false;
    }
    index += spaces;
    match line.get(index) {
        Some(byte) => byte.is_ascii_alphabetic() || *byte == b'_',
        None => false,
    }
}

/// `basename -- PATH .plm`.
pub fn scene_name_of(path: &Path) -> String {
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    name.strip_suffix(".plm").unwrap_or(&name).to_string()
}

/// The scripts' `resolve_scene`. Prints the "no scene / several scenes" list and
/// returns `None` where the shell returned 1; the caller turns that into the
/// script's `die "... cannot resolve the scene ..."`.
pub fn resolve(ctx: &Ctx, argument: Option<&str>) -> Option<Scene> {
    let project = &ctx.project;
    if let Some(argument) = argument {
        if let Ok(metadata) = fs::metadata(argument) {
            if metadata.is_file() {
                let file = PathBuf::from(argument);
                return Some(Scene {
                    name: scene_name_of(&file),
                    file,
                });
            }
        }
        for directory in scene_dirs(project) {
            let base = directory
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_default();
            if base == argument {
                let file = directory.join(format!("{base}.plm"));
                if file.is_file() {
                    return Some(Scene { name: base, file });
                }
            }
        }
        for directory in scene_dirs(project) {
            let file = directory.join(format!("{argument}.plm"));
            if file.is_file() {
                return Some(Scene {
                    name: argument.to_string(),
                    file,
                });
            }
        }
        return None;
    }

    let mut found: Vec<Scene> = Vec::new();
    for file in scene_files(project) {
        if is_part_file(&file) {
            continue;
        }
        found.push(Scene {
            name: scene_name_of(&file),
            file,
        });
    }
    match found.len() {
        1 => Some(found.remove(0)),
        0 => {
            ctx.say(format!(
                "no scene found under {}",
                project.join("shells").display()
            ));
            None
        }
        _ => {
            ctx.say("several scenes found; name one of them:");
            for scene in &found {
                ctx.say(format!("  {}", scene.name));
            }
            None
        }
    }
}
