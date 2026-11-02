//! Caps Lock detection.
//!
//! The compositor does not report Caps Lock: it is a kernel LED, one per
//! keyboard that has it (`/sys/class/leds/*capslock*/brightness`), which is
//! the only place a compositor-agnostic worker can see it. Any lit LED means
//! the next letter is a capital, which is exactly what a password field must
//! say out loud. This mirrors `caps_locked()` in `kbd.sh`.

use std::fs;
use std::path::Path;

/// Where the kernel exposes the keyboard LEDs.
pub const LED_ROOT: &str = "/sys/class/leds";

/// True when any `*capslock*` LED is lit.
///
/// The directory is a parameter so tests can build a fake LED tree; production
/// passes [`LED_ROOT`]. A missing tree or an unreadable LED counts as "off",
/// exactly like the shell's failed `[ -r … ]` guard.
pub fn caps_locked(root: &Path) -> bool {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(_) => return false,
    };
    for entry in entries.flatten() {
        if !entry.file_name().to_string_lossy().contains("capslock") {
            continue;
        }
        let brightness = entry.path().join("brightness");
        match fs::read_to_string(&brightness) {
            // `$(cat …)` strips trailing newlines before the comparison.
            Ok(text) if text.trim_end_matches('\n') == "1" => return true,
            _ => {}
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            static SEQUENCE: AtomicU64 = AtomicU64::new(0);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_nanos())
                .unwrap_or(0);
            let path = std::env::temp_dir().join(format!(
                "pleamar-kbdlayout-caps-{label}-{}-{nanos}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).expect("test directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn led(root: &Path, name: &str, value: &str) {
        let directory = root.join(name);
        fs::create_dir_all(&directory).expect("led directory");
        fs::write(directory.join("brightness"), value).expect("brightness");
    }

    #[test]
    fn missing_tree_is_off() {
        let directory = TempDir::new("missing");
        assert!(!caps_locked(&directory.path().join("absent")));
    }

    #[test]
    fn empty_tree_is_off() {
        let directory = TempDir::new("empty");
        assert!(!caps_locked(directory.path()));
    }

    #[test]
    fn a_lit_capslock_led_is_on() {
        let directory = TempDir::new("lit");
        led(directory.path(), "input4::capslock", "1\n");
        assert!(caps_locked(directory.path()));
    }

    #[test]
    fn unlit_leds_are_off() {
        let directory = TempDir::new("unlit");
        led(directory.path(), "input4::capslock", "0\n");
        led(directory.path(), "input5::numlock", "1\n");
        assert!(!caps_locked(directory.path()));
    }

    #[test]
    fn any_lit_capslock_wins() {
        let directory = TempDir::new("any");
        led(directory.path(), "input1::capslock", "0\n");
        led(directory.path(), "input2::capslock", "1\n");
        assert!(caps_locked(directory.path()));
    }

    #[test]
    fn non_capslock_leds_are_ignored() {
        let directory = TempDir::new("other");
        led(directory.path(), "input1::scrolllock", "1\n");
        assert!(!caps_locked(directory.path()));
    }
}
