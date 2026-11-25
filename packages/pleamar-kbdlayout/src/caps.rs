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
