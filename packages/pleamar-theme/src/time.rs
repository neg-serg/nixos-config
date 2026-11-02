//! The `// written:` stamp, formatted exactly like `date -u +%Y-%m-%dT%H:%M:%SZ`.
//!
//! std has a clock but no calendar formatting, so the civil-date conversion is
//! here (Howard Hinnant's `civil_from_days`). The generated file carries the
//! stamp only so a human can see when it was written; the unchanged check
//! strips it.

use std::time::{SystemTime, UNIX_EPOCH};

/// Whole seconds since the Unix epoch, the way `date` truncates the clock.
pub fn now_seconds() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => i64::try_from(duration.as_secs()).unwrap_or(i64::MAX),
        Err(error) => -i64::try_from(error.duration().as_secs()).unwrap_or(i64::MAX),
    }
}

/// The current UTC time as `YYYY-MM-DDTHH:MM:SSZ`.
pub fn utc_timestamp_now() -> String {
    format_utc(now_seconds())
}

/// Format whole seconds since the Unix epoch as the shell's `date -u` did.
pub fn format_utc(seconds: i64) -> String {
    let days = seconds.div_euclid(86_400);
    let time = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        time / 3600,
        (time % 3600) / 60,
        time % 60
    )
}

/// Days since 1970-01-01 to a proleptic Gregorian date.
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let shifted = days + 719_468;
    let era = if shifted >= 0 {
        shifted
    } else {
        shifted - 146_096
    } / 146_097;
    let day_of_era = shifted - era * 146_097; // [0, 146096]
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_position = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_position + 2) / 5 + 1;
    let month = if month_position < 10 {
        month_position + 3
    } else {
        month_position - 9
    };
    (if month <= 2 { year + 1 } else { year }, month, day)
}

#[cfg(test)]
mod tests {
    use super::format_utc;

    #[test]
    fn epochs_match_date_u() {
        assert_eq!(format_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_utc(951_827_696), "2000-02-29T12:34:56Z");
        assert_eq!(format_utc(1_735_689_599), "2024-12-31T23:59:59Z");
        assert_eq!(format_utc(1_793_654_861), "2026-11-02T21:27:41Z");
    }
}
