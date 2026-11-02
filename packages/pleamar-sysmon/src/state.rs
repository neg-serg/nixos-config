//! The private counter-state file.
//!
//! The shell keeps the previous `/proc/stat` and `/proc/diskstats` counters in
//! a `mktemp` file under `$TMPDIR` (`pleamar-sysmon.XXXXXX`, mode 0600) so one
//! sampling process can hand the baseline to the next. The format is the awk
//! program's: `"<cpu_total> <cpu_idle>\n<disk_read> <disk_write>\n"`.

use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static ATTEMPT: AtomicU64 = AtomicU64::new(0);

/// RAII owner of the state file: dropping it removes the file, mirroring the
/// shell's `trap cleanup EXIT`.
#[derive(Debug)]
pub struct StateFile {
    path: PathBuf,
}

impl StateFile {
    /// Create the state file where the shell's `mktemp` would: `$TMPDIR` (or
    /// `/tmp` when unset or empty), with a `pleamar-sysmon.XXXXXX` name.
    pub fn create() -> io::Result<Self> {
        let base = env::var_os("TMPDIR")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/tmp"));
        Self::create_in(&base)
    }

    pub fn create_in(directory: &Path) -> io::Result<Self> {
        use std::os::unix::fs::OpenOptionsExt;

        for _ in 0..128 {
            let path = directory.join(format!("pleamar-sysmon.{}", random_suffix()));
            match fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&path)
            {
                Ok(_) => return Ok(Self { path }),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "cannot create a unique state file name",
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for StateFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn random_suffix() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let mut state =
        nanos ^ ((process::id() as u128) << 32) ^ (ATTEMPT.fetch_add(1, Ordering::Relaxed) as u128);
    let mut suffix = String::with_capacity(6);
    for _ in 0..6 {
        // xorshift64* over the low bits; the suffix only has to be unique
        // enough for a per-process temporary file.
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        suffix.push(ALPHABET[(state % ALPHABET.len() as u128) as usize] as char);
    }
    suffix
}

/// Previous counters. `None` is the awk `-1` sentinel: the state file had no
/// usable line, so the next sample seeds the baseline instead of averaging
/// from zero.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counters {
    pub cpu: Option<(u64, u64)>,
    pub disk: Option<(u64, u64)>,
}

pub fn read(path: &Path) -> Counters {
    let text = fs::read_to_string(path).unwrap_or_default();
    let mut lines = text.split('\n');
    let cpu = lines.next().and_then(parse_pair);
    let disk = lines.next().and_then(parse_pair);
    Counters { cpu, disk }
}

fn parse_pair(line: &str) -> Option<(u64, u64)> {
    let mut fields = line.split_whitespace();
    let first = fields.next()?;
    let second = fields.next()?;
    Some((parse_counter(first), parse_counter(second)))
}

/// awk reads the counters with `f[1] + 0`: a malformed field becomes zero.
fn parse_counter(field: &str) -> u64 {
    field.parse::<u64>().unwrap_or(0)
}

pub fn write(path: &Path, cpu: (u64, u64), disk: (u64, u64)) -> io::Result<()> {
    let contents = format!("{} {}\n{} {}\n", cpu.0, cpu.1, disk.0, disk.1);
    fs::write(path, contents)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::TempDir;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn create_uses_the_prefix_and_private_mode() {
        let dir = TempDir::new("state-create");
        let state = StateFile::create_in(dir.path()).expect("state file");
        let name = state
            .path()
            .file_name()
            .expect("name")
            .to_string_lossy()
            .into_owned();
        assert!(
            name.starts_with("pleamar-sysmon."),
            "unexpected name {name}"
        );
        assert_eq!(name.len(), "pleamar-sysmon.".len() + 6);
        let mode = fs::metadata(state.path())
            .expect("metadata")
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
        let path = state.path().to_path_buf();
        drop(state);
        assert!(!path.exists(), "dropping the state must remove the file");
    }

    #[test]
    fn write_and_read_round_trip() {
        let dir = TempDir::new("state-round-trip");
        let state = StateFile::create_in(dir.path()).expect("state file");
        write(state.path(), (1234, 567), (89, 10)).expect("write");
        assert_eq!(
            read(state.path()),
            Counters {
                cpu: Some((1234, 567)),
                disk: Some((89, 10)),
            }
        );
        assert_eq!(
            fs::read_to_string(state.path()).expect("text"),
            "1234 567\n89 10\n"
        );
    }

    #[test]
    fn missing_file_means_no_baseline() {
        let counters = read(Path::new("/nonexistent/pleamar-sysmon.state"));
        assert_eq!(counters, Counters::default());
    }

    #[test]
    fn malformed_fields_become_zero_like_awk() {
        let dir = TempDir::new("state-malformed");
        let path = dir.path().join("state");
        fs::write(&path, "abc def\n1\n").expect("write");
        assert_eq!(
            read(&path),
            Counters {
                cpu: Some((0, 0)),
                disk: None,
            }
        );
    }
}
