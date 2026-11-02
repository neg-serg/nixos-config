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

#[cfg(test)]
mod tests {
    use super::Paths;
    use crate::env::Env;
    use crate::test_support::TempDir;

    fn paths(root: &TempDir) -> Paths {
        let environment = Env::from_vars([
            ("HOME", root.path().to_string_lossy().into_owned()),
            (
                "XDG_CACHE_HOME",
                root.path().join("cache").to_string_lossy().into_owned(),
            ),
            (
                "XDG_CONFIG_HOME",
                root.path().join("config").to_string_lossy().into_owned(),
            ),
        ]);
        Paths::from_env(&environment).expect("paths")
    }

    #[test]
    fn empty_xdg_variables_fall_back_to_home() {
        let root = TempDir::new("paths-empty");
        let home = root.path().to_string_lossy().into_owned();
        let environment = Env::from_vars([
            ("HOME", home.as_str()),
            ("XDG_CACHE_HOME", ""),
            ("XDG_CONFIG_HOME", ""),
        ]);
        let paths = Paths::from_env(&environment).expect("paths");
        assert_eq!(paths.cache_dir, root.path().join(".cache/shtoy"));
        assert_eq!(paths.shader_dir, root.path().join(".config/shtoy/shaders"));
        assert_eq!(
            paths.api_key_file,
            root.path().join(".config/shtoy/api_key")
        );
    }

    #[test]
    fn listing_puts_cached_first_and_marks_unshadowed_shipped_ids() {
        let root = TempDir::new("paths-list");
        let paths = paths(&root);
        std::fs::create_dir_all(&paths.cache_dir).unwrap();
        std::fs::create_dir_all(&paths.shader_dir).unwrap();
        for name in ["beta", "Alpha", "zeta"] {
            std::fs::write(paths.cache_dir.join(format!("{name}.frag")), b"x").unwrap();
        }
        for name in ["Alpha", "alpha", "gamma"] {
            std::fs::write(paths.shader_dir.join(format!("{name}.frag")), b"x").unwrap();
        }
        // Byte order in the C locale: uppercase first.
        assert_eq!(
            paths.list_shaders().unwrap(),
            "Alpha\nbeta\nzeta\nalpha (shipped)\ngamma (shipped)\n"
        );
    }

    #[test]
    fn hidden_entries_are_not_listed_and_directories_are_listed_but_shadow_nothing() {
        let root = TempDir::new("paths-hidden");
        let paths = paths(&root);
        std::fs::create_dir_all(&paths.cache_dir).unwrap();
        std::fs::create_dir_all(&paths.shader_dir).unwrap();
        std::fs::write(paths.cache_dir.join(".hidden.frag"), b"x").unwrap();
        std::fs::create_dir_all(paths.cache_dir.join("shadowed.frag")).unwrap();
        std::fs::write(paths.shader_dir.join("shadowed.frag"), b"x").unwrap();
        // The glob took the directory named shadowed.frag as a match, so it is
        // listed as a cached id, while only a regular file can shadow the
        // shipped id (`[ -f ... ]`).
        assert_eq!(
            paths.list_shaders().unwrap(),
            "shadowed\nshadowed (shipped)\n"
        );
    }

    #[test]
    fn no_shaders_anywhere_is_an_error() {
        let root = TempDir::new("paths-none");
        let paths = paths(&root);
        let error = paths.list_shaders().unwrap_err().to_string();
        assert_eq!(error, "no cached or shipped shaders");
    }
}
