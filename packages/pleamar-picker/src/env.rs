//! Environment: the cache directory, HOME and the state directory the caches
//! live in. The rules are the shell's `${XDG_CACHE_HOME:-$HOME/.cache}` and
//! `$HOME/.local/state/wl`, including the empty-variable cases.

use std::ffi::{OsStr, OsString};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::path::PathBuf;

/// `$NAME`, set or unset (an empty value stays empty).
pub fn var(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

/// `${NAME:-…}`: an empty value counts as unset.
pub fn nonempty(name: &str) -> Option<OsString> {
    var(name).filter(|value| !value.is_empty())
}

/// `$HOME` presence — the shell's `set -u` only cares whether it is set.
pub fn home() -> Option<OsString> {
    var("HOME")
}

/// `base + suffix` with no path normalisation, so an empty `$HOME` becomes
/// `/.cache` exactly as `"${HOME}/.cache"` did.
pub fn append(base: &OsStr, suffix: &str) -> PathBuf {
    let mut bytes = base.as_bytes().to_vec();
    bytes.extend_from_slice(suffix.as_bytes());
    PathBuf::from(OsString::from_vec(bytes))
}

/// The cache root for a command without `set -u`: `$XDG_CACHE_HOME` when
/// non-empty, else `$HOME/.cache` (missing HOME gives `/ .cache`, as the
/// still helper's `$HOME` expansion did).
pub fn cache_lenient() -> PathBuf {
    if let Some(xdg) = nonempty("XDG_CACHE_HOME") {
        return PathBuf::from(xdg);
    }
    append(&home().unwrap_or_default(), "/.cache")
}

/// The cache root for a command under `set -u`: `$XDG_CACHE_HOME` when
/// non-empty, else a set `$HOME` `.cache`, else `None` (the shell died on the
/// unbound variable).
pub fn cache_required() -> Option<PathBuf> {
    if let Some(xdg) = nonempty("XDG_CACHE_HOME") {
        return Some(PathBuf::from(xdg));
    }
    home().map(|home| append(&home, "/.cache"))
}

/// The cache root once `$HOME` is already required: `$XDG_CACHE_HOME` wins.
pub fn cache_with_home(home: &OsStr) -> PathBuf {
    if let Some(xdg) = nonempty("XDG_CACHE_HOME") {
        PathBuf::from(xdg)
    } else {
        append(home, "/.cache")
    }
}

/// `$HOME/.local/state/wl`, the wl-daemon fallback directory.
pub fn wl_state(home: &OsStr) -> PathBuf {
    append(home, "/.local/state/wl")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn append_keeps_an_empty_base_absolute() {
        assert_eq!(append(OsStr::new(""), "/.cache"), PathBuf::from("/.cache"));
        assert_eq!(
            append(OsStr::new("/home/u"), "/.local/state/wl"),
            PathBuf::from("/home/u/.local/state/wl")
        );
    }
}
