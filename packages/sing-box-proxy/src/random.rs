//! Small pseudo-random helper for `shuf`/`random.shuffle` replacements.
//!
//! The shell used `shuf` (subscriptions) and `random.shuffle` (validation) only
//! to spread samples; no cryptographic quality is required. Seeding from the
//! clock and the pid keeps consecutive runs independent.

use std::time::{SystemTime, UNIX_EPOCH};

fn seed() -> u64 {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos() as u64)
        .unwrap_or(0x9e37_79b9_7f4a_7c15);
    nanos ^ ((std::process::id() as u64) << 32) ^ 0x2545_f491_4f6c_dd1d
}

fn next_u64(state: &mut u64) -> u64 {
    let mut x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    x.wrapping_mul(0x2545_f491_4f6c_dd1d)
}

/// One pseudo-random 64-bit value (temp-file suffixes, seeds).
pub fn random_u64() -> u64 {
    let mut state = seed();
    next_u64(&mut state)
}

/// In-place Fisher-Yates shuffle.
pub fn shuffle<T>(items: &mut [T]) {
    if items.len() < 2 {
        return;
    }
    let mut state = seed();
    for index in (1..items.len()).rev() {
        let other = (next_u64(&mut state) % (index as u64 + 1)) as usize;
        items.swap(index, other);
    }
}
