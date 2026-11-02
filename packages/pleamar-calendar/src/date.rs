//! Dates, as the shell got them from GNU `date`.
//!
//! `set_month` accepted `YYYY-MM` and `YYYY-MM-DD` (the day was dropped
//! without being validated), then built the month range with
//! `date -d "$FIRST +1 month -1 day"` and the dd.mm.yyyy forms with
//! `date -d`. khal's `{start-date}` was normalised the same way. This module
//! does the same arithmetic on `chrono` dates: the default month comes from
//! the local wall clock (`date +%Y-%m`), month ranges are calendar-correct for
//! leap years and year boundaries, and khal's two documented date forms (ISO
//! and `%d.%m.%Y`) normalise to ISO.
//!
//! GNU `date -d` accepts far more spellings ("tomorrow", RFC 2822, …). The
//! shell's pipeline only produced ISO and dd.mm.yyyy — khal's output and the
//! two CLI formats — so anything else stays as khal printed it, exactly the
//! shell's fallback when `date -d` failed.

use chrono::{Datelike, Days, Local, NaiveDate};

/// One month of the calendar, with the four strings the shell kept in
/// `MONTH`/`FIRST`/`LAST`/`FIRST_EU`/`LAST_EU`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Month {
    pub year: i32,
    pub number: u32,
    pub first: String,
    pub last: String,
    pub first_eu: String,
    pub last_eu: String,
}

impl Month {
    /// `set_month`: `YYYY-MM` or `YYYY-MM-DD`, day ignored, month validated by
    /// the date arithmetic the shell attempted.
    pub fn parse(raw: &str) -> Option<Self> {
        let text = raw.as_bytes();
        let month_text = match text.len() {
            7 => {
                if !is_year_dash_month(text) {
                    return None;
                }
                &raw[..7]
            }
            10 => {
                if !is_year_dash_month(text)
                    || text[7] != b'-'
                    || !text[8..10].iter().all(|byte| byte.is_ascii_digit())
                {
                    return None;
                }
                &raw[..7]
            }
            _ => return None,
        };

        let year: i32 = month_text[..4].parse().ok()?;
        let number: u32 = month_text[5..7].parse().ok()?;
        if !(1..=12).contains(&number) {
            return None;
        }
        let first = NaiveDate::from_ymd_opt(year, number, 1)?;
        let last = NaiveDate::from_ymd_opt(year, number, days_in_month(year, number))?;
        Some(Self {
            year,
            number,
            first: iso(first),
            last: iso(last),
            first_eu: european(first),
            last_eu: european(last),
        })
    }

    /// `$MONTH`: `YYYY-MM`.
    pub fn name(&self) -> String {
        format!("{:04}-{:02}", self.year, self.number)
    }

    /// `$YEAR`: the text before the dash (the shell's `${MONTH%%-*}`).
    pub fn year_text(&self) -> String {
        format!("{:04}", self.year)
    }

    /// `${MONTH#*-}`: the two-digit month.
    pub fn month_text(&self) -> String {
        format!("{:02}", self.number)
    }
}

/// The shell's `date +%Y-%m` default (local time, like every `date` call).
pub fn current_month() -> String {
    Local::now().format("%Y-%m").to_string()
}

/// `date -d "$raw_date" +%F` for the two forms khal can print; anything else
/// is returned untouched, as the shell did when `date` failed.
pub fn normalize_date(raw: &str) -> String {
    if let Some(date) = parse_iso(raw) {
        return iso(date);
    }
    if let Some(date) = parse_european(raw) {
        return iso(date);
    }
    raw.to_string()
}

/// jq's `prevday` from the pill filter: `strptime("%Y-%m-%d") | mktime - 86400
/// | strftime("%Y-%m-%d")`. The filter compares calendar days, so one day
/// before the parsed date is the same string (mktime/strftime round-trip in
/// the host time zone; no DST transition moves a date that far).
pub fn previous_day(day: &str) -> Option<String> {
    let date = parse_iso(day)?;
    date.checked_sub_days(Days::new(1)).map(iso)
}

fn is_year_dash_month(text: &[u8]) -> bool {
    text[4] == b'-'
        && text[..4].iter().all(|byte| byte.is_ascii_digit())
        && text[5..7].iter().all(|byte| byte.is_ascii_digit())
}

fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        _ if is_leap_year(year) => 29,
        _ => 28,
    }
}

