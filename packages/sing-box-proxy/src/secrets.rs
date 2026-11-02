//! Secret file loaders.
//!
//! Same semantics as the shell:
//! - `load_fallback` returns the raw file content when the secret exists (the
//!   callers strip trailing newlines like `$(...)` did) and `None` when it does
//!   not; the script has no hardcoded fallback nodes.
//! - `load_lan_auth` returns the file content with trailing newlines stripped
//!   (command substitution), or `""` when the secret is absent/unreadable.
//!
//! Paths come from `paths::Paths`, so the defaults stay `/run/secrets/...`.

use crate::paths::Paths;
use std::fs;
use std::io;

pub fn load_fallback(paths: &Paths) -> io::Result<Option<String>> {
    if !paths.secret.is_file() {
        return Ok(None);
    }
    fs::read_to_string(&paths.secret).map(Some)
}

pub fn load_lan_auth(paths: &Paths) -> String {
    if !paths.lan_secret.is_file() {
        return String::new();
    }
    fs::read_to_string(&paths.lan_secret)
        .map(|text| text.trim_end_matches('\n').to_string())
        .unwrap_or_default()
}
