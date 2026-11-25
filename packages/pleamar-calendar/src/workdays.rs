//! The production calendar from isdayoff.ru.
//!
//! `workdays_json` in the shell, with the same country switch as holidays:
//!
//! - `workdays-YEAR-MONTH-CC.txt` caches the raw digit string for 24 h. The
//!   name really repeats the year (`workdays-2026-2026-11-RU.txt`, because
//!   `$YEAR` and `$MONTH` both go into it); that is the shell's file and the
//!   port keeps it.
//! - The answer is one digit per day: `0` working, `1` non-working, `2` a
//!   shortened day, `4` a moved working day. Only the non-zero days become
//!   `{date, code}` records.
//! - The body is cached raw without a trailing newline, and is not cached at
//!   all unless it is all digits (`work calendar gave no day codes`).
//! - A failed request is `work calendar request failed: <curl's last stderr
//!   line>` and does not fail the events.

use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::cache;
use crate::date::Month;
use crate::failure::Failure;
use crate::http::Http;

const TTL_SECS: i64 = 86_400;

pub struct Resolved {
    pub workdays: Value,
    pub error: Option<String>,
}

pub fn resolve(
    country: &str,
    month: &Month,
    cache_dir: &Path,
    base: &str,
    http: &Http,
    now: i64,
) -> Result<Resolved, Failure> {
    if country.is_empty() {
        return Ok(empty());
    }
    let path = cache_file(cache_dir, month, country);

    if cache::fresh(&path, now, TTL_SECS) {
        if let Some(body) = cache::read_text(&path) {
            return Ok(Resolved {
                workdays: decode(&body, month),
                error: None,
            });
        }
    }

    let url = format!(
        "{base}?year={}&month={}&cc={country}",
        month.year_text(),
        month.month_text()
    );
    // A failed request is an error field, not a failed sample.
    let body = match http.get(&url) {
        Ok(body) => body,
        Err(crate::http::FetchError::Interrupted) => return Err(Failure::Interrupted),
        Err(crate::http::FetchError::Message(text)) => {
            return Ok(Resolved {
                workdays: Value::Array(Vec::new()),
                error: Some(format!("work calendar request failed: {text}")),
            });
        }
    };

    // The shell's `$(< body)` dropped trailing newlines, then
    // `[[ body =~ ^[0-9]+$ ]]`: one line of digits and nothing else.
    let body = body.trim_end_matches('\n');
    if body.is_empty() || !body.bytes().all(|byte| byte.is_ascii_digit()) {
        return Ok(Resolved {
            workdays: Value::Array(Vec::new()),
            error: Some("work calendar gave no day codes".to_string()),
        });
    }

    // `printf '%s' "$body" > tmp`: no newline in this cache.
    if let Err(error) = cache::write_atomic(&path, body.as_bytes(), "workdays") {
        eprintln!("calendar: workdays cache write failed: {error}");
    }

    Ok(Resolved {
        workdays: decode(body, month),
        error: None,
    })
}

pub fn cache_file(cache_dir: &Path, month: &Month, country: &str) -> PathBuf {
    cache_dir.join(format!(
        "workdays-{}-{}-{}.txt",
        month.year_text(),
        month.name(),
        country
    ))
}

/// The shell's awk + sed: every character that is not `0` becomes
/// `{"date":"YYYY-MM-DD","code":N}`, day one being the first character.
///
/// All-zero input is `[]`. (The shell's awk printed nothing and `sed` wrapped
/// nothing, leaving `WORKDAYS_JSON` empty, which made the following jq call
/// fail and the worker print a truncated line; a valid empty array is the only
/// faithful rendering of "no day codes for this month".)
fn decode(body: &str, month: &Month) -> Value {
    let mut workdays = Vec::new();
    for line in body.split('\n') {
        for (index, character) in line.chars().enumerate() {
            let Some(code) = character.to_digit(10) else {
                // The raw ask is digits; a hand-edited cache with other bytes
                // must not produce invalid JSON.
                continue;
            };
            if code == 0 {
                continue;
            }
            let mut map = Map::new();
            map.insert(
                "date".to_string(),
                Value::String(format!(
                    "{}-{:02}-{:02}",
                    month.year_text(),
                    month.number,
                    index + 1
                )),
            );
            map.insert("code".to_string(), Value::from(code));
            workdays.push(Value::Object(map));
        }
    }
    Value::Array(workdays)
}

fn empty() -> Resolved {
    Resolved {
        workdays: Value::Array(Vec::new()),
        error: None,
    }
}
