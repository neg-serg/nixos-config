//! The path/environment setup the shell performed at the top of the script.
//!
//! Every value is kept as bytes and concatenated exactly like the shell did
//! (`"$HOME/tmp"`), including the leading slash when HOME happens to be empty.
//! Directory creation mirrors the shell's `mkdir -p` calls: failures are not
//! fatal there either (the script has no `set -e`).

use std::env;
use std::fs;
use std::path::PathBuf;

use crate::bytes::{join, os_owned};

pub struct Paths {
    pub home: Vec<u8>,
    /// `$HOME/tmp`
    pub cache: Vec<u8>,
    /// `$HOME/tmp/swayimg.$$`
    pub tmp_file: Vec<u8>,
    /// `$HOME/tmp/wall_swww.$$`
    pub tmp_wall: Vec<u8>,
    /// `$XDG_DATA_HOME/swayimg`
    pub swayimg_dir: Vec<u8>,
    /// `$XDG_DATA_HOME/swayimg/last`
    pub last_file: Vec<u8>,
    /// `$XDG_DATA_HOME/swayimg/range_mark`
    pub range_file: Vec<u8>,
    /// `$XDG_DATA_HOME/wl/wallpaper.list`
    pub wallpaper_list: Vec<u8>,
    /// `$HOME/trash/1st-level/pic`
    pub trash: Vec<u8>,
    /// `$XDG_PICTURES_DIR` (or `$HOME/Pictures`)
    pub pictures: Vec<u8>,
}

fn variable(name: &str) -> Option<Vec<u8>> {
    env::var_os(name).map(|value| {
        use std::os::unix::ffi::OsStringExt;
        value.into_vec()
    })
}

fn non_empty(name: &str) -> Option<Vec<u8>> {
    variable(name).filter(|value| !value.is_empty())
}

impl Paths {
    pub fn from_env() -> Self {
        let home = variable("HOME").unwrap_or_default();
        let cache = join(&home, b"tmp");
        let pid = std::process::id();
        let tmp_file = join(&cache, format!("swayimg.{pid}").as_bytes());
        let tmp_wall = join(&cache, format!("wall_swww.{pid}").as_bytes());
        let data = non_empty("XDG_DATA_HOME").unwrap_or_else(|| join(&home, b".local/share"));
        let swayimg_dir = join(&data, b"swayimg");
        let last_file = join(&swayimg_dir, b"last");
        let range_file = join(&swayimg_dir, b"range_mark");
        let wallpaper_list = join(&data, b"wl/wallpaper.list");
        let trash = join(&home, b"trash/1st-level/pic");
        let pictures = non_empty("XDG_PICTURES_DIR").unwrap_or_else(|| join(&home, b"Pictures"));
        Self {
            home,
            cache,
            tmp_file,
            tmp_wall,
            swayimg_dir,
            last_file,
            range_file,
            wallpaper_list,
            trash,
            pictures,
        }
    }

    /// The script's startup `mkdir -p` calls. Errors are ignored: without
    /// `set -e` the script continued and let the individual writes fail.
    pub fn create(&self) {
        let _ = fs::create_dir_all(path(&self.cache));
        let _ = fs::create_dir_all(path(&self.swayimg_dir));
    }
}

pub fn path(bytes: &[u8]) -> PathBuf {
    PathBuf::from(os_owned(bytes))
}

/// `trap finish EXIT`: the shell removed both temp files on every exit path
/// after the trap was installed (help exits before that and never creates one).
pub struct Cleanup {
    tmp_file: Vec<u8>,
    tmp_wall: Vec<u8>,
}

impl Cleanup {
    pub fn new(paths: &Paths) -> Self {
        Self {
            tmp_file: paths.tmp_file.clone(),
            tmp_wall: paths.tmp_wall.clone(),
        }
    }
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        let _ = fs::remove_file(path(&self.tmp_file));
        let _ = fs::remove_file(path(&self.tmp_wall));
    }
}
