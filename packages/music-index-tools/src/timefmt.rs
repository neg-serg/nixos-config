//! Local-time and duration formatting.
//!
//! `created` in `meta.json` is `time.strftime("%Y-%m-%dT%H:%M:%S")`, i.e. local
//! time. The only standard-library equivalent goes through `localtime_r`, so
//! the crate keeps a single small FFI block here instead of pulling in a
//! timezone-aware date crate for one field.

use std::ffi::{c_char, c_int, c_long};
use std::time::{SystemTime, UNIX_EPOCH};

#[repr(C)]
struct Tm {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    // glibc extensions; the leading fields above are the portable part.
    tm_gmtoff: c_long,
    tm_zone: *const c_char,
}

extern "C" {
    fn localtime_r(timep: *const i64, result: *mut Tm) -> *mut Tm;
}

/// Local timestamp in `%Y-%m-%dT%H:%M:%S` form.
pub fn local_timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs() as i64)
        .unwrap_or(0);
    // SAFETY: `localtime_r` writes a `struct tm` into the provided storage and
    // returns either that pointer or NULL. `Tm` mirrors glibc's layout; the
    // conversion below only reads the calendar fields it initialised.
    let mut tm: Tm = unsafe { std::mem::zeroed() };
    let ok = unsafe { !localtime_r(&seconds, &mut tm).is_null() };
    if !ok {
        // localtime_r fails only for unrepresentable timestamps; fall back to
        // the Unix epoch in UTC rather than panicking.
        return "1970-01-01T00:00:00".to_string();
    }
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec
    )
}

/// `time.strftime("%H:%M:%S", time.gmtime(seconds))`; `%H` wraps at 24 hours.
pub fn hms(seconds: f64) -> String {
    let total = if seconds.is_finite() && seconds > 0.0 {
        seconds as i64
    } else {
        0
    };
    let hours = (total / 3600) % 24;
    let minutes = (total / 60) % 60;
    let seconds = total % 60;
    format!("{hours:02}:{minutes:02}:{seconds:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_shape() {
        let stamp = local_timestamp();
        assert_eq!(stamp.len(), 19, "got {stamp}");
        assert_eq!(&stamp[4..5], "-");
        assert_eq!(&stamp[10..11], "T");
        assert_eq!(&stamp[13..14], ":");
    }

    #[test]
    fn hms_wraps_at_one_day() {
        assert_eq!(hms(0.0), "00:00:00");
        assert_eq!(hms(59.9), "00:00:59");
        assert_eq!(hms(3661.0), "01:01:01");
        assert_eq!(hms(86400.0 + 5.0), "00:00:05");
    }
}
