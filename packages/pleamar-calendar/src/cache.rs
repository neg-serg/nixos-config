//! Byte caches: `calendar-YYYY-MM.json`, `holidays-YYYY-CC.json` and
//! `workdays-YYYY-YYYY-MM-CC.txt`.
//!
//! The first two are jq compact documents with a trailing newline (`jq -c >
//! tmp`, then `mv -f`); the third is the raw isdayoff digit string with no
//! newline (`printf '%s' "$body" > tmp`). The file mode is the shell
//! redirect's: 0666 masked by the umask (0644 on this host), not mktemp's
//! 0600. Writes stay atomic: a private temp file next to the target, then a
//! rename over it.
//!
//! Freshness is the shell's `stat -c %Y` + `NOW - mtime < TTL` for the
//! holiday/workday files, and the document's own `fetched_at` for the calendar
//! payload (120 s). A stat failure was `|| echo 0`, i.e. stale.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::UNIX_EPOCH;

static ATTEMPT: AtomicU64 = AtomicU64::new(0);

/// `stat -c %Y` in seconds; `None` made the shell treat the cache as stale.
pub fn mtime_secs(path: &Path) -> Option<i64> {
    let modified = fs::metadata(path).ok()?.modified().ok()?;
    modified
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_secs() as i64)
}

/// The shell's `age=$((NOW - mtime)); [ "$age" -lt "$ttl" ]`: a future mtime
/// (negative age) counted as fresh.
pub fn fresh(path: &Path, now: i64, ttl_secs: i64) -> bool {
    mtime_secs(path).is_some_and(|mtime| now.saturating_sub(mtime) < ttl_secs)
}

/// Read a text cache, dropping trailing newlines the way bash's `$(< file)`
/// does. A missing or unreadable file is `None`.
pub fn read_text(path: &Path) -> Option<String> {
    let text = fs::read_to_string(path).ok()?;
    Some(text.trim_end_matches('\n').to_string())
}

/// `mkdir -p` + temp file + `mv -f`.
pub fn write_atomic(path: &Path, document: &[u8], prefix: &str) -> io::Result<()> {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty());
    if let Some(directory) = directory {
        fs::create_dir_all(directory)?;
    }
    let directory = directory.unwrap_or_else(|| Path::new("."));
    let mut attempt = 0;
    loop {
        let temp = temp_path(directory, prefix);
        let mut file = match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            // The shell redirected with `>`: 0666 & ~umask.
            .mode(0o666)
            .open(&temp)
        {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists && attempt < 128 => {
                attempt += 1;
                continue;
            }
            Err(error) => return Err(error),
        };
        let result = file
            .write_all(document)
            .and_then(|()| file.flush())
            .and_then(|()| {
                drop(file);
                fs::rename(&temp, path)
            });
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        return result;
    }
}

fn temp_path(directory: &Path, prefix: &str) -> PathBuf {
    directory.join(format!(
        ".{prefix}.{}.{}.tmp",
        std::process::id(),
        ATTEMPT.fetch_add(1, Ordering::Relaxed)
    ))
}
