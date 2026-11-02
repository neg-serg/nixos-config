//! `strflocaltime("%H:%M")` — the shell let jq format epoch seconds in the
//! host's local timezone (that is the fix that made the journal times real;
//! `strftime` had printed UTC). chrono's `Local` goes through the same libc
//! `localtime_r`, so `TZ`, DST transitions and the fallback for a broken zone
//! behave like jq's strftime.
//!
//! `None` means jq's `strflocaltime` would have raised
//! "error converting number of seconds since epoch to datetime" (out of the
//! time_t range): the whole jq program fails, which the shell turns into
//! `entries: []` through its `|| echo '[]'` fallback.

use chrono::{Local, TimeZone};

/// Convert the shell's `(microseconds / 1000000)` number into local `HH:MM`.
/// The float-to-integer step truncates toward zero, like the C cast jq does
/// before calling `localtime_r`.
pub fn hh_mm_from_micros(micros: f64) -> Option<String> {
    let seconds = (micros / 1_000_000.0) as i64;
    let datetime = Local.timestamp_opt(seconds, 0).single()?;
    Some(datetime.format("%H:%M").to_string())
}
