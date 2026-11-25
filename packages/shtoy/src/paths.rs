//! Directory layout and `--list` output.
//!
//! The shell computed the three paths once at startup:
//!   $XDG_CACHE_HOME/shtoy          (default: $HOME/.cache/shtoy)
//!   $XDG_CONFIG_HOME/shtoy/shaders (default: $HOME/.config/shtoy/shaders)
//!   $XDG_CONFIG_HOME/shtoy/api_key
//! An empty XDG variable is treated as unset, matching `${VAR:-default}`.

use std::ffi::OsString;
use std::fs;
use std::io::Write as _;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::env::Env;
use crate::Die;

#[derive(Debug)]
pub struct Paths {
    pub cache_dir: PathBuf,
    pub shader_dir: PathBuf,
    pub api_key_file: PathBuf,
}

impl Paths {
    pub fn from_env(environment: &Env) -> Result<Self, Die> {
        let home = environment
            .get_nonempty("HOME")
            .ok_or_else(|| Die::new("HOME is not set"))?;
        let home = PathBuf::from(home);
        let config = xdg_dir(environment, "XDG_CONFIG_HOME", home.join(".config"));
        let cache = xdg_dir(environment, "XDG_CACHE_HOME", home.join(".cache"));
        Ok(Self {
            cache_dir: cache.join("shtoy"),
            shader_dir: config.join("shtoy").join("shaders"),
            api_key_file: config.join("shtoy").join("api_key"),
        })
    }

    /// `--list`: cached ids first, then shipped ids that the cache does not
    /// shadow, each group in file-name order. `*.frag` entries are taken as the
    /// shell glob took them: hidden names are skipped, directories and symlinks
    /// still count, and only a regular file shadows a shipped id (`-f`).
    pub fn list_shaders(&self) -> Result<String, Die> {
        let cached = frag_names(&self.cache_dir);
        let shipped = frag_names(&self.shader_dir);
        if cached.is_empty() && shipped.is_empty() {
            return Err(Die::new("no cached or shipped shaders"));
        }

        let mut output = String::new();
        for name in &cached {
            output.push_str(&frag_stem(name));
            output.push('\n');
        }
        for name in &shipped {
            if !self.cache_dir.join(name).is_file() {
                output.push_str(&frag_stem(name));
                output.push_str(" (shipped)\n");
            }
        }
        Ok(output)
    }
}

fn xdg_dir(environment: &Env, key: &str, fallback: PathBuf) -> PathBuf {
    environment
        .get_nonempty(key)
        .map(PathBuf::from)
        .unwrap_or(fallback)
}

/// Names matching the shell's `"$DIR"/*.frag` glob, in file-name order.
fn frag_names(directory: &Path) -> Vec<OsString> {
    let mut names = Vec::new();
    let Ok(entries) = fs::read_dir(directory) else {
        // A missing or unreadable directory simply had no glob matches.
        return names;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let bytes = name.as_bytes();
        if bytes.first() == Some(&b'.') {
            continue;
        }
        if bytes.ends_with(b".frag") {
            names.push(name);
        }
    }
    sort_names(&mut names);
    names
}

/// Bash sorts glob matches with `strcoll` in the process locale, so the shell's
/// `--list` order depended on LANG/LC_COLLATE (en_US.UTF-8, for example,
/// compares case-insensitively). The same collation is available from the
/// system `sort`; use it first and fall back to byte order when `sort` is not
/// on PATH, so the order stays valid outside a normal user environment.
fn sort_names(names: &mut Vec<OsString>) {
    if names.len() < 2 {
        return;
    }
    if let Some(sorted) = sort_with_system_util(names) {
        *names = sorted;
        return;
    }
    names.sort_by(|left, right| left.as_bytes().cmp(right.as_bytes()));
}

fn sort_with_system_util(names: &[OsString]) -> Option<Vec<OsString>> {
    let mut child = Command::new("sort")
        .arg("-z")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    {
        let mut stdin = child.stdin.take()?;
        for name in names {
            stdin.write_all(name.as_bytes()).ok()?;
            stdin.write_all(b"\0").ok()?;
        }
    }
    let output = child.wait_with_output().ok()?;
    if !output.status.success() {
        return None;
    }
    let sorted: Vec<OsString> = output
        .stdout
        .split(|byte| *byte == 0)
        .filter(|chunk| !chunk.is_empty())
        .map(|chunk| OsString::from_vec(chunk.to_vec()))
        .collect();
    if sorted.len() != names.len() {
        return None;
    }
    Some(sorted)
}

fn frag_stem(name: &OsString) -> String {
    let text = name.to_string_lossy();
    text.strip_suffix(".frag").unwrap_or(&text).to_string()
}
