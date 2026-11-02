//! Unique temporary files, without a dependency on the `tempfile` crate.
//!
//! The shell used `mktemp "${TMPDIR:-/tmp}/<prefix>XXXXXX<suffix>"`, which
//! creates with `O_EXCL`. This module does the same: try `create_new` with a
//! random-looking six-character token, remove the file on drop and leave the
//! name pattern close to mktemp's (`shtoy-Ab12Cd.frag`).

use std::ffi::OsString;
use std::fs::{self, OpenOptions};
use std::io;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::env::Env;
use crate::Die;

static COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct TempFile {
    path: PathBuf,
}

impl TempFile {
    pub fn create(environment: &Env, prefix: &str, suffix: &str) -> Result<Self, Die> {
        let directory = match environment.get_nonempty("TMPDIR") {
            Some(value) => PathBuf::from(value),
            None => PathBuf::from("/tmp"),
        };
        for attempt in 0..128 {
            let candidate = directory.join(OsString::from(format!(
                "{prefix}{}{suffix}",
                random_token(attempt)
            )));
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                // mktemp's 0600 mode: the prepared copy may be shown on screen
                // but it is still a per-user temporary file.
                .mode(0o600)
                .open(&candidate)
            {
                Ok(_) => return Ok(Self { path: candidate }),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => {
                    return Err(Die::new(format!(
                        "cannot create a temporary file in {}: {error}",
                        directory.display()
                    )));
                }
            }
        }
        Err(Die::new(format!(
            "cannot create a temporary file in {}",
            directory.display()
        )))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn random_token(attempt: u64) -> String {
    const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.subsec_nanos() as u64)
        .unwrap_or(0);
    let mut state = nanos
        ^ (std::process::id() as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ attempt.wrapping_add(COUNTER.fetch_add(1, Ordering::Relaxed));
    let mut token = String::with_capacity(6);
    for _ in 0..6 {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        token.push(ALPHABET[(state % ALPHABET.len() as u64) as usize] as char);
    }
    token
}

#[cfg(test)]
mod tests {
    use super::TempFile;
    use crate::env::Env;
    use crate::test_support::TempDir;

    #[test]
    fn creates_distinct_files_inside_tmpdir_and_removes_them() {
        let root = TempDir::new("tempfile");
        let environment = Env::from_vars([("TMPDIR", root.path().to_string_lossy().into_owned())]);
        let first = TempFile::create(&environment, "shtoy-", ".frag").unwrap();
        let second = TempFile::create(&environment, "shtoy-", ".frag").unwrap();
        assert_ne!(first.path(), second.path());
        assert!(first.path().is_file());
        assert!(first.path().starts_with(root.path()));
        assert_eq!(
            first.path().extension().and_then(|value| value.to_str()),
            Some("frag")
        );
        let first_path = first.path().to_path_buf();
        drop(first);
        assert!(!first_path.exists());
    }

    #[test]
    fn missing_tmpdir_falls_back_to_tmp() {
        let environment = Env::from_vars(Vec::<(&str, &str)>::new());
        let temporary = TempFile::create(&environment, "shtoy-", ".frag").unwrap();
        assert!(temporary.path().starts_with("/tmp"));
    }
}