fn is_leap_year(year: i32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn iso(date: NaiveDate) -> String {
    format!("{:04}-{:02}-{:02}", date.year(), date.month(), date.day())
}

fn european(date: NaiveDate) -> String {
    format!("{:02}.{:02}.{:04}", date.day(), date.month(), date.year())
}

/// GNU `date -d` for `YYYY-MM-DD` (month and day may be one digit).
fn parse_iso(text: &str) -> Option<NaiveDate> {
    let mut parts = text.split('-');
    let year = parts.next()?;
    let month = parts.next()?;
    let day = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    if year.len() != 4 || !year.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let year: i32 = year.parse().ok()?;
    let month: u32 = parse_component(month, 2)?;
    let day: u32 = parse_component(day, 2)?;
    NaiveDate::from_ymd_opt(year, month, day)
}

/// GNU `date -d` for `%d.%m.%Y`; the two-digit year follows GNU's pivot
/// (00..68 -> 2000..2068, 69..99 -> 1969..1999).
fn parse_european(text: &str) -> Option<NaiveDate> {
    let mut parts = text.split('.');
    let day = parts.next()?;
    let month = parts.next()?;
    let year = parts.next()?;
    if parts.next().is_some() {
        return None;
    }
    let day: u32 = parse_component(day, 2)?;
    let month: u32 = parse_component(month, 2)?;
    let year: i32 = match year.len() {
        2 if year.bytes().all(|byte| byte.is_ascii_digit()) => {
            let value: i32 = year.parse().ok()?;
            if value < 69 {
                value + 2000
            } else {
                value + 1900
            }
        }
        4 if year.bytes().all(|byte| byte.is_ascii_digit()) => year.parse().ok()?,
        _ => return None,
    };
    NaiveDate::from_ymd_opt(year, month, day)
}

fn parse_component(text: &str, width: usize) -> Option<u32> {
    if text.is_empty() || text.len() > width || !text.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn month_ranges_match_gnu_date() {
        let month = Month::parse("2026-11").expect("month");
        assert_eq!(month.first, "2026-11-01");
        assert_eq!(month.last, "2026-11-30");
        assert_eq!(month.first_eu, "01.11.2026");
        assert_eq!(month.last_eu, "30.11.2026");
        assert_eq!(month.name(), "2026-11");
        assert_eq!(month.year_text(), "2026");
        assert_eq!(month.month_text(), "11");

        assert_eq!(Month::parse("2026-02").expect("feb").last, "2026-02-28");
        assert_eq!(Month::parse("2024-02").expect("leap").last, "2024-02-29");
        assert_eq!(Month::parse("2026-12").expect("dec").last, "2026-12-31");
        assert_eq!(Month::parse("2026-01").expect("jan").last, "2026-01-31");
        // GNU date handled both extremes: `date -d '0000-01-01 +1 month -1 day'`
        // and `9999-12-01 +1 month -1 day` succeed.
        assert_eq!(
            Month::parse("0000-01").expect("year zero").last,
            "0000-01-31"
        );
        assert_eq!(
            Month::parse("9999-12").expect("year max").last,
            "9999-12-31"
        );
    }

    #[test]
    fn month_accepts_a_day_and_ignores_its_value() {
        // `${raw%-*}` dropped the day without validating it.
        assert_eq!(
            Month::parse("2026-11-05").expect("iso day").name(),
            "2026-11"
        );
        assert_eq!(
            Month::parse("2026-11-99").expect("bad day").name(),
            "2026-11"
        );
    }

    #[test]
    fn month_rejects_what_gnu_date_rejected() {
        for value in [
            "",
            "2026-1",
            "202611",
            "2026-13",
            "2026-00",
            "2026-1a",
            "20-11",
            "2026/11",
            "2026-11-5",
            "2026-11-05x",
            "abcd-ef",
        ] {
            assert!(Month::parse(value).is_none(), "{value}");
        }
    }

    #[test]
    fn khal_dates_normalise_like_date_d() {
        assert_eq!(normalize_date("2026-11-05"), "2026-11-05");
        assert_eq!(normalize_date("2026-1-5"), "2026-01-05");
        assert_eq!(normalize_date("05.11.2026"), "2026-11-05");
        assert_eq!(normalize_date("5.11.2026"), "2026-11-05");
        assert_eq!(normalize_date("05.11.26"), "2026-11-05");
        assert_eq!(normalize_date("05.11.99"), "1999-11-05");
        // The shell kept whatever `date -d` could not parse.
        assert_eq!(normalize_date("tomorrow"), "tomorrow");
        assert_eq!(normalize_date("2026-02-31"), "2026-02-31");
        assert_eq!(normalize_date(""), "");
    }

    #[test]
    fn previous_day_is_the_jq_prevday() {
        assert_eq!(previous_day("2026-11-03").as_deref(), Some("2026-11-02"));
        assert_eq!(previous_day("2026-03-01").as_deref(), Some("2026-02-28"));
        assert_eq!(previous_day("2024-03-01").as_deref(), Some("2024-02-29"));
        assert_eq!(previous_day("2026-1-1").as_deref(), Some("2025-12-31"));
        assert_eq!(previous_day("03.11.2026"), None);
        assert_eq!(previous_day("2026-02-31"), None);
    }
}
